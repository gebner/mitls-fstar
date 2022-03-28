module Handshake

open FStar.Seq
open FStar.Error
open FStar.Bytes

open Mem
open TLSError
open TLSInfo
open TLSConstants
// open HandshakeMessages // for the message syntax
open HandshakeLog // for Outgoing
open Epochs
open Mem

module U32 = FStar.UInt32
module MS = FStar.Monotonic.Seq
module HS = FStar.HyperStack
module Nego = Negotiation
module Secret = Handshake.Secret
// added back to simplify the diff
module KeySchedule = Handshake.Secret
module HMAC_UFCMA = HMAC.UFCMA
module HSM = HandshakeMessages
module HSL = HandshakeLog
module CH = Parsers.ClientHello
module SH = Parsers.ServerHello
// For readabililty, we try to open/abbreviate fewer modules

(* A flag for runtime debugging of Handshake data.
   The F* normalizer will erase debug prints at extraction
   when this flag is set to false. *)
val discard: bool -> ST unit
  (requires (fun _ -> True))
  (ensures (fun h0 _ h1 -> h0 == h1))
let discard _ = ()
let print s = discard (IO.debug_print_string ("HS | "^s^"\n"))
unfold val trace: s:string -> ST unit
  (requires (fun _ -> True))
  (ensures (fun h0 _ h1 -> h0 == h1))
unfold let trace = if DebugFlags.debug_HS then print else (fun _ -> ())

// TODO : implement resumption
//val getCachedSession: cfg:config -> ch:ch -> ST (option session)
//  (requires (fun h -> True))
//  (ensures (fun h0 i h1 -> True))
//let getCachedSession cfg cg = None


// *** internal stuff: state machine, reader/writer counters, etc.

/// We keep the handshake state, now including TLS 1.3 key schedule
/// state, and some digests (from time of hashing to time of use).
/// TODO: we need to know the hash algorithm matches HandshakeLog's.

//19-05-11 should be bound in Transcript
// some states keep digests (irrespective of their hash algorithm)
type digest = Hashing.anyTag //  l:bytes{length l <= 32}

#set-options "--admit_smt_queries true"
type machineState =
  | C_Idle
  | C_wait_ServerHello: // waiting for plaintext handshake
    psks: list (i:Idx.id{~(Secret.no_psk i)}) ->
    groups: list CommonDH.group -> // ghost summary of our offer
    ks: Secret.c13_wait_ServerHello psks groups -> machineState

  | C13_wait_Finished1: // TLS 1.3 waiting for encrypted handshake
    i:   Secret.hs_id ->
    ams: Secret.ams (Secret.ams_of_hms i) ->
    cfk: Secret.fink (Secret.cfk_of_hms i) ->
    sfk: Secret.fink (Secret.sfk_of_hms i) -> machineState

  | C13_sent_EOED: // TLS 1.3 #20 aggravation, optional from C13_wait_Finished1
    i:   Secret.hs_id ->
    ams: Secret.ams (Secret.ams_of_hms i) ->
    cfk: Secret.fink (Secret.cfk_of_hms i) ->
    digest (* _EOED *) ->
    option HSM.cr13 -> machineState

  | C13_complete: // TLS 1.3 waiting for post-handshake messages (TBC rekeying)
    i:   Secret.ams_id ->
//    rms: Secret.secret (rms_of_ams i tr) (* for accepting resumption tickets *) ->
    machineState

  | C12_wait_CCS1 of digest      // TLS resume, digest to be authenticated by server
  | C12_wait_R_Finished1 of digest // TLS resume, digest to be authenticated by server
  | C12_wait_ServerHelloDone:
    // cr:random ->
    machineState

  | C12_wait_CCS2: // TLS classic
    ks: Secret.ks12_state ->
    digest_Finished1: digest -> // to be authenticated in the server Finished
    machineState

  | C12_wait_Finished2: // TLS classic
    ks: Secret.ks12_state ->
    digest_Finished1: digest -> // to be authenticated in the server Finished
    machineState

  | C_Complete // TODO add state

  | S_Idle

  | S13_sent_ServerHello:      // TLS 1.3, intermediate state to encryption
    i: Idx.id -> // Secret.esId ->
    idh: Idx.id_dhe ->
    ks: Secret.s13_wait_ServerHello i idh -> machineState


  | S_wait_EOED                // Waiting for EOED
  | S_wait_Finished2 of digest // TLS 1.3, digest to be MACed by client
  | S_wait_CCS1                // TLS classic
  | S_wait_Finished1 of digest // TLS classic, digest to the MACed by client
  | S_wait_CCS2 of digest      // TLS resume (CCS)
  | S_wait_CF2 of digest       // TLS resume (CF)
  | S_Complete


// 17-03-24 considered using instead "if role = Client then
// clientState else serverServer" but that may break extraction to
// Karamel and complicate typechecking; we could also use refinements.

// Removed error states, consider adding again to ensure the machine is stuck?

// TODO add ghost transcript and the Transcript state; unclear where
// they fit, e.g. above or under machine states.

noeq type hs' = | HS:
  #region: rgn {is_hs_rgn region} ->
  r: role ->
  nego: Nego.t region r ->
  log: HandshakeLog.t {HandshakeLog.region_of log = region} ->
  //17-12-02 ks: Secret.ks (*region*) ->
  epochs: epochs region (Nego.nonce nego) ->
  state: ref machineState {HS.frameOf state = region} -> // state machine; should be opaque and depend on r.
  hs'

let hs = hs' //17-04-08 around .fsti limitation

let nonce         (s:hs) = Nego.nonce s.nego
let region_of     (s:hs) = s.region
let role_of       (s:hs) = s.r
let random_of     (s:hs) = nonce s
let config_of     (s:hs) = Nego.local_config s.nego
let version_of    (s:hs) = Nego.version s.nego
let get_mode (s:hs) = Nego.getMode s.nego
let is_server_hrr (s:hs) = Nego.is_server_hrr s.nego
let is_0rtt_offered (s:hs) =
  let mode = get_mode s in Nego.zeroRTToffer mode.Nego.n_offer
let is_post_handshake (s:hs) =
  match !s.state with | C_Complete | S_Complete -> true | _ -> false
let epochs_of (s:hs) = s.epochs

(* WIP on the handshake invariant
let inv (s:hs) (h:HS.mem) =
  // let context = Negotiation.context h hs.nego in
  let transcript = HandshakeLog.transcript h hs.log in
  match HS.sel h s.state with
  | C_Wait_ServerHello ->
      hs.role = Client /\
      transcript = [clientHello hs.nonce offer] /\
      "nego in Wait_ServerHello" /\
      "ks in wait_ServerHello"
  | _ -> True
*)

// the states of the HS sub-module will be subject to a joint invariant
// for example the Nego state is a function of ours.


let stateType (s:hs) = seq (epoch s.region (nonce s)) * machineState
let stateT (s:hs) (h:HS.mem) : GTot (stateType s) = (logT s h, sel h s.state)

let forall_epochs (s:hs) h (p:(epoch s.region (nonce s) -> Type)) =
  (let es = logT s h in
   forall (i:nat{i < Seq.length es}).{:pattern (Seq.index es i)} p (Seq.index es i))
//epochs in h1 extends epochs in h0 by one

(*
#set-options "--admit_smt_queries true"
let fresh_epoch h0 s h1 =
  let es0 = logT s h0 in
  let es1 = logT s h1 in
  Seq.length es1 > 0 &&
  es0 = Seq.slice es1 0 (Seq.length es1 - 1)

(* vs modifies clauses? *)
(* let unmodified_epochs s h0 h1 =  *)
(*   forall_epochs s h0 (fun e ->  *)
(*     let rs = regions e in  *)
(*     (forall (r:rid{Set.mem r rs}).{:pattern (Set.mem r rs)} Map.sel h0 r = Map.sel h1 r)) *)
*)

let latest h (s:hs{Seq.length (logT s h) > 0}) = // accessing the latest epoch
  let es = logT s h in
  Seq.index es (Seq.length es - 1)

// separation policy: the handshake mutates its private state,
// only depends on it, and only extends the log with fresh epochs.

// placeholder, to be implemented as a stateful property.
let completed #rgn #nonce e = True

// consider adding an optional (resume: option sid) on the client side
// for now this bit is not explicitly authenticated.

