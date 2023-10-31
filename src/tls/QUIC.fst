module QUIC

/// QUIC-specific interface on top of our main TLS API
/// * establishes session & exported keys: no application-data traffic!
/// * simplified configuration, with reasonable defaults
/// * TCP-like send/recv callbacks operate on caller-provided buffers
///   recv may yield (not enough input)
///   send is guaranteed to succeed (large enough output buffer expected)
///
/// See https://tools.ietf.org/html/draft-ietf-quic-tls-04
///
/// Relying on FFI for accessing configs, callbacks, etc.
/// Testing both in OCaml (TCP-based, TestQUIC ~ TestFFI) and in C.

open FStar.Bytes
open FStar.Error
open FStar.HyperStack.All

open TLSConstants
open TLSInfo
open DataStream
open TLS
open FFICallbacks

module HS = FStar.HyperStack
module FFI = FFI
module Range = Range
open Range
module Parse = Parse

#set-options "--admit_smt_queries true"

(* A flag for runtime debugging of ffi data.
   The F* normalizer will erase debug prints at extraction
   when this flag is set to false. *)
val discard: bool -> ST unit
  (requires (fun _ -> True))
  (ensures (fun h0 _ h1 -> h0 == h1))
let discard _ = ()
let print s = discard (IO.debug_print_string ("QIC| "^s^"\n"))
unfold val trace: s:string -> ST unit
  (requires (fun _ -> True))
  (ensures (fun h0 _ h1 -> h0 == h1))
unfold let trace = if DebugFlags.debug_QUIC then print else (fun _ -> ())


// an integer carrying the fatal alert descriptor
// we could also write txt into the application error log
type error = UInt16.t
private let errno description txt: ST error
  (requires fun h0 -> True)
  (ensures fun h0 _ h1 -> h0 == h1)
=
  let open TLSError in 
  trace ("returning error"^
    (match description with
    | Some ad -> " "^string_of_alert ad
    | None    -> "")^": "^txt);
  let a = match description with | Some a -> a | None -> fatalAlert Internal_error in
  Parse.uint16_of_bytes (Alert.alertBytes a)

module Handshake = Old.Handshake

let quic_check config =
  if config.min_version <> TLS_1p3 then trace "WARNING: not TLS 1.3";
  if not config.non_blocking_read then trace "WARNING: reads are blocking";
  if None? config.alpn            then trace "WARNING: missing ALPN";
  if not config.is_quic           then trace "WARNING: missing QUIC config, using TLS key labels"

let ffiConfig (host:bytes) =
  let h = if length host = 0 then None else Some host in
  { defaultConfig with
    min_version = TLS_1p3;
    max_version = TLS_1p3;
    is_quic = true;
    peer_name = h;
    non_blocking_read = true;
    send_ticket = None;
  }

type chSummary = {
  ch_sni: bytes;
  ch_alpn: bytes;
  ch_extensions: bytes;
  ch_cookie: option bytes;
  ch_ticket_data: option bytes;
}

let rec find_ticket_content (l:list Extensions.pskIdentity)
  : St (option bytes) =
  match l with
  | [] -> None
  | (id,_)::t ->
    match Ticket.check_ticket false id with
    | Some (Ticket.Ticket13 _ _ _ _ _ _ _ app_data) -> Some app_data
    | _ -> find_ticket_content t

let peekClientHello (ch:bytes) (has_record:bool) : ML (option chSummary) =
  if length ch < 40 then (trace "peekClientHello: too short"; None) else
  let ch =
    if has_record then
      let hdr, ch = split ch 5ul in
      match Record.parseHeader hdr with
      | Error (_, msg) -> trace ("peekClientHello: bad record header"); None
      | Correct(ct, pv, len) ->
        if ct <> Content.Handshake || len <> length ch then
          (trace "peekClientHello: bad CT or length"; None)
        else Some ch
    else Some ch
    in
  match ch with
  | None -> None
  | Some ch ->
    match HandshakeMessages.parseMessage ch with
    | Error _
    | Correct None -> trace ("peekClientHello: bad handshake header"); None
    | Correct (Some (| _, hst, ch, _ |)) ->
      if hst <> HandshakeMessages.HT_client_hello then
         (trace "peekClientHello: not a client hello"; None)
      else
        match HandshakeMessages.parseClientHello ch with
        | Error (_, msg) -> trace ("peekClientHello: bad client hello: "^msg); None
        | Correct (ch, _) ->
          let sni = Negotiation.get_sni ch in
          let alpn = Extensions.alpnBytes (Negotiation.get_alpn ch) in
          let ext = HandshakeMessages.optionExtensionsBytes ch.HandshakeMessages.ch_extensions in
	  let ticket_data =
	    match Negotiation.find_clientPske ch with
	    | None -> None
	    | Some (psk,_) -> find_ticket_content psk in
          let cookie =
            match Negotiation.find_cookie ch with
            | None -> None
            | Some c ->
              match Ticket.check_cookie c with
              | None -> None
              | Some (hrr, digest, extra) -> Some extra
            in
          Some ({ch_sni = sni; ch_alpn = alpn; ch_extensions = ext; ch_cookie = cookie; ch_ticket_data = ticket_data })

module H = Old.Handshake
module HSL = HandshakeLog
module KS = Old.KeySchedule

