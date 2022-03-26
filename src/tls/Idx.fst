module Idx

open Mem
//open Pkg

module DM = FStar.DependentMap
module MDM = FStar.Monotonic.DependentMap

type info = TLSInfo.logInfo

// 17-12-08 we considered separating "honesty" from the more ad hoc parts of this file.

/// TLS-SPECIFIC KEY INDICES
/// --------------------------------------------------------------------------------------------------
///
/// We provide an instance of ipkg to track key derivation (here using constant labels)
/// these labels are specific to HKDF, for now strings e.g. "e exp master".
type label = s:string{Bytes.length (Bytes.bytes_of_string s) < 250}

/// the middle extraction takes an optional DH secret, identified by this triple
/// we use our own datatype to simplify typechecking
type id_dhe =
  | NoIDH
  | IDH:
    gX: CommonDH.dhi ->
    gY: CommonDH.dhr gX -> id_dhe

// The "ciphersuite hash algorithms" eligible for TLS 1.3 key derivation.
// We will be more restrictive.
type kdfa = a:EverCrypt.HMAC.supported_alg { Spec.Hash.Definitions.is_md a }

/// Runtime key-derivation parameters, to be adjusted.
///
/// HKDF defines an injective function from label * context to bytes, to be used as KDF indexes.
///
type context =
  | Extract: context // TLS extractions have no label and no context; we may separate Extract0 and Extract2
  | ExtractDH: v:id_dhe -> context // This is Extract1 (the middle extraction)
  | Expand: context // TLS expansion with default hash value
  | ExpandLog: // TLS expansion using hash of the handshake log
    info: TLSInfo.logInfo (* ghost, abstract summary of the transcript *) ->
    hv: Hashing.Spec.anyTag (* requires stratification *) -> context
// 18-09-25 should info be HandshakeLog.hs_transcript? 


/// Underneath, HKDF takes a "context" and a required length, with
/// disjoint internal encodings of the context:
/// [HKDF.format #ha label digest len]

type id_psk = nat // external application PSKs only; we may also set the usage's maximal recursive depth here.

// The `[@ Gc]` attribute instructs KaRaMeL to translate the `pre_id` field as a pointer,
// otherwise it would generate an invalid type definition.
[@ Gc]
type pre_id =
  | Preshared:
      a: kdfa (* fixing the hash algorithm *) ->
      id_psk  ->
      pre_id
  | Derive:
      i:pre_id (* parent index *) ->
      l:label (* static part of the derivation label *) ->
      context (* dynamic part of the derivation label *) ->
      pre_id

// always bound by the index (and also passed concretely at creation-time).
val ha_of_id: i:pre_id -> kdfa
let rec ha_of_id = function
  | Preshared a _ -> a
  | Derive i lbl ctx -> ha_of_id i

// placeholders
assume val idh_of_log: TLSInfo.logInfo -> id_dhe
assume val summary: Bytes.bytes -> TLSInfo.logInfo

// concrete transcript digest
let digest_info (a:kdfa) (info:TLSInfo.logInfo) (hv: Hashing.Spec.anyTag) =
  exists (transcript: Hashing.hashable a).
    // Bytes.length hv = hash_len a /\
    hv = Hashing.h a transcript /\
    Hashing.CRF.hashed a transcript /\
    info = summary transcript

/// stratified definition of id required.
///
/// we will enforce
/// * consistency on the hash algorithm
/// * monotonicity of the log infos (recursively including earlier resumption logs).
/// * usage restriction: the log after DH must include the DH identifier of the parent.
///   (Hence, we should either forbid successive DHs or authenticate them all.)
///
val pre_wellformed_id: pre_id -> Type0
let rec pre_wellformed_id = function
  | Preshared a _ -> True
  | Derive i l (ExpandLog info hv) -> pre_wellformed_id i /\ digest_info (ha_of_id i) info hv
  | Derive i lbl ctx ->
      //TODO "ctx either extends the parent's, or includes its idh" /\
      pre_wellformed_id i

/// Indexes are used concretely in model code, so we
/// erase them conditionally on model
type id = 
  (if model then i:pre_id {pre_wellformed_id i}
  else unit)

unfold type wellformed_id (i:id) =
  (if model then pre_wellformed_id i else True)

unfold let wellformed_derive (i:id) (l:label) (ctx:context) =
  (if model then pre_wellformed_id (Derive i l ctx) else True)

unfold let derive (i:id) (l:label) (ctx:context{wellformed_derive i l ctx}) : id =
  (if model then Derive i l ctx else ())

type honest_idh (c:context) =
  ExtractDH? c /\ IDH? (ExtractDH?.v c) /\
  (let ExtractDH (IDH gX gY) = c in CommonDH.honest_dhr gY)