p/// Handshake invariant (TBC)
/// HS machine state, e.g.
/// | C_wait_ServerHello ->
///   related states for Nego, KS, HSL
///   transcript = [...] /\
///   negostate = nego_of_transcript config transcript
///
/// nego lookups are readers functions
/// (returning a result and its witness---or just mon. transcript?)
/// defined once the transcript is big enough.
///
// WIP on the handshake invariant; see also hs_inv below!
// let inv (s:hs) (h:HyperStack.mem) =
//   let n = Negotiation.negotiationState h hs.nego in // let context = Negotiation.context h hs.nego in
//   let tr = HSL.transcript h hs.log in
//   let control = HyperStack.sel h s.state in
//   let kst = Secret.state h hs.ks in
//   (Correct nego = Nego.replay transcript /\
//   (match control with
//   | C_Idle ->
//       // create...client_ClientHello
//       hs.role = Client /\
//       tr = [] /\
//       writing h hs.nego /\
//       C_Init? kst // unclear we care about its nonce, otherwise see client_ClientHello

//   | C_wait_ServerHello ->
//       // client_ClientHello...(client_HelloRetryRequest \/ client_ServerHello)
//       // with a branch on proposing TLS 1.3 or not
//       hs.role = Client /\
//       tr = [clientHello hs.nonce (Negotiation.offer_of nego)] /\
//       ( match kst with
//         | C_13_wait_SH (*cr*) esl gs -> "esl and gs compatible with offer"
//         | _ -> False )
// (*
//   | C13_wait_Finished1 ->
//       hs.role = Client /\
//       tr = [clientHello hs.nonce (Negotiation.offer_of nego); ServerHello ...] /\
//       // When do we care about precise indexes? We plan to sync
//       // with Secret on indexes, rather than transcripts
//       // (abstract for Secret).  we'll need to keep around at
//       // least the PSK index in addition to the log
//       match kst with
//       | C_13_wait_SF (*subsumed by i?: alpha*) i1 transcript_sh (*for deriving the indexes of*) cfk sfk ams ->
//           i1 = i_hs_secret_of_transcript tr /\
//           transcript_sh = tr `up_to` ServerHello?
//           "something about local writers?"
//       | _ -> False
// *)
//   | S_Idle ->
//       hs.role = Server /\
//       tr = [] /\
//       S_Init? kst

//   | _ -> True
//   ))

(*
/// i.e. we expect this definition in Secret
/// to keep C_13_wait_SH abstract, we'd need to record the

| C_13_wait_SH:
    // *overwritten* symmetric extracts for the PSKs we are proposing
    // (the indexes are a function of those of the PKSs)
    esl: list (i:esId{~(NoPSK? i)} & es i) ->
    // *overwritten* when hello_retry
    // private exponents for the honestly-generated shares we are proposing
    gs: list (g:CommonDH.group & CommonDH.keyshare g) -> ks_client_state
// --->

| C_13_wait_SF:
    i1: id (* ghost, synchronized with HS invariant *) ->
    transcript: (*ghost*) list msg ->
    cfk: MAC.UFCMA.key (derive_cfk1 i1 transcript) ->
    sfk: MAC.UFCMA.key (derive_sfk1 i1 transcript) ->
    ams: KDF.secret (derive_ams1 i1) -> ks_client_state
*)


// Well-formed logs are all prefixes of (Epoch; Complete)*; Error
// This crucially assumes that TLS keeps track of OutCCS and InCCSAck
// so that it knows which reader & writer to use (not always the latest ones):
// - within InCCSAck..OutCCS, we still use the older writer
// - within OutCCS..InCCSAck, we still use the older reader
// - otherwise we use the latest readers and writers

// abstract invariant; depending only on the HS state (not the epochs state)
// no need for an epoch states invariant here: the HS never modifies them

assume val hs_invT : s:hs -> epochs:seq (epoch s.region (nonce s)) -> machineState -> Type0

let hs_inv (s:hs) (h: HS.mem) = True
(* 17-04-08 TODO deal with inferred logic qualifiers
  hs_invT s (logT s h) (sel h (HS?.state s))  //An abstract invariant of HS-internal state
  /\ Epochs.containsT s.epochs h                //Nothing deep about these next two, since they can always
  /\ HS.contains s.state.ref ( h)                 //be recovered by 'recall'; carrying them in the invariant saves the trouble

//A framing lemma with a very trivial proof, because of the way stateT abstracts the state-dependent parts
*)

#set-options "--admit_smt_queries true"
let frame_iT_trivial  (s:hs) (rw:rw) (h0:HS.mem) (h1:HS.mem)
  : Lemma (stateT s h0 = stateT s h1  ==>  iT s rw h0 = iT s rw h1)
  = ()

//Here's a framing on stateT connecting it to the region discipline
let frame_stateT  (s:hs) (rw:rw) (h0:HS.mem) (h1:HS.mem) (mods:Set.set rid)
  : Lemma
    (requires
      HS.modifies mods ( h0) ( h1) /\
      HS.live_region h0 s.region /\
      not (Set.mem s.region mods))
    (ensures stateT s h0 = stateT s h1)
  = ()

//This is probably the framing lemma that a client of this module will want to use
let frame_iT  (s:hs) (rw:rw) (h0:HS.mem) (h1:HS.mem) (mods:Set.set rid)
  : Lemma
    (requires
      HS.modifies mods ( h0) ( h1) /\
      HS.live_region h0 s.region /\
      not (Set.mem s.region mods))
    (ensures stateT s h0 = stateT s h1 /\ iT s rw h0 = iT s rw h1)
=
  frame_stateT s rw h0 h1 mods;
  frame_iT_trivial s rw h0 h1



// factored out; indexing to be reviewed
val register: hs -> KeySchedule.recordInstance -> St unit
let register hs keys =
    let ep = //? we don't have a full index yet for the epoch; reuse the one for keys??
      let h = Nego.Fresh ({ Nego.session_nego = None }) in
      // Epochs.recordInstanceToEpoch #hs.region #(nonce hs) h keys in // just coercion
      let KeySchedule.StAEInstance #id r w = keys in
      Epochs.recordInstanceToEpoch #hs.region #(nonce hs) h (Handshake.Secret.StAEInstance #id r w) in // just coercion
    Epochs.add_epoch hs.epochs ep // actually extending the epochs log

val export: hs -> KeySchedule.exportKey -> St unit
let export hs xk =
  trace "exporting a key";
  Monotonic.Seq.i_write_at_end hs.epochs.exporter xk

let xkeys_of hs = Monotonic.Seq.i_read hs.epochs.exporter

(* ------- Pure functions between offer/mode and their message encodings -------- *)

(*
let clientHello offer = // pure; shared by Client and Server
  let sid =
    match offer.co_resume with
    | None -> empty_bytes
    | Some x -> x
    in
  (* In Extensions: prepare client extensions, including key shares *)
  //17-03-30 where are the keyshares? How to convert them?
  let ext = Extensions.prepareExtensions
    offer.co_protocol_version
    offer.co_cipher_suites
    false false //17-03-30 ??
    offer.co_sigAlgs
    offer.co_namedGroups // list of named groups?
    None //17-03-30 ?? optional (cvd,svd)
    offer.co_client_shares // apparently at most one for now
    in
  {
    ch_protocol_version = offer.co_protocol_version;
    ch_client_random = offer.co_client_random;
    ch_sessionID = sid;
    ch_cipher_suites = offer.co_cipher_suites;
    ch_compressions = offer.co_compressions;
    ch_extensions = Some ext }
*)

(* -------------------- Handshake Client ------------------------ *)

// now in Secret: type binderId = HMAC_UFCMA.binderId

type btag (binderKey:(i:binderId & bk:KeySchedule.binderKey i)) =
  HMAC_UFCMA.tag (HMAC_UFCMA.HMAC_Binder (let (|i,_|) = binderKey in i))

val map_ST2: 'c -> ('c -> 'a -> KeySchedule.ST0 'b) -> list 'a -> KeySchedule.ST0 (list 'b)
let rec map_ST2 env f x = match x with
  | [] -> []
  | a::tl -> f env a :: map_ST2 env f tl

let compute_binder hs (bkey:(i:binderId & bk:KeySchedule.binderKey i)): ST (btag bkey)
    (requires fun h0 -> True)
    (ensures fun h0 _ h1 -> modifies_none h0 h1)  // we'll need a complete spec to determine the transcript
  =
  let (| bid, bk |) = bkey in
  let digest_CH0 = HandshakeLog.hash_tag #(binderId_hash bid) hs.log in
  HMAC_UFCMA.mac bk digest_CH0