let create_hs (is_server:bool) config : ML H.hs =
  quic_check config;
  let r = new_region HS.root in
  let role = if is_server then Server else Client in
  H.create r config role

type hs_in = {
  input: bytes;
  max_output: UInt32.t;
}

type hs_out = {
  consumed: UInt32.t;
  output: bytes;
  to_be_written: UInt32.t;
  is_complete: bool;
  is_writable: bool;
  is_early_rejected: bool;
  is_post_handshake: bool;
}

type hs_result =
  | HS_SUCCESS of hs_out
  | HS_ERROR of UInt16.t

private let currentId (hs:H.hs) (rw:rw) : St TLSInfo.id =
  let j = H.i hs rw in
  if j<0 then PlaintextID (H.nonce hs)
  else
    let e = Old.Epochs.get_current_epoch (H.epochs_of hs) rw in
    Old.Epochs.epoch_id e

let get_epochs (hs:H.hs) : ML (int * int) =
  H.i hs Reader, H.i hs Writer

private let handle_signals (hs:H.hs) (sig:option HSL.next_keys_use) : ML (bool * bool) =
  match sig with
  | None -> false, false
  | Some use ->
    Old.Epochs.incr_writer (H.epochs_of hs);
    if use.HSL.out_skip_0RTT then
     begin
      trace "Skip 0-RTT (incr writer)";
      Old.Epochs.incr_writer (H.epochs_of hs)
     end;
    (use.HSL.out_appdata, use.HSL.out_0RTT_reject)

private inline_for_extraction let api_error (ad, err) =
  trace ("Returning HS error: "^err);
  HS_ERROR (Parse.uint16_of_bytes (Alert.alertBytes ad))

let process_hs (hs:H.hs) (ctx:hs_in) : ML hs_result =
  let tbw = H.to_be_written hs in
  if tbw > 0 then
   begin
    if ctx.max_output = 0ul then
      HS_SUCCESS ({
        consumed = 0ul;
        output = empty_bytes;
        to_be_written = UInt32.uint_to_t tbw;
        is_complete = false;
        is_writable = false;
	is_early_rejected = false;
	is_post_handshake = false;
      })
    else
      let i = currentId hs Writer in
      match H.next_fragment_bounded hs i (UInt32.v ctx.max_output) with
      | Error z -> api_error z
      | Correct (HSL.Outgoing (Some frag) sig complete) ->
        let is_writable, reject_0rtt = handle_signals hs sig in
        HS_SUCCESS ({
	  consumed = 0ul;
	  output = dsnd frag;
	  to_be_written = UInt32.uint_to_t (H.to_be_written hs);
	  is_complete = complete;
	  is_writable = is_writable;
	  is_early_rejected = reject_0rtt;
	  is_post_handshake = false;
	})
   end
  else
    let i = currentId hs Reader in
    let len = length ctx.input in
    let rg : Range.frange i = (len, len) in
    let f : Range.rbytes rg = ctx.input in
    match H.recv_fragment hs rg f with
    | H.InQuery _ _ -> trace "Unexpected handshake query"; HS_ERROR 252us
    | H.InError z -> api_error z
    | H.InAck nk complete ->
      let consumed = UInt32.uint_to_t len in
      let j = H.i hs Writer in
      let post_hs = H.is_post_handshake hs in
      let i = currentId hs Writer in
      let max_o = UInt32.v ctx.max_output in
      match H.next_fragment_bounded hs i max_o with
      | Error z -> api_error z
      | Correct (HSL.Outgoing frag sig complete' ) ->
        let is_writable, reject_0rtt = handle_signals hs sig in
        HS_SUCCESS ({
          consumed = consumed;
          output = (match frag with Some f -> dsnd f | None -> empty_bytes);
          to_be_written = UInt32.uint_to_t (H.to_be_written hs);
          is_complete = complete || complete';
	  is_writable = is_writable;
	  is_early_rejected = reject_0rtt;
	  is_post_handshake = post_hs;
        })

type raw_key = {
  alg: aeadAlg;
  aead_key: bytes;
  aead_iv: bytes;
  pn_key: bytes;
}

let get_secrets (hs:Old.Handshake.hs) : ML (option KS.raw_rekey_secrets) =
  H.rekey_secrets hs

let get_key (hs:Old.Handshake.hs) (ectr:nat) (rw:bool) : ML (option raw_key) =
  let epochs = Monotonic.Seq.i_read (Old.Epochs.get_epochs (Handshake.epochs_of hs)) in
  if Seq.length epochs <= ectr then None
  else
    let e = Seq.index epochs ectr in
    let AEAD alg _ = aeAlg_of_id (Old.Epochs.epoch_id e) in
    let (key, iv), pn =
      let (rpn, wpn) = Old.Epochs.pn_epoch e in
      if rw then
        let StAE.Stream _ st = Old.Epochs.reader_epoch e in
        let st = StreamAE.State?.aead st in
        AEADProvider.leak st, Some?.v rpn
      else
        let StAE.Stream _ st = Old.Epochs.writer_epoch e in
        let st = StreamAE.State?.aead st in
        AEADProvider.leak st, Some?.v wpn
    in
    Some ({
      alg = alg;
      aead_key = key;
      aead_iv = iv;
      pn_key = pn;
    })
    
let send_ticket (hs:Old.Handshake.hs) (b:bytes) : ML bool =
  Old.Handshake.send_ticket hs b