/// We use a global honesty table for all indexes. Inside ipkg, we
/// assume all index types are defined in the table below. We assume
/// write access to this table is public, but the following global
/// invariant must be enforced: if i is corrupt then all indexes
/// derived from i are also corrupt
/// ---EXCEPT if ctx is ExtractDH g gx gy with CommonDH.honest_dhr gy
///
type honesty_invariant (m:DM.t id (MDM.opt (fun _ -> bool))) =
  (forall (i:id) (l:label) (c:context{wellformed_derive i l c}).
  {:pattern (DM.sel m (Derive i l c))}
  Some? (DM.sel m (derive i l c)) ==> Some? (DM.sel m i) /\
  (DM.sel m i = Some false ==> (honest_idh c \/ DM.sel m (derive i l c) = Some false)))

//17-12-08 removed [private] twice, as we need to recall it in ODH :(
type i_honesty_table =
  MDM.t tls_honest_region id (fun (t:id) -> bool) honesty_invariant
let h_table = if model then i_honesty_table else unit

let honesty_table: h_table =
  if model then
    MDM.alloc #id #(fun _ -> bool) #honesty_invariant #tls_honest_region ()
  else ()

// Registered is monotonic
type registered (i:id) =
  (if model then
    let log : i_honesty_table = honesty_table in
    witnessed (MDM.defined log i)
  else True)

type regid = i:id{registered i}

type honest (i:id) =
  (if model then
    let log: i_honesty_table = honesty_table in
    witnessed (MDM.contains log i true)
  else False)

type corrupt (i:id) =
  (if model then
    let log : i_honesty_table = honesty_table in
    witnessed (MDM.contains log i false)
  else True)

assume val bind_squash_st:
  #a:Type ->
  #b:Type ->
  #pre:(mem -> Type) ->
  squash a ->
  $f:(a -> ST (squash b) (requires (fun h0 -> pre h0)) (ensures (fun h0 _ h1 -> h0 == h1))) ->
  ST (squash b) (requires (fun h0 -> pre h0)) (ensures (fun h0 _ h1 -> h0 == h1))
#reset-options "--smtencoding.valid_intro true --smtencoding.valid_elim true"
#set-options "--z3rlimit 100"
inline_for_extraction
private let lemma_honest_or_corrupt (i:regid)
  :ST unit (requires (fun _ -> True)) (ensures (fun h0 _ h1 -> h0 == h1 /\ (honest i \/ corrupt i)))
  = if model then begin
      let log:i_honesty_table = honesty_table in
      let aux :(h:mem) -> (sum (MDM.contains log i true h) (~ (MDM.contains log i true h)))
               -> ST (squash (honest i \/ corrupt i))
	            (requires (fun h0     -> h == h0))
		        (ensures (fun h0 _ h1 -> h0 == h1))
        = fun _ x ->
	  recall log;
	  testify (MDM.defined log i);
	  match x with
	  | Left  h ->
	    MDM.contains_stable log i true;
	    mr_witness log (MDM.contains log i true)
	  | Right h ->
	    MDM.contains_stable log i false;
	    mr_witness log (MDM.contains log i false)
      in
      let h = get () in
      let y = Squash.bind_squash (Squash.get_proof (l_or (MDM.contains log i true h) (~ (MDM.contains log i true h)))) (fun y -> y) in
      bind_squash_st y (aux h)
    end
    else ()

inline_for_extraction
private let lemma_not_honest_and_corrupt (i:regid)
  :ST unit (requires (fun _ -> True)) (ensures (fun h0 _ h1 -> h0 == h1 /\ (~ (honest i /\ corrupt i))))
  = if model then begin
      let log:i_honesty_table = honesty_table in
      let aux :(sum (honest i /\ corrupt i) (~ (honest i /\ corrupt i)))
               -> ST (squash (~ (honest i /\ corrupt i)))
	            (requires (fun h0     -> True))
		    (ensures (fun h0 _ h1 -> h0 == h1))
        = fun x ->
	  recall log;
	  testify (MDM.defined log i);
	  match x with
	  | Left  h -> testify (MDM.contains log i true); testify (MDM.contains log i false)
	  | Right h -> ()
      in
      let y = Squash.bind_squash (Squash.get_proof (l_or (honest i /\ corrupt i) (~ (honest i /\ corrupt i)))) (fun y -> y) in
      bind_squash_st y aux
    end
    else ()

(*
 * AR: 04/01: A stateful version of the lemma_honest_corrupt
 *)
inline_for_extraction
let lemma_honest_corrupt_st (i:regid)
  :ST unit (requires (fun _ -> True)) (ensures (fun h0 _ h1 -> h0 == h1 /\ (honest i <==> (~ (corrupt i)))))
  = lemma_honest_or_corrupt i; lemma_not_honest_and_corrupt i

// ADL: difficult to prove, relies on an axiom outside the current formalization of FStar.Monotonic
inline_for_extraction
let lemma_honest_corrupt (i:regid)
  : Lemma (honest i <==> ~(corrupt i)) =
  admit()