let verify_binder hs (bkey:(i:binderId & bk:KeySchedule.binderKey i)) (tag:btag bkey) tlen: ST bool
    (requires fun h0 -> True)
    (ensures fun h0 _ h1 -> modifies_none h0 h1)
  =
  let (| bid, bk |) = bkey in
  let digest_CH0 = HandshakeLog.hash_tag_truncated #(binderId_hash bid) hs.log tlen in
  HMAC_UFCMA.verify bk digest_CH0 tag



// 17-11-25 -------------- experimental rewriting from here -----------------

// key state kept after sending clientHello
private type client_binders_state = list (i:id & info i * es i)


// For each proposed PSK, start keying and produce the binder tag.
//
// not yet tail-recursive (fix later with list processing)
// we could also output the binders instead of building a list.
private let rec client_Binder_loop hs (pskids: list (PSK.pskid * PSK.obfuscated_ticket_age)):
  ST (client_Binder_state * Extensions.binders)
  (requires fun h0 -> True
    // HSL contains the truncated hello message to be authenticated in
    // binders (satisfying their logical payloand) and these pskids
    // are all included in the offer
    )
  (ensures fun h0 (earlies, binders) h1 -> True
    // modifies "only creates local keys?"
    // if early was None and the list is non-empty, then early is the first early context
    )
=
  match pskids with
  | [] -> (early, binders)
  | (pskid, _obfuscated_age) :: pskids ->
      let (| i, info, es, bfk |) = Secret.compute_es_and_bfk pskid in
      let digest_truncated_ClientHello = HSL.hash_tag #(binderId_hash info) hs.log in
      let binder = HMAC_UFCMA.mac bfk digest_truncated_ClientHello in
      let earlies, binders = client_Binder_loop hs pskids in
      ((| i, info, es |) :: earlies), (binder :: binders)

// Compute and send the PSK binders if necessary; may be called both
// by client_ClientHello and client_HelloRetryRequest.  On the client
// side, we don't actually care about the presence or contents of
// Binders in the transcript.
val client_Binders: s:hs -> offer -> ST client_binders_state
  (requires fun h0 -> True
    // HSL contains the truncated hello message to be authenticated in
    // binders (satisfying their logical payloand)
    )
  (ensures fun h0 _ h1 ->
    // TODO modifies only the transcript
    // only dealing with Some? for now
    // we don't care about the presence and contents of Binders in the transcript
    let tr0 = HSL.transcript h0 hs.log in
    let tr1 = HSL.transcript h1 hs.log in
    if None? (Nego.find_clientPske offer)
    then tr1 = tr0
    else (exists (b:Extensions.binders). tr1 = tr0 @ [Binders b])
    )


let client_Binders hs offer =
  match Nego.resume hs.nego with
  | (_, []) -> () // No PSK, no binders
  | (_, pskl) ->
    let binderKeys = KeySchedule.ks_client_13_get_binder_keys hs.ks pskl in
    let binders = map_ST2 hs compute_binder binderKeys in
    HSL.send hs.log (Binders binders);
    earlies

/// 17-11-11 verification style? we hope to factor out most of the
/// pre/post in the invariant (but note we just called
/// HSL.next_fragment so the transcript has changed).
///
val client_ClientHello: s:hs -> i:id -> ST (result (HSL.outgoing i))
  (requires fun h0 ->
    let n = HS.sel h0 Nego.(s.nego.state) in
    let t = HSL.transcript h0 s.log in
    let k = HS.sel h0 s.ks.KeySchedule.state in
    match n with
    | Nego.C_Init nonce -> k = KeySchedule.(C (C_Init nonce)) /\ t = []
    | _ -> False )
  (ensures fun h0 r h1 ->
    let n = HS.sel h0 Nego.(s.nego.state) in
    let t = HSL.transcript h0 s.log in
    let k = HS.sel h1 s.ks.KeySchedule.state in
    ( Correct? r ==>
      ( match n with
        | Nego.C_Offer offer -> (
          ( if offer.CH.version = TLS_1p3
            then
             k = KeySchedule.(C(C_13_wait_SH
              (nonce s)
              [] (*TODO: es for 0RTT*)
              (C_13_wait_SH?.gs (C?.s k)) // TODO
                 // ADL: need an existential for the keyshares (offer only has contains shares)
                 // + check that that the group and CommonDH.pubshare g gx match
              //(Nego.gs_of offer)
             ))
            else k = KeySchedule.(C(C_12_Full_CH offer.CH.random)) /\
          t = [HSL.Msg (HSM.M_client_hello offer)] ))
        | _ -> False )))

let client_ClientHello hs i =
  // The configuration determines which groups to propose (duplicating Nego?)
  // groups = None indicates a 1.2 handshake
  // groups = Some [] is valid, to deliberately trigger HRR.
  let groups =
    match (config_of hs).max_version with
    | TLS_1p3 ->
      trace "offering ClientHello 1.3"; Some (config_of hs).offer_shares
    | _ ->
      trace "offering ClientHello 1.2"; None
    in

  // Secret samples the corresponding key shares, keeping their private exponents.
  // (threading hs.ks ensures these shares are single-use).
  let shares = Secret.ks_client_init hs.ks groups in

  // Nego compute the full client offer
  let offer = Nego.client_ClientHello hs.nego shares in

  // We send it in two steps:
  // 1. the truncated ClientHello;
  // 2. the binders that authenticate its offer.
  HSL.send hs.log (ClientHello offer);
  let earlies = client_Binders hs offer in

  if Some? (Nego.find_early_data offer) then (
    // optional EDI
    assert(earlies <> []);
    let (| i, info, _ |) = head earlies in
    let ha = ha_of_info info in
    let digest_full_ClientHello = HSL.hash_tag #ha hs.log in
    let early_exporter_secret, edk =
      Secret.client13_0RTT (head earlies) digest_full_ClientHello in
    export hs early_exporter_secret;
    register hs edk;
    HSL.send_signals hs.log (Some (true, false)) false );

  let ks0 = (shares, earlies) in
  hs.state := C_wait_ServerHello ks0;
  Correct(HSL.next_fragment hs.log i)

let client_HelloRetryRequest (hs:hs) (hrr:hrr) : St incoming =
  trace "client_HelloRetryRequest";
  let s =
    match Nego.group_of_hrr hrr with
    | None ->
      // this case should only ever happen in QUIC stateless retry address validation
      trace "Server did not specify a group in HRR, re-using the previous choice"; None
    | Some ng ->
        let Some g = CommonDH.group_of_namedGroup ng in
        let s = KeySchedule.ks_client_13_hello_retry hs.ks g in
	Some (| g, s |)
    in
  match Nego.client_HelloRetryRequest hs.nego hrr s with
  | Error z -> InError z
  | Correct(ch) ->
    HSL.send hs.log (HSL.Msg (HSM.M_client_hello ch));
    client_Binders hs ch;
    // Note: we stay in Wait_ServerHello
    // Only the Nego state machine was moved by HRR
    InAck false false

// 17-11-11
// how to avoid duplicating the invariant after reading the flight?
// pass the whole state before calling HSL?
// share [c_WaitServerHello tr] formulas between pre/post and the invariant?
val client_ServerHello:
  s:hs ->
  ks: Secret.c13_wait_serverHello psks groups (*scope?*) ->
  sh:sh ->
  ST incoming
  (requires fun h0 ->
    inv s h0 /\ (
    let control = HyperStack.sel h0 s.state in
    control = C_WaitServerHello /\
    writing h hs.nego
    ))
  (ensures fun h0 r h1 ->
    inv s h1 /\ (
    let control = HyperStack.sel h1 s.state in
    // correct TLS 1.3 ==>
    //   tr = [CH;B;SH]
    //   control = C13_wait_Finished1
    //   HSL has parameters set;
    //   installed handshake keys
    True
    ))
