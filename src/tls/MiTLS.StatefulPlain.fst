module MiTLS.StatefulPlain
open MiTLS

open FStar.Seq
open FStar.Bytes
open FStar.Error

open MiTLS.TLSError
open MiTLS.TLSConstants
open MiTLS.TLSInfo
open MiTLS.Content

module Range = MiTLS.Range
open MiTLS.Range

// Defines additional data and an abstract "plain i ad rg" plaintext
// typed interface from the more concrete & TLS-specific type
// "Content.fragment i". (Type abstraction helps with modularity, but
// not with privacy in this case.)

// This module is used only up to TLS 1.2

type id = i:id { ID12? i }

let ad_Length i = 3
val makeAD: i:id -> ct:contentType -> Tot (lbytes (ad_Length i))
let makeAD i ct =
    (ctBytes ct) @| versionBytes (pv_of_id i)

// StatefulLHAE should be parametric in this type (or its refinement), but that'd be heavy
// here, the refinement ensures we never fail parsing indexes to retrieve ct
// that said, we should entirely avoid parsing it.
type adata (i:id) = b:bytes { exists ct. b == makeAD i ct }

let lemma_12 (i:id) : Lemma (~(PlaintextID? i)) = ()

#set-options "--admit_smt_queries true"
val parseAD: i:id -> ad:adata i -> Tot contentType
let parseAD i ad =
  lemma_12 i;
  let pv = pv_of_id i in
  let bct, bver = FStar.Bytes.split ad 1ul in
  match parseCT bct, parseVersion bver with
  | Correct ct, Correct ver ->
    assert (ver = pv);
    ct
#reset-options

#set-options "--z3rlimit 10 --initial_fuel 0 --max_fuel 0 --initial_ifuel 0 --max_ifuel 0 --admit_smt_queries true"
val lemma_makeAD_parseAD: i:id -> ct:contentType -> Lemma
  (requires (True))
  (ensures (parseAD i (makeAD i ct) = ct))
  [SMTPat (makeAD i ct)]
let lemma_makeAD_parseAD i ct = ()
#reset-options

(*** plaintext fragments ***)

type is_plain (i: id) (ad: adata i) (rg:range) (f: fragment i) =
  fst (ct_rg i f) = parseAD i ad /\ wider rg (snd (ct_rg i f))

// naming: we switch from fragment to plain as we are no longer TLS-specific
// XXX JP, NS: figure our whether we want to make the type below abstract, and
// if so, how
type plain (i:id) (ad:adata i) (rg:range) = f:fragment i{is_plain i ad rg f}
//  { (parseAD i ad, rg) = Content.ct_rg i f }

// Useful if the parameters [id], [ad] and [rg] have been constructed _after_
// the fragment [f]; allows solving some scoping errors.
val assert_is_plain: i:id -> ad:adata i -> rg:range -> f:fragment i ->
  Pure (plain i ad rg) (requires (is_plain i ad rg f)) (ensures (fun _ -> true))
let assert_is_plain i ad rg f = f

val ghost_repr: #i:id -> #ad:adata i -> #rg:range -> plain i ad rg -> GTot (rbytes rg)
let ghost_repr #i #ad #rg pf =
  (Content.ghost_repr #i pf <: bytes) // Workaround for #543

val repr: i:id{ ~(safeId i)} -> ad:adata i -> rg:range -> p:plain i ad rg -> Tot (b:rbytes rg {b = ghost_repr #i #ad #rg p})
let repr i ad rg f = Content.repr i f

type wf_ad_rg i ad rg =
  wider Range.fragment_range rg
  /\ (parseAD i ad = Change_cipher_spec ==> wider rg (point 1))
  /\ (parseAD i ad = Alert ==> wider rg (point 2))

type wf_payload_ad_rg i ad rg (b:rbytes rg) =
  (parseAD i ad = Change_cipher_spec ==> b = ccsBytes)
  /\ (parseAD i ad = Alert ==> length b = 2 /\ Correct? (Alert.parse b))

val mk_plain: i:id{ ~(authId i)} -> ad:adata i -> rg:Range.frange i { wf_ad_rg i ad rg } ->
    b:rbytes rg { wf_payload_ad_rg i ad rg b } ->
  Tot (p:plain i ad rg {b = ghost_repr #i #ad #rg p})

#set-options "--z3rlimit 20"
let mk_plain i ad rg b = Content.mk_fragment i (parseAD i ad) rg b

// should go to StatefulLHAE

type cipher (i:id) = b:bytes {Range.valid_clen i (length b)}