#set-options "--z3rlimit 100" 
inline_for_extraction
let lemma_corrupt_invariant (i:regid) (lbl:label) (ctx:context)
  : ST unit
  (requires fun h0 -> ~(honest_idh ctx) /\
    wellformed_derive i lbl ctx /\ registered (derive i lbl ctx))
  (ensures fun h0 _ h1 -> h0 == h1 /\
    corrupt i ==> corrupt (derive i lbl ctx))
  =
  if not model then () else
  begin
    lemma_honest_corrupt i;
    lemma_honest_corrupt (derive i lbl ctx);
    let log : i_honesty_table = honesty_table in
    recall log;
    testify (MDM.defined log i);
    match MDM.lookup log i with
    | Some true -> ()
    | Some false ->
      let m = !log in
      // No annotation, but the proof relies on the global log invariant
      testify (MDM.defined log (derive i lbl ctx));
      MDM.contains_stable log (derive i lbl ctx) false;
      mr_witness log (MDM.contains log (derive i lbl ctx) false)
  end

inline_for_extraction noextract
let get_honesty (i:id {registered i}) : ST bool
  (requires fun h0 -> True)
  (ensures fun h0 b h1 -> h0 == h1 /\ (b <==> honest i))
  = if model then
      let log : i_honesty_table = honesty_table in
      recall log;
      testify (MDM.defined log i);
      match MDM.lookup log i with
      | Some b ->
        (*
         * AR: 03/01
         *     We need to show b <==> honest i
         *     The direction b ==> honest i is straightforward, from the postcondition of MDM.lookup
         *     For the other direction, we need to do a recall on the witnessed predicate in honest i
         *     One way is to go through squash types, using a bind_squash_st axiom above
         *)
        let aux (b:bool) : ST unit
                             (requires (fun h0     -> MDM.contains log i b h0))
	    		     (ensures (fun h0 _ h1 -> h0 == h1 /\ (honest i ==> b)))
          = let f :(b:bool) -> (sum (honest i) (~ (honest i)))
	           -> ST (squash (honest i ==> b2t b))
	                (requires (fun h0      -> MDM.contains log i b h0))
                        (ensures  (fun h0 _ h1 -> h0 == h1))
	      = fun _ x ->
	        match x with
	        | Left  h -> Squash.return_squash h; testify (MDM.contains log i true)
	        | Right h -> Squash.return_squash h; assert (~ (honest i))
	    in
	    let y = Squash.bind_squash (Squash.get_proof (l_or (honest i) (~ (honest i)))) (fun y -> y) in
	    bind_squash_st y (f b)
        in
        aux b;
        b
    else false

// TODO(adl) preservation of the honesty table invariant
let rec lemma_honesty_update (m:DM.t id (MDM.opt (fun _ -> bool)))
  (i:regid) (l:label) (c:context) (b:bool{b <==> honest i})
  : Lemma (requires wellformed_derive i l c)
    (ensures honesty_invariant (DM.upd m (derive i l c) (Some b)))
// : Lemma (requires Some? (m i ) /\ None? (m (Derive i l c)) /\ m i == Some false ==> not b)
//         (ensures honesty_invariant (MDM.upd m (Derive i l c) b))
  = admit() // easy

#reset-options "--admit_smt_queries true"
inline_for_extraction noextract
let register_derive (i:regid) (l:label) (c:context)
  : ST (regid * bool)
  (requires fun h0 -> wellformed_derive i l c)
  (ensures fun h0 (i', b) h1 ->
    (if model then modifies_one tls_honest_region h0 h1 else h0 == h1)
    /\ i' == derive i l c
    /\ (b2t b <==> honest i'))
  =
  if model then
    let i':id = Derive i l c in
    let log : i_honesty_table = honesty_table in
    recall log;
    match MDM.lookup log i' with
    | Some b ->
//      MDM.contains_stable log i' true;
//      mr_witness log (MDM.contains log i' true);
      assume (registered i'); // FIXME
      lemma_honest_corrupt i'; (i', b)
    | None ->
      let b = get_honesty i in
      let h = get () in
//      lemma_honesty_update (sel h log) i l c b;
      MDM.extend log i' b;
      lemma_honest_corrupt i';
      (i', b)
  else ((), false)
#reset-options

// 17-10-21 WIDE/NARROW INDEXES (old)
//
// We'd rather keep wide indexes secret.  Internally, for each salt
// index, we maintain a table from (g, gX, gY) to PRFs, with some
// sharing.  (The sharing may be public, but not wide indexes values
// are not.)  Informally this is sound because our limited use of the
// tables does not depend on their sharing.
//
// The danger of overly precise indexes is that, ideally, we may
// separate instances that use the same concrete keys---in our case
// this does not matter because security does not depend on their
// sharing.

noextract
let ii: Pkg.ipkg = // (#info:Type0) (get_info: id -> info) =
  Pkg.Idx id registered honest get_honesty