let client_ServerHello (s:hs) ks (sh:sh) (* digest:Hashing.anyTag *): St incoming =
  trace "client_ServerHello";
  match Nego.client_ServerHello s.nego sh with
  | Error z -> InError z
  | Correct mode ->
    let pv = mode.Nego.n_protocol_version in
    let cfg = Nego.local_config s.nego in
    let ha = Nego.hashAlg mode in
    let ka = Nego.kexAlg mode in
    HandshakeLog.setParams s.log pv ha (Some ka) None (*?*);
    match pv with
    | TLS_1p3 ->
      begin
        trace "Running TLS 1.3";
        let digest_ServerHello = HandshakeLog.hash_tag #ha s.log in
        let hsi, ks', cfk, sfk, hs_wr, hs_rd = KeySchedule.client13_ServerHello
          psks groups ks
          mode.Nego.n_server_random
          mode.Nego.n_cipher_suite
          digest_ServerHello
          mode.Nego.n_server_share
          mode.Nego.n_pski in
        register s hs_keys; // register new epoch
        if Nego.zeroRTToffer mode.Nego.n_offer then
         begin
          // Skip the 0-RTT epoch on the reading side
          Epochs.incr_reader s.epochs;
	  match mode.Nego.n_pski with
	  | None ->
	    trace "0-RTT rejected early (no PSK was selected)";
	    Epochs.incr_writer s.epochs
	  | Some _ ->
            trace "0RTT potentially accepted (wait for EE to confirm)";
	    // No EOED in QUIC, so we immediately enable HSK
	    if cfg.is_quic then Epochs.incr_writer s.epochs
         end
	else // No EOED to send in 0-RTT epoch
	  Epochs.incr_writer s.epochs; // Next flight (CFin) will use HSK
        s.state := C_Wait_Finished1;
        Epochs.incr_reader s.epochs; // Client 1.3 HSK switch to handshake key for decrypting EE etc...
        InAck true false // Client 1.3 HSK
      end
    | _ ->
      begin
        trace "Running classic TLS";
        trace ("Offered SID="^(print_bytes mode.Nego.n_offer.CH.session_id)^" Server SID="^(print_bytes mode.Nego.n_sessionID));
        if Nego.resume_12 mode then
         begin // 1.2 resumption
          trace "Server accepted our 1.2 ticket.";
          let Some (tid, Ticket.Ticket12 pv cs ems msId ms) = fst (Nego.resume s.nego) in
          let pv' = mode.Nego.n_protocol_version in
          let cs' = mode.Nego.n_cipher_suite in
          let sr = mode.Nego.n_server_random in
          if pv = pv' && cs = cs' then // TODO check full session
           begin
            let adk = KeySchedule.ks_client_12_resume s.ks sr pv cs ems msId ms in
            let digestSH = HandshakeLog.hash_tag #ha s.log in
            register s adk;
            s.state := C_Wait_CCS1 digestSH;
            InAck false false
           end
          else
            InError (fatalAlert Handshake_failure, "inconsistent protocol version or ciphersuite during resumption")
         end
        else
         begin // 1.2 full handshake
           s.state := C12_wait_ServerHelloDone;
           InAck false false
         end
      end

(* receive Certificate...ServerHelloDone, with optional cert request. Not for TLS 1.3 *)
val client_ServerHelloDone:
  hs ->
  HSM.crt ->
  HSM.ske ->
  option HSM.cr ->
  ST incoming
  (requires (fun h -> True))
  (ensures (fun h0 i h1 -> True))
let client_ServerHelloDone hs c ske ocr =
    trace "processing ...ServerHelloDone";
    match Nego.client_ServerKeyExchange hs.nego c ske ocr with
    | Error z -> InError z
    | Correct mode -> (
      ( match ocr with
        | None -> ()
        | Some cr ->
            trace "processing certificate request (TODO)";
            let cc = {crt_chain = []} in
            HandshakeLog.send hs.log (Certificate cc));

      let gy = Some?.v (mode.Nego.n_server_share) in // already set in KS
      let ks, gx = 
        KeySchedule.client12_full_dh
        mode.Nego.n_offer.HSM.ch_client_random //17-12-02 simplify?
        mode.Nego.n_server_random
        mode.Nego.n_protocol_version
        mode.Nego.n_cipher_suite
        (Nego.emsFlag mode) // a flag controlling the use of ems
        gy in
      let (|g, _|) = gy in
      let msg = ClientKeyExchange ({cke_kex_c = kex_c_of_dh_key #g gx}) in
      let ha = verifyDataHashAlg_of_ciphersuite (mode.Nego.n_cipher_suite) in
      let digestClientKeyExchange = HandshakeLog.send_tag #ha hs.log (HSL.Msg12 msg) in
      let ks, cfin_key, app_keys = KeySchedule.client12_set_session_hash ks digestClientKeyExchange in
      register hs app_keys;
      // we send CCS then Finished;  we will use the new keys only after CCS

      trace ("digest is "^print_bytes digestClientKeyExchange);
      //let cvd = TLSPRF.verifyData (mode.Nego.n_protocol_version,mode.Nego.n_cipher_suite) cfin_key Client digestClientKeyExchange in
      let cvd = TLSPRF.finished12 ha cfin_key Client digestClientKeyExchange in
      let fin = HSM.M12_finished cvd in
      let digestClientFinished = HandshakeLog.send_CCS_tag #ha hs.log (HSL.Msg12 fin) false in
      hs.state := C12_wait_CCS2 ks digestClientFinished;
      InAck false false)

#set-options "--admit_smt_queries true"
(* completes the handshake; called either by client13_ServerFinished
   or after sending EOED *)
private val client13_ClientFinished:
  i: Secret.hs_id ->
  secret: ams (Secret.ams_of_hms i) ->
  cfk: Secret.fink (Secret.cfk_of_hms i) -> //17-12-28 wrong index; we probably need i1 instead of i2.
  digest (* either ...ServerFinished or ...ServerFinished; EOED *) ->
  option HSM.cr13 ->
  St unit
let client13_ClientFinished i secret cfk digest ocr =
  let mode = Nego.getMode hs.nego in
  let ha = verifyDataHashAlg_of_ciphersuite (mode.Nego.n_cipher_suite) in
  let digest_cvd =
    match ocr with
    | Some cr -> HSL.send_tag #ha hs.log (Certificate13 ({crt_request_context = empty_bytes; crt_chain13 = []}))
    | None -> digest in
  let cvd = HMAC_UFCMA.mac cfk digest_cvd in
  if not (Nego.zeroRTT mode) then Epochs.incr_writer hs.epochs; // to HSK, 0-RTT case is treated in EOED logic
  let digest_ClientFinished = HSL.send_tag #ha hs.log (Finished ({fin_vd = cvd})) in
  let i2 = ams_of_hms i in
  let rms = KeySchedule.rms13_ClientFinished i2 ams digest_ClientFinished in // for Post-HS
  Epochs.incr_reader hs.epochs; // to ATK
  HandshakeLog.send_signals hs.log (Some (true, false)) true; //was: Epochs.incr_writer hs.epochs
  hs.state := C13_complete i2 rms // full_mode (cvd,svd); do we still need to keep those?

(* receive EncryptedExtension...ServerFinished for TLS 1.3,
   roughly mirroring client_ServerHelloDone;
   may still fail on Finished, CertificateVerify, or negotiation;
   otherwise complete the handshake. *)
val client13_ServerFinished:
  s: hs ->
  ee: HSM.ee ->
  ocr: option HSM.cr13 ->
  oc_digest: option (HSM.crt13 * Hashing.anyTag) ->
  ocv: option HSM.cv ->
  svd: bytes ->
  digestCertVerify: Hashing.anyTag (* authenticated by Finished *) ->
  digestServerFinished: Hashing.anyTag (* including Finished *) ->
  ST incoming
  (requires fun h0 ->
    let control = HyperStack.sel h0 s.state in
    C13_wait_Finished1? control)
  (ensures fun h0 r h1 -> True)
let client13_ServerFinished hs ee ocr oc_digest ocv (svd:bytes) digestCertVerify digestServerFinished =
  let C13_wait_Finished1 i ams cfk sfk = !hs.state in
  let i2 = Secret.ams_of_hms i in
  let verified_Finished = HMAC_UFCMA.verify sfin_key digestCertVerify svd in
  if (not verified_Finished)
  then InError (fatalAlert Decode_error, "Finished MAC did not verify: expected digest "^print_bytes digestCertVerify )
  else
  let oc, digestCert = // push this to Nego?
    match oc_digest with
    | None -> None
    | Some (c,dc) -> (Some c.crt_chain13), Some dc in
  match Nego.clientComplete_13 hs.nego ee ocr oc ocv digestCert with
  | Error z -> InError z
  | Correct mode ->
      let r, w, x1s = KeySchedule.client13_ServerFinished ks digestServerFinished in
      export hs x1s;
      register hs (r,w); // application data keys are ready to use in both directions
      if Nego.zeroRTT mode then (
        trace "Early data accepted; emitting EOED.";
        let ha = Nego.hashAlg mode in
        let digestEOED = HSL.send_tag #ha hs.log EndOfEarlyData in
        HSL.send_signals hs.log (Some (false, false)) false;
        hs.state := C13_sent_EOED i digestEOED ocr cfin_key;
        // will call client13_ClientFinished next
        InAck false false )
      else (
        trace "Early data rejected";
        //17-12-28 missing parameters for resumption and ticketing.
        client13_ClientFinished i ams cfk digestServerFinished ocr;
        InAck true false // Client 1.3 ATK; next the client will read again to send Finished, writer++, and the Complete signal
      ) // moving to C_Complete

let rec iutf8 (m:bytes) : St (s:string{String.length s < pow2 30 /\ utf8_encode s = m}) =
    match iutf8_opt m with
    | None -> trace ("Not a utf8 encoding of a string"); iutf8 m
    | Some s -> s

// Processing of the server CCS and optional NewSessionTicket
// This is used both in full handshake and resumption
let client12_NewSessionTicket (hs:hs) (resume:bool) (digest:Hashing.anyTag) (ost:option sticket)
  : St incoming =
  trace (
    "Processing server CCS ("
    ^(if resume then "resumption" else "full handshake")^"). "
    ^(match ost with
     | None -> "No ticket sent."
     | Some {sticket_ticket = t} -> "Ticket: "^(print_bytes t)));
  hs.state :=
    (if resume then C12_wait_R_Finished1 digest
    else C12_wait_Finished2 digest);
  Epochs.incr_reader hs.epochs;
  let mode = Nego.getMode hs.nego in
  match ost, Nego.sendticket_12 mode with
  | Some {sticket_ticket = tid}, true ->
    let cfg = Nego.local_config hs.nego in
    let sni = iutf8 (Nego.get_sni mode.Nego.n_offer) in
    let (msId, ms) = KeySchedule.ks_12_ms hs.ks in
    let pv = mode.Nego.n_protocol_version in
    let cs = mode.Nego.n_cipher_suite in
    let tcb = cfg.ticket_callback in
    tcb.new_ticket tcb.ticket_context sni tid (TicketInfo_12 (pv, cs, Nego.emsFlag mode)) ms;
    InAck true false
  | None, false -> InAck true false
  | Some t, false -> InError (fatalAlert Unexpected_message, "unexpected NewSessionTicket message")
  | None, true -> InError (fatalAlert Unexpected_message, "missing expected NewSessionTicket message")

// Process an incoming ticket (1.3)
let client13_NewSessionTicket (hs:hs) (st13:sticket13)
  : St incoming =
  let tid = st13.ticket13_ticket in
  trace ("Received ticket: "^(hex_of_bytes tid));
  let mode = Nego.getMode hs.nego in
  let CipherSuite13 ae h = mode.Nego.n_cipher_suite in
  let t_ext = st13.ticket13_extensions in
  let ed = List.Tot.find Extensions.E_early_data? t_ext in
  let now = UInt32.uint_to_t (FStar.Date.secondsFromDawn()) in
  let pskInfo = PSK.({
    ticket_nonce = Some st13.ticket13_nonce;
    time_created = now;
    ticket_age_add = st13.ticket13_age_add;
    allow_early_data = Some? ed;
    allow_dhe_resumption = true;
    allow_psk_resumption = true;
    early_ae = ae; early_hash = h;
    identities = (empty_bytes, empty_bytes); // TODO certs
  }) in
  let psk = KeySchedule.ks_client_13_rms_psk hs.ks st13.ticket13_nonce in
  let sni = iutf8 (Nego.get_sni mode.Nego.n_offer) in
  let cfg = Nego.local_config hs.nego in
  let valid_ed =
    if cfg.max_early_data = Some 0xfffffffful then
      (match ed with
      | None -> true
      | Some (Extensions.E_early_data (Some x)) -> x = 0xfffffffful
      | _ -> false)
    else true in
  if valid_ed then
    (let tcb = cfg.ticket_callback in
    tcb.new_ticket tcb.ticket_context sni tid (TicketInfo_13 pskInfo) psk;
    InAck false false)
  else InError (fatalAlert Illegal_parameter, "QUIC tickets must allow 0xFFFFFFFF bytes of early data")

let client_ServerFinished hs f digestClientFinished =
  let sfin_key = KeySchedule.ks_12_finished_key hs.ks in
  let mode = Nego.getMode hs.nego in
  let ha = verifyDataHashAlg_of_ciphersuite mode.Nego.n_cipher_suite in
  let expected_svd = TLSPRF.finished12 ha sfin_key Server digestClientFinished in
  //let expected_svd = TLSPRF.verifyData (mode.Nego.n_protocol_version,mode.Nego.n_cipher_suite) sfin_key Server digestClientFinished in
  if f.fin_vd = expected_svd
  then (
    hs.state := C_Complete; // ADL: TODO need a proper renego state Idle (Some (vd,svd)))};
    InAck false true // Client 1.2 ATK
    )
  else
    InError (fatalAlert Decode_error, "Finished MAC did not verify: expected digest "^print_bytes digestClientFinished)

// Server finished in 1.2 resumption
let client_R_ServerFinished hs f digestNewSessionTicket digestServerFinished
  : St incoming =
  trace "client_R_ServerFinished";
  let sfin_key = KeySchedule.ks_12_finished_key hs.ks in
  let mode = Nego.getMode hs.nego in
  let ha = verifyDataHashAlg_of_ciphersuite mode.Nego.n_cipher_suite in
  let expected_svd = TLSPRF.finished12 ha sfin_key Server digestNewSessionTicket in
  if f.fin_vd = expected_svd
  then (
    let cvd = TLSPRF.finished12 ha sfin_key Client digestServerFinished in
    let _ = HandshakeLog.send_CCS_tag #ha hs.log (HSL.Msg12 (HSM.M12_finished cvd)) true in
    hs.state := C_Complete; // ADL: TODO need a proper renego state Idle (Some (vd,svd)))};
    InAck false false // send_CCS_tag buffers the complete
  )
  else
    InError (fatalAlert Decode_error, "Finished MAC did not verify: expected digest "^print_bytes digestNewSessionTicket)

(* -------------------- Handshake Server ------------------------ *)

(* called by server_ClientHello after sending TLS 1.2 ServerHello *)
// static precondition: n.n_protocol_version <> TLS_1p3 && Some? n.n_sigAlg && (n.n_kexAlg = Kex_DHE || n.n_kexAlg = Kex_ECDHE)
// should instead use Nego for most of this processing

val server_ServerHelloDone: hs -> St incoming // why do I need an explicit val?
let server_ServerHelloDone hs =
  trace "Sending ...ServerHelloDone";
  let mode = Nego.getMode hs.nego in
  let Some (chain, sa) = mode.Nego.n_server_cert in // Server cert chosen in Nego.server_ClientHello
  match Nego.chosenGroup mode with
  | None ->
    InError (fatalAlert Handshake_failure, perror __SOURCE_FILE__ __LINE__ "no shared supported group")
  | Some g  ->
    // ad hoc signing of the nonces and server key share
    let kex_s = KEX_S_DHE (Some?.v mode.Nego.n_server_share) in
    let tbs =
      let cr = mode.Nego.n_offer.ch_client_random in
      let sv = kex_s_to_bytes kex_s in
      let csr = cr @| mode.Nego.n_server_random in
      Nego.to_be_signed mode.Nego.n_protocol_version Server (Some csr) sv
    in
    match Nego.sign hs.nego tbs with
    | Error z -> InError z
    | Correct sig ->
      let ske = sv @| Parsers.CertificateVerify13.certificateVerify13_serializer32 sig in
      HandshakeLog.send hs.log (HSL.Msg12 (HSM.M12_certificate (Cert.chain_down chain)));
      HandshakeLog.send hs.log (HSL.Msg12 (HSM.M12_server_key_exchange ske));
      HandshakeLog.send hs.log (HSL.Msg12 (HSM.M12_server_hello_done ()));
      hs.state := S_wait_CCS1;
      InAck false false // Server 1.2 ATK

// the ServerHello message is a simple function of the mode.
let not_encryptedExtension e = not (Extensions.encryptedExtension e)
let serverHello (m:Nego.mode) =
  let open Nego in
  let pv = m.n_protocol_version in
  ServerHello ({
    sh_protocol_version = pv;
    sh_server_random = m.n_server_random;
    sh_sessionID = m.n_sessionID;
    sh_cipher_suite = m.n_cipher_suite;
    sh_compression = NullCompression;
    sh_extensions =
      match pv, m.n_server_extensions with
      | TLS_1p3, Some exts ->
        Some (List.Tot.filter not_encryptedExtension exts)
      | _ -> m.n_server_extensions
   })

val consistent_truncation: option (list Extensions.pskIdentity * nat) -> option Extensions.binders -> bool
let consistent_truncation x y =
  match x, y with
  | None, None -> true
  | None, Some _ -> false
  | Some _, None -> false
  | Some (psks,_), Some binders -> List.length psks = List.length binders

(* receive ClientHello, choose a protocol version and mode *)
val server_ClientHello: hs -> HSM.clientHello -> ST incoming
  (requires (fun h -> True))
  (ensures (fun h0 i h1 -> True))

let server_ClientHello hs offer =
  let open Parsers.OfferedPsks in
  let binders = Nego.find_clientPske offer in

    trace ("Processing ClientHello"
           ^ (match binders with
	     | None -> ""
             | Some opsk -> " with "
	       ^ string_of_int (List.length opsk.binders)
               ^ " binder(s)"));

    if not (consistent_truncation binders)
    then InError (fatalAlert Illegal_parameter, "unexpected number of binders")
    else

    // Negotiation proceeds in two steps, first resumption / server share
    // Note that only the nego state machine records HRR
    // there is currently no S_wait_CH2 state - the logic is all the same
    // except for this call to Nego that ensures the two CH are consistent with
    // the HRR group
    match Nego.server_ClientHello hs.nego offer hs.log with
    | Error z -> InError z
    | Correct (Nego.ServerHelloRetryRequest hrr) ->
      HandshakeLog.send hs.log (HelloRetryRequest hrr);
      // Note: no handshake state machine transition
      InAck false false

    | Correct (Nego.ServerMode mode cert app_exts) ->

    let pv = mode.Nego.n_protocol_version in
    let cr = mode.Nego.n_offer.CH.random in
    let ha = Nego.hashAlg mode in

    if Nego.resume_12 mode
    then
     begin
      trace "accepted TLS 1.2 resumption";
      let ka = Nego.kexAlg mode in
      HandshakeLog.setParams hs.log pv ha (Some ka) None;

      // We only support 1.2 ticket-based resumption for now
      // The following pattern always succeeds
      // TODO don't decrypt twice between Nego and HS
      let Some tid = Nego.find_sessionTicket offer in
      let Some (pv, cs, ems, msId, ms) = Ticket.check_ticket12 tid in
      let adk = KeySchedule.server12_resume hs.ks cr pv cs ems msId ms in
      register hs adk;

      match Nego.server_ServerShare hs.nego None app_exts with
      | Error z -> InError z
      | Correct mode ->
        let digestSessionTicket =
          if Nego.sendticket_12 mode then
            // Save hashing the SH if we don't send a ticket
            let _ = HandshakeLog.send hs.log (HSL.Msg (serverHello mode)) in
            let ticket =
	      let open Parsers.NewSessionTicket12 in
	      {lifetime_hint = 3600ul; ticket = tid; } in
            HandshakeLog.send_tag #ha hs.log (HSL.Msg12 (HSM.M12_new_session_ticket ticket))
          else
            HandshakeLog.send_tag #ha hs.log (HSL.Msg (serverHello mode))
          in
        let digestServerFinished =
          let fink = KeySchedule.ks_12_finished_key hs.ks in
          let svd = TLSPRF.finished12 ha fink Server digestSessionTicket in
          HandshakeLog.send_CCS_tag #ha hs.log (HSL.Msg12 (HSM.M12_finished svd)) true in
        hs.state := S_wait_CCS2 digestServerFinished;
        InAck false false
     end // 1.2 resumption
    else (
      let cs = mode.Nego.n_cipher_suite in
      let g_gx = mode.Nego.n_client_share in
      let key_share_result =
        if pv = TLS_1p3  then
        match mode.Nego.n_pski with
        | None ->
            let server_share, None = KeySchedule.server13_init cr sr cs None g_gx (HSL.transcript h1 hs.log) in
            Correct server_share
        | Some i -> (
            trace ("accepted TLS 1.3 psk #"^string_of_int i);
            // we should statically know that the offer list is big enough, hence the binder list too.
            let Some (psks,tlen) = opsk in
            let Some (id, _) = List.Tot.nth psks i in
            let Some tag = List.Tot.nth (Some?.v obinders) i in
            assume(PSK.registered_psk id);
            let server_share, Some binderKey = KeySchedule.server13_init cr cs (Some id) g_gx (HSL.transcript h1 hs.log) in
            if verify_binder hs binderKey tag tlen
            then Correct server_share
            else
              //( trace ("WARNING: binder verification failed, tlen="^string_of_int tlen); Correct server_share))
              fatal Bad_record_mac "binder verification failed")
        else
        match Nego.kexAlg mode with
          | Kex_DHE | Kex_ECDHE ->
            let Some g = Nego.chosenGroup mode in
            let ks, gy = KeySchedule.server12_init_dh cr sr pv cs (Nego.emsFlag mode) g in
            Correct (Some (CommonDH.Share g gy))
          | _ -> fatal Handshake_failure "Unsupported RSA key exchange" in
      match key_share_result with
      | Error z -> InError z
      | Correct optional_server_share ->
      match Nego.server_ServerShare hs.nego optional_server_share app_exts with
      | Error z -> InError z
      | Correct mode ->
        let ka = Nego.kexAlg mode in
        HandshakeLog.setParams hs.log pv ha (Some ka) None;
        let ha = verifyDataHashAlg_of_ciphersuite mode.Nego.n_cipher_suite in
        // these hashes are not always used
        let digestClientHelloBinders = HandshakeLog.hash_tag #ha hs.log in
        let digestServerHello = HandshakeLog.send_tag #ha hs.log (HSL.Msg (serverHello mode)) in
        if pv = TLS_1p3
        then
          begin
            let zeroing = Nego.zeroRTT mode in
            if zeroing  then (
              let early_exporter_secret, zero_keys =
                KeySchedule.server13_0rtt_key hs.ks digestClientHelloBinders in
              export hs early_exporter_secret;
              register hs zero_keys
            );
            // TODO handle 0RTT accepted and 0RTT refused
            // - get 0RTT key from KS.
            // - do the signalling
            HandshakeLog.send_signals hs.log (Some (false, zeroing)) false; // signal key change after writing ServerHello
            trace "derive handshake keys";
            let hs_keys = KeySchedule.server13_ServerHello hs.ks digestServerHello (* digestServerHello *)  in
            register hs hs_keys;
            // We will start using the HTKs later (after sending SH, and after receiving 0RTT traffic)
            hs.state := S13_sent_ServerHello;
            InAck zeroing false
          end
        else
          server_ServerHelloDone hs // sending our whole flight hopefully in a single packet.
    )

inline_for_extraction type cke_t = Parsers.Handshake12_m12_client_key_exchange.handshake12_m12_client_key_exchange

(* receive ClientKeyExchange; CCS *)
let server_ClientCCS1 hs (cke:cke_t) (* clientCert *) digestCCS1 =
    // FIXME support optional client c and cv
    // let ems = n.n_extensions.ne_extended_ms in // ask Nego?
    trace "process Client CCS";
    match cke.cke_kex_c with
      | KEX_C_RSA _ | KEX_C_DH -> InError(fatalAlert Decode_error, perror __SOURCE_FILE__ __LINE__ "Expected DHE/ECDHE CKE")
      | KEX_C_DHE gyb
      | KEX_C_ECDHE gyb ->
        begin
          let mode = Nego.getMode hs.nego in  //TODO read back from mode.
          // ADL: the type of gyb will change from bytes to g & share g; for now we parse here.
          let Some (|g,  _|) = mode.Nego.n_server_share in
          match CommonDH.parse g gyb with
          | None -> InError(fatalAlert Decode_error, perror __SOURCE_FILE__ __LINE__ "Cannot parse client share in CKE")
          | Some gy ->
            let app_keys = Secret.server12_cke_dh hs.ks (| g, gy |) digestCCS1 in
            register hs app_keys;
            Epochs.incr_reader hs.epochs;
            // use the new reader; will use the new writer only after sending CCS
            hs.state := S_wait_Finished1 digestCCS1; // keep digest to verify the Client Finished
            InAck true false  // Server 1.2 ATK
        end

// Resumption client finished
let server_ClientFinished2 hs cvd digestSF digestCF =
  trace "Process Client Finished";
  let fink = KeySchedule.ks_12_finished_key hs.ks in
  let mode = Nego.getMode hs.nego in
  let pv = mode.Nego.n_protocol_version in
  let cs = mode.Nego.n_cipher_suite in
  let ha = verifyDataHashAlg_of_ciphersuite (mode.Nego.n_cipher_suite) in
  let expected_cvd = TLSPRF.finished12 ha fink Client digestSF in
  if cvd = expected_cvd then
    (hs.state := S_Complete; InAck false false)
  else
    InError (fatalAlert Decode_error, "Client Finished MAC did not verify: expected digest "^print_bytes digestSF)

(* receive ClientFinish *)
val server_ClientFinished:
  hs -> bytes -> Hashing.anyTag -> Hashing.anyTag -> St incoming
let server_ClientFinished hs cvd digestCCS digestClientFinished =
    trace "Process Client Finished";
    let fink = KeySchedule.ks_12_finished_key hs.ks in
    let mode = Nego.getMode hs.nego in
    let cfg = Nego.local_config hs.nego in
    let pv = mode.Nego.n_protocol_version in
    let cs = mode.Nego.n_cipher_suite in
    let alpha = (mode.Nego.n_protocol_version, mode.Nego.n_cipher_suite) in
    let ha = verifyDataHashAlg_of_ciphersuite (mode.Nego.n_cipher_suite) in
    let expected_cvd = TLSPRF.finished12 ha fink Client digestCCS in
    //let expected_cvd = TLSPRF.verifyData alpha fink Client digestCCS in
    if cvd = expected_cvd
    then
      //let svd = TLSPRF.verifyData alpha fink Server digestClientFinished in
      let digestTicket =
        if Nego.sendticket_12 mode then
          let (msId, ms) = KeySchedule.ks_12_ms hs.ks in
          let ticket = Ticket.Ticket12 pv cs (Nego.emsFlag mode) msId ms in
          let ticket = Parsers.NewSessionTicket12.({
            lifetime_hint = 3600ul;
            ticket = Ticket.create_ticket false ticket;
          }) in
          HandshakeLog.send_tag #ha hs.log (HSL.Msg12 (HSM.M12_new_session_ticket ticket))
        else digestClientFinished in
      let svd = TLSPRF.finished12 ha fink Server digestTicket in
      let unused_digest = HandshakeLog.send_CCS_tag #ha hs.log (HSL.Msg12 (HSM.M12_finished svd)) true in
      hs.state := S_Complete;
      InAck false false // Server 1.2 ATK; will switch write key and signal completion after sending
    else
      InError (fatalAlert Decode_error, "Finished MAC did not verify: expected digest "^print_bytes digestClientFinished)

(* send EncryptedExtensions; Certificate13; CertificateVerify; Finish (1.3) *)
val server_ServerFinished_13: hs -> i:id -> ST (result (outgoing i))
  (requires (fun h -> True))
  (ensures (fun h0 i h1 -> True))
let server_ServerFinished_13 hs i =
    // static pre: n.n_protocol_version = TLS_1p3 && Some? n.n_sigAlg && (n.n_kexAlg = Kex_DHE || n.n_kexAlg = Kex_ECDHE)
    // most of this should go to Nego
    trace "prepare Server Finished";
    let mode = Nego.getMode hs.nego in
    let kex = Nego.kexAlg mode in
    let pv = mode.Nego.n_protocol_version in
    let cs = mode.Nego.n_cipher_suite in
    let exts = Some?.v mode.Nego.n_server_extensions in
    let sh_alg = sessionHashAlg pv cs in
    let halg = verifyDataHashAlg_of_ciphersuite cs in // Same as sh_alg but different type FIXME

    let eexts = List.Tot.filter Extensions.encryptedExtension exts in

    let digestFinished =
      match kex with
      | Kex_ECDHE -> // [Certificate; CertificateVerify]
        HandshakeLog.send hs.log (HSL.Msg13 (HSM.M13_encrypted_extensions eexts));
        let Some (chain, sa) = mode.Nego.n_server_cert in
	let c = Parsers.Certificate13.({
	  certificate_request_context = empty_bytes;
	  certificate_list = chain}) in
        let digestSig = HandshakeLog.send_tag #halg hs.log (HSL.Msg13 (HSM.M13_certificate c)) in
        let tbs = Nego.to_be_signed pv Server None digestSig in
        (match Nego.sign hs.nego tbs with
        | Error z -> Error z
        | Correct signature -> Correct (HandshakeLog.send_tag #halg hs.log (HSL.Msg13 (HSM.M13_certificate_verify signature))))
      | _ -> // PSK
        Correct (HandshakeLog.send_tag #halg hs.log (HSL.Msg13 (HSM.M13_encrypted_extensions eexts)))
      in

    match digestFinished with
    | Correct digestFinished ->
      let (| sfinId, sfin_key |) = KeySchedule.ks_server_13_server_finished hs.ks in
      let svd = HMAC_UFCMA.mac sfin_key digestFinished in
      let digestServerFinished = HandshakeLog.send_tag #halg hs.log (HSL.Msg13 (HSM.M13_finished svd)) in
      // we need to call KeyScheduke twice, to pass this digest
      let app_keys, exporter_master_secret = KeySchedule.ks_server_13_sf hs.ks digestServerFinished in
      export hs exporter_master_secret;
      register hs app_keys;
      HandshakeLog.send_signals hs.log (Some (true,false)) false;
      Epochs.incr_reader hs.epochs; // TODO when to increment the reader?

      hs.state :=
        (if Nego.zeroRTT mode then S_wait_EOED
         else S_wait_Finished2 digestServerFinished);
      Correct(HSL.next_fragment hs.log i)
    | Error z -> Error z

let server_EOED hs (digestEOED: Hashing.anyTag)
  : St incoming
  =
  trace "Process EOED (increment reader to HS key)";
  Epochs.incr_reader hs.epochs;
  hs.state := S_wait_Finished2 digestEOED;
  InAck false false

(* receive ClientFinish 1.3 *)
val server_ClientFinished_13: hs ->
  cvd:bytes ->
  Hashing.anyTag -> // Digest either up to ServerFinished or up to CertificateVerify with client certg
  Hashing.anyTag -> // Digest up to ClientFinished
  option (HSM.crt13 * HSM.cv * Hashing.anyTag) -> St incoming
let server_ClientFinished_13 hs f digestBeforeClientFinished digestClientFinished clientAuth =
   trace "Process Client Finished";
   match clientAuth with
   | Some  (c,cv,digest) ->
      InError(fatalAlert Internal_error,
        perror __SOURCE_FILE__ __LINE__ "Client CertificateVerify validation not implemented")
   | None ->
       let (| i, cfin_key |) = KeySchedule.ks_server_13_client_finished hs.ks in
       let mode = Nego.getMode hs.nego in
       if HMAC_UFCMA.verify cfin_key digestBeforeClientFinished f
       then
        begin
         (* NewSessionTicket is sent if client advertised a PSK_KEX mode *)
         (match Nego.find_psk_key_exchange_modes mode.Nego.n_offer with
         | [] -> trace ("Not sending a ticket: no PSK key exchange mode advertised")
         | psk_kex ->
           let (| li, rmsid, rms |) = KeySchedule.ks_server_13_cf hs.ks digestClientFinished in
           let cfg = Nego.local_config hs.nego in
           let cs = mode.Nego.n_cipher_suite in
           let age_add = Random.sample32 4ul in
           let age_add = uint32_of_bytes age_add in
           let now = UInt32.uint_to_t (FStar.Date.secondsFromDawn()) in
           let ticket = Ticket.Ticket13 cs li rmsid rms empty_bytes now age_add empty_bytes in
           let tb = Ticket.create_ticket false ticket in

           trace ("Sending ticket: "^(print_bytes tb));
           let ticket_ext =
             match cfg.max_early_data with
             | Some max_ed -> [Extensions.E_early_data (Some max_ed)]
             | None -> [] in
           let tnonce, _ = split_ tb 12 in
           HandshakeLog.send hs.log (NewSessionTicket13 ({
             ticket13_lifetime = FStar.UInt32.(uint_to_t 3600);
             ticket13_age_add = age_add;
             ticket13_nonce = tnonce;
             ticket13_ticket = tb;
             ticket13_extensions = ticket_ext;
           })));

          hs.state := S_Complete;
          Epochs.incr_reader hs.epochs; // finally start reading with AKTs
          InAck true true  // Server 1.3 ATK
        end
       else InError (fatalAlert Decode_error, "Finished MAC did not verify: expected digest "^print_bytes digestClientFinished)

(* TODO: resumption *)
assume val server_send_server_finished_res: hs -> ST unit
  (requires (fun h -> True))
  (ensures (fun h0 i h1 -> True))

(* Handshake API: PUBLIC Functions, taken from FSTI *)

// returns the protocol version negotiated so far
// (used for formatting outgoing packets, but not trusted)
(*
val version: s:hs -> Tot protocolVersion
  (requires (hs_inv s))
  (ensures (fun h0 pv h1 -> h0 = h1))
  *)

(* ----------------------- Control Interface -------------------------*)

let create (parent:rid) cfg role =
  let r = new_region parent in
  let log = HandshakeLog.create r None (* cfg.max_version (Nego.hashAlg nego) *) in
  //let nonce = Nonce.mkHelloRandom r r0 in //NS: should this really be Client?
  let ks, nonce = KeySchedule.create #r role in
  let nego = Nego.create r role cfg nonce in
  let epochs = Epochs.create r nonce in
  let state = ralloc r (if role = Client then C_Idle else S_Idle) in
  let x: hs = HS role nego log ks epochs state in //17-04-17 why needed?
  x

let rehandshake s c = FStar.Error.unexpected "rehandshake: not yet implemented"

let rekey s c = FStar.Error.unexpected "rekey: not yet implemented"

let request s c = FStar.Error.unexpected "request: not yet implemented"

let invalidateSession hs = ()
// ADL: disabling this for top-level API testing purposes
// FStar.Error.unexpected "invalidateSession: not yet implemented"


(* ------------------ Outgoing -----------------------*)

let next_fragment (hs:hs) i =
    trace "next_fragment";
    let outgoing = HSL.next_fragment hs.log i in
    match outgoing, !hs.state with
    // When the output buffer is empty, we send extra messages in 3 cases
    // * we prepare the initial ClientHello; or
    // * we continue with encrypted traffic after sending ServerHello in plaintext; or
    // * we continue with hs-encrypted traffic after sending EOED.
    // Otherwise, we just returns buffered messages and signals
    | Outgoing None None false, C_Idle -> client_ClientHello hs i
    | Outgoing None None false, S13_sent_ServerHello -> server_ServerFinished_13 hs i
    | Outgoing None None false, C13_sent_EOED d ocr cfk ->
        client13_ClientFinished hs d ocr cfk;
        Correct(HSL.next_fragment hs.log i)

    //| Outgoing msg  true _ _, _ -> (Epochs.incr_writer hs.epochs; Correct outgoing) // delayed
    | _ -> Correct outgoing // nothing to do

(* ----------------------- Incoming ----------------------- *)

let rec recv_fragment (hs:hs) #i rg f =
    let recv_again r =
      match r with
      // only case where the next incoming flight may already have been buffered.
      | InAck false false -> recv_fragment hs #i (0,0) empty_bytes 
      | r -> r  in
    trace "recv_fragment";
    let h0 = get() in
    let flight = HSL.receive hs.log f in
    match flight with
    | Error z -> InError z
    | Correct None -> InAck false false // nothing happened
    | Correct (Some (ms,ts)) ->
      match !hs.state, ms, ts with
      | C_Idle, _, _ -> InError (fatalAlert Unexpected_message, "Client hasn't sent hello yet")

      | C_wait_ServerHello, [HelloRetryRequest hrr], [] ->
        client_HelloRetryRequest hs hrr

      | C_wait_ServerHello, [ServerHello sh], [] ->
        let r = client_ServerHello hs sh in
        recv_again r

    //| C_wait_ServerHello, Some ([ServerHello sh], [digest]) -> client_ServerHello hs sh digest
      | C12_wait_ServerHelloDone, [Certificate c; ServerKeyExchange ske; ServerHelloDone], [] ->
        client_ServerHelloDone hs c ske None

      | C12_wait_ServerHelloDone, [Certificate c; ServerKeyExchange ske; CertificateRequest cr; ServerHelloDone], [] ->
        client_ServerHelloDone hs c ske (Some cr)

      | C13_wait_Finished1 _ _ _ _,
        [EncryptedExtensions ee; Certificate13 c; CertificateVerify cv; Finished f],
        [_; digestCert; digestCertVerify; digestServerFinished] ->
        client13_ServerFinished hs ee None (Some (c, digestCert)) (Some cv) f.fin_vd
                                digestCertVerify digestServerFinished
      | C13_wait_Finished1 _ _ _ _,
        [EncryptedExtensions ee; CertificateRequest13 cr; Certificate13 c; CertificateVerify cv; Finished f],
        [_; digestCert; digestCertVerify; digestServerFinished] ->
        client13_ServerFinished hs ee (Some cr) (Some (c, digestCert)) (Some cv) f.fin_vd
                                digestCertVerify digestServerFinished
      | C13_wait_Finished1 _ _ _ _,
        [EncryptedExtensions ee; Finished f],
        [digestEE; digestServerFinished] ->
        client13_ServerFinished hs ee None None None f.fin_vd
                                digestEE digestServerFinished

      | C12_wait_R_Finished1 digestNewSessionTicket, [Finished f], [digestServerFinished] ->
        client_R_ServerFinished hs f digestNewSessionTicket digestServerFinished

      | C12_wait_Finished2 _ _, [Finished f], [digestServerFinished] ->
        client_ServerFinished hs f

      | S_Idle, [ClientHello ch], []  -> server_ClientHello hs ch None
      | S_Idle, [ClientHello ch; Binders binders], []  -> server_ClientHello hs ch (Some binders)

      | S_wait_Finished1 digest, [Finished f], [digestClientFinish] ->
        server_ClientFinished hs f.fin_vd digest digestClientFinish
      | S_Wait_Finished1 digest, [Finished f], tags ->
        trace (TLSConstants.fold_string print_bytes "BAD TAGS: " " " tags);
        server_ClientFinished hs f.fin_vd digest digest

      | S_wait_CF2 digest, [Finished f], [digestClientFinished] -> // classic resumption
        server_ClientFinished2 hs f.fin_vd digest digestClientFinished

      | S_wait_Finished2 (digestServerFinished),
        [Finished f], [digestClientFinished] ->
        server_ClientFinished_13 hs f.fin_vd digestServerFinished digestClientFinished None

      | S_wait_Finished2 (digestServerFinished),
        [Certificate13 c; CertificateVerify cv; Finished f], [digestSigned; digestCertVerify; digestClientFinished] ->
        server_ClientFinished_13 hs f.fin_vd digestCertVerify digestClientFinished (Some (c, cv, digestSigned))

      | S_wait_EOED,
        [EndOfEarlyData], [digestEOED] ->
        server_EOED hs digestEOED

      | C_Complete, [NewSessionTicket13 st13], [] ->
        client_NewSessionTicket_13 hs st13

      // are we missing the case with a Certificate but no CertificateVerify?
      | _,  _, _ ->
        trace "DISCARD FLIGHT"; InAck false false
        //InError(AD_unexpected_message, "unexpected flight")



// TODO check CCS once committed to TLS 1.3 yields an alert
let recv_ccs (hs:hs) =
    trace "recv_ccs";
    // Draft 22 CCS during HRR
    // Because of stateless HRR, this may also happen as the very first message before CH (!!!)
    let is_hrr = Nego.is_hrr hs.nego in
    let is_idle = S_Idle? !hs.state in
    if is_hrr || is_idle then
     begin
      trace "IGNORING CCS (workaround for implementations that send CCS after HRR)";
      InAck false false
     end
    else
      // CCS triggers completion of the incoming flight of messages.
      let mode = Nego.getMode hs.nego in
      match HSL.receive_CCS #(Nego.hashAlg mode) hs.log with
      | Error z -> InError z
      | Correct (ms, digests, digestCCS) ->
        match !hs.state, ms, digests with
        // client resumption
        | C_Wait_CCS1 _, [NewSessionTicket st], [digestNewSessionTicket] ->
          client_NewSessionTicket_12 hs true digestNewSessionTicket (Some st)
        | C_Wait_CCS1 digestServerHello, [], [] ->
          client_NewSessionTicket_12 hs true digestServerHello None
        // client full handshake
        | C_Wait_CCS2 digest, [], [] ->
          client_NewSessionTicket_12 hs false digest None
        | C_Wait_CCS2 _, [NewSessionTicket st], [digestNewSessionTicket] ->
          client_NewSessionTicket_12 hs false digestNewSessionTicket (Some st)

        | S_Wait_CCS2 digestServerFinished, [], [] -> (
          Epochs.incr_reader hs.epochs;
          hs.state := S_Wait_CF2 digestServerFinished;
          InAck true false)

        | S_Wait_CCS1, [ClientKeyExchange cke], [digest_to_finish] ->
          // assert (Some? pv && pv <> Some TLS_1p3 && (kex = Some Kex_DHE || kex = Some Kex_ECDHE))
          // getting two copies of the same digest?
          server_ClientCCS1 hs cke digestCCS

        | _, _, _ ->
          trace "WARNING: bad CCS";
          InError(fatalAlert Unexpected_message, "CCS received at wrong time")


let authorize s ch = FStar.Error.unexpected "authorize: not yet implemented"
