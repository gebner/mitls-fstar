(*
  Copyright 2015--2019 INRIA and Microsoft Corporation

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

  Authors: C.Fournet, T. Ramananandro, A. Rastogi, N. Swamy
*)
module TLS.Handshake.ParseFlights

(*
 * This module provides functions to parse Handshake flights
 *)

open FStar.Integers
open FStar.HyperStack.ST

module G = FStar.Ghost
module List = FStar.List.Tot

module HS = FStar.HyperStack
module B = LowStar.Buffer

module LP = LowParse.Low.Base

open HSL.Common

module HSM = HandshakeMessages

module R = LowParse.Repr
module C = LowStar.ConstBuffer

module HSM13R = MITLS.Repr.Handshake13
module HSM12R = MITLS.Repr.Handshake12
module HSMR   = MITLS.Repr.Handshake

#reset-options "--max_fuel 0 --max_ifuel 0 --using_facts_from '* -FStar.Tactics -FStar.Reflection'"


/// The interface is designed to support incremental parsing of flights
///   i.e. suppose it gets a call to parse a flight consisting of three messages [ m1; m2; m3 ]
///   it could happen that the input buffer has data only for m1, while rest of the messages are not yet there
///   in that case, the client appends more data to the buffer (say after reading from the network), and calls
///   this module to parse [ m1; m2; m3 ] again. The interface is designed so that in this second call, we only
///   need to parse m2 and m3, using m1 from the first call.
///
/// Towards this incremental parsing support, this module maintains two ghost state elements:
///   in_progress_flight and parsed_bytes
///
///   In the second call, the caller has to call the same receive function (i.e. in_progress_flight is same)
///   and that they did not modify the prefix of the buffer (i.e. parsed_bytes are same)
///
///   The caller is allowed to call the second receive with a different buffer as long as the contents of the
///   prefix are same
///
/// The module is written in a state-passing style, each receive function returns a new state
///
/// Also see TLS.Handshake.Receive, a wrapper over this module that provides a simpler interface for TLS.Handshake.Machine


/// Supported flight types
///
/// The names should be in-sync with state names of TLS.Handshake.Machine

type in_progress_flt_t =
  | F_none
  | F_s_Idle  //server waiting for CH
  | F_c_wait_ServerHello
  | F_c13_wait_Finished1
  | F_s13_wait_Finished2
  | F_s13_wait_EOED
  // FIXME(adl) missing F_s13_postHS / complete
  | F_c13_Complete
  | F_c12_wait_ServerHelloDone
  | F_cs12_wait_Finished
  | F_c12_wait_NST
  | F_s12_wait_CCS1


/// Abstract state

val state : Type0

/// Parsed bytes that we have seen so far

val parsed_bytes (st:state) : GTot bytes

let length_parsed_bytes (st:state) : GTot nat = Seq.length (parsed_bytes st)


/// Current flight in progress

val in_progress_flt (st:state) : GTot in_progress_flt_t


/// Postcondition of create
///
/// A fresh instance of state has empty parsed bytes and no in-progress flight

unfold
let create_post
: state -> Type0
= fun st ->
  parsed_bytes st == Seq.empty /\
  in_progress_flt st == F_none


/// create is a Pure function

val create (_:unit) : Pure state (requires True) (ensures create_post)


/// Precondition of all the receive functions
///
/// The input slice should be live
/// The passed begin and end indices should be properly ordered
/// Parsed bytes should remain same and in-progress flight (if set) should be the same

(* FIXME: I define here the type for const_slices as it used to be in
   LowParse.Repr, but we need it here just because this is the only
   place in miTLS where we are using validators, (whereas
   LowParse.Repr assumes an already valid buffer) Also, because we are
   not meant to be compositional in terms of parsers here, we require
   the length to be exactly equal to the size of the buffer. 

inline_for_extraction
noeq
type const_slice = {
  slice_base: C.const_buffer LP.byte;
  slice_len: (len: uint_32 { v len == C.length slice_base });
}

inline_for_extraction
let slice_of_const_slice (c: const_slice) : Tot (LP.slice (C.qbuf_pre (C.as_qbuf c.slice_base)) (C.qbuf_pre (C.as_qbuf c.slice_base))) = {
  LP.base = C.cast c.slice_base;
  LP.len = c.slice_len;
}

let live_slice (h: HS.mem) (c: const_slice) : GTot Type0 =
  LP.live_slice h (slice_of_const_slice c)

let slice_as_seq (h: HS.mem) (c: const_slice) : GTot LP.bytes =
  LP.bytes_of_slice_from h (slice_of_const_slice c) 0ul
*)

unfold
let receive_pre (st:state) (b:C.const_buffer LP.byte) (f_begin f_end:uint_32) (in_progress:in_progress_flt_t)
: HS.mem -> Type0
= fun h ->
  let open B in let open R in

  C.live h b /\
  v f_begin + length_parsed_bytes st <= v f_end /\
  v f_end <= C.length b /\

  Seq.equal (Seq.slice (C.as_seq h b) (v f_begin) (v f_begin + length_parsed_bytes st))
            (parsed_bytes st) /\

  (length_parsed_bytes st == 0 \/ in_progress_flt st == in_progress)


/// Postcondition of the receive functions
///
/// If there is an error in parsing, postconditions are under-specified
/// If we want more data, in-progress flight and parsed_bytes are set appropriately
/// If successful in parsing the flight, the returned flight is valid (in LowParse sense) and
///   in-progress flight and parsed bytes are reset in the returned state

unfold
let receive_post
  (#flt:Type)
  (st:state)
  (b:C.const_buffer LP.byte)
  (f_begin f_end:uint_32)
  (in_progress:in_progress_flt_t)
  (valid:uint_32 -> uint_32 -> flt -> HS.mem -> Type0)
  (h0:HS.mem)
  (x:TLS.Result.result (option flt & state))
  (h1:HS.mem)
= receive_pre st b f_begin f_end in_progress h0 /\
  B.(modifies loc_none  h0 h1) /\
  (let open TLS.Result in
   match x with
   | Error _ -> True
   | Correct (None, rst) ->
     in_progress_flt rst == in_progress /\
     parsed_bytes rst == Seq.slice (C.as_seq h0 b) (v f_begin) (v f_end)
   | Correct (Some flt, rst) ->
     valid f_begin f_end flt h1 /\
     parsed_bytes rst == Seq.empty /\
     in_progress_flt rst == F_none
   | _ -> False)


/// For most flights, the interface insists that there are no leftover bytes in the buffer
///
/// But for some flights, it is allowed to have leftover bytes
///
/// Following postcondition is slightly adjusted to account for it


unfold
let receive_post_with_leftover_bytes
  (#flt:Type)
  (st:state)
  (b:C.const_buffer LP.byte)
  (f_begin f_end:uint_32)
  (in_progress:in_progress_flt_t)
  (valid:uint_32 -> uint_32 -> flt -> HS.mem -> Type0)
  (h0:HS.mem)
  (x:TLS.Result.result (option (flt & uint_32) & state))
  (h1:HS.mem)
= receive_pre st b f_begin f_end in_progress h0 /\
  B.(modifies loc_none h0 h1) /\
  (let open TLS.Result in
   match x with
   | Error _ -> True
   | Correct (None, rst) ->
     in_progress_flt rst == in_progress /\
     parsed_bytes rst == Seq.slice (C.as_seq h0 b) (v f_begin) (v f_end)
   | Correct (Some (flt, idx_end), rst) ->
     idx_end <= f_end /\
     valid f_begin idx_end flt h1 /\
     parsed_bytes rst == Seq.empty /\
     in_progress_flt rst == F_none
   | _ -> False)



/// Error codes returned by the receive functions

let parsing_error = TLS.Result.({
  alert= Parsers.AlertDescription.Decode_error;
  cause= "Failed to validate incoming message" })

let unexpected_flight_error = TLS.Result.({
  alert= Parsers.AlertDescription.Unexpected_message;
  cause= "A message was received in a state where it was not expected" })

let leftover_bytes_error = TLS.Result.({
  alert= Parsers.AlertDescription.Decode_error;
  cause= "Leftover bytes after a key-transitioning message (Binders, non-retry SH, EOED, Finished)" })

let message_overflow_error = TLS.Result.({
  alert= Parsers.AlertDescription.Decode_error;
  cause= "Received message overflows input buffer length" })


/// Ad-hoc flights receive functions
///
/// Aligned with the states in TLS.Handshake.Machine


(*** ClientHello and ServerHello flights ***)


(****** Handshake state S_Idle ******)


/// Handshake state S_Idle expects the following flight
///
/// [ ClientHello ]
///
/// The following flight type covers this case


noeq type s_Idle (b:C.const_buffer LP.byte) = {
  ch : HSMR.ch_pos b
}

unfold
let valid_s_Idle
  (#b:C.const_buffer LP.byte) (f_begin f_end:uint_32)
  (flt:s_Idle b) (h:HS.mem)
= let open R in

  flt.ch.start_pos == f_begin /\
  R.end_pos flt.ch == f_end /\

  R.valid_repr_pos flt.ch h


val receive_s_Idle (st:state) (b:C.const_buffer LP.byte) (len: uint_32 { v len == C.length b }) (f_begin f_end:uint_32)
: ST (TLS.Result.result (option (s_Idle b) & state))
  (requires receive_pre st b f_begin f_end F_s_Idle)
  (ensures  receive_post st b f_begin f_end F_s_Idle valid_s_Idle)


(****** Handshake state C_wait_ServerHello ******)


/// Handshake state C_wait_ServerHello expects the following flight
///
/// [ ServerHello ]
///
/// The following flight type covers this case

noeq type c_wait_ServerHello (b:C.const_buffer LP.byte) = {
  sh : HSMR.sh_pos b
}

unfold
let valid_c_wait_ServerHello
  (#b:C.const_buffer LP.byte) (f_begin f_end:uint_32)
  (flt:c_wait_ServerHello b) (h:HS.mem)
= let open R in

  flt.sh.start_pos == f_begin /\
  R.end_pos flt.sh == f_end /\

  valid_repr_pos flt.sh h

(*
 * AR: 07/23: Cedric mentioned that for this flight, the buffer may have leftover bytes
 *            So we should not insist on consuming all the bytes [f_begin, f_end]
 *            In general, since the interface is ad-hoc anyway, we will decide this on a flight-by-flight basis
 *            Also, we don't enforce anything about the flight in the leftover bytes
 *
 *            The receive function then returns the flight and the index upto which the buffer was consumed
 *)

val receive_c_wait_ServerHello (st:state) (b:C.const_buffer LP.byte) (len: uint_32 { v len == C.length b }) (f_begin f_end:uint_32)
: ST (TLS.Result.result (option (c_wait_ServerHello b & uint_32) & state))
  (requires receive_pre st b f_begin f_end F_c_wait_ServerHello)
  (ensures  receive_post_with_leftover_bytes st b f_begin f_end F_c_wait_ServerHello valid_c_wait_ServerHello)


(*** 1.3 flights ***)


unfold let in_range_and_valid
  (#a:Type0) (#b:C.const_buffer LP.byte) (r:R.repr_pos a b)
  (f_begin f_end:uint_32) (h:HS.mem)
= let open R in
  f_begin <= r.start_pos /\ 
  R.end_pos r <= f_end /\  //in-range
  valid_repr_pos r h  //valid


(****** Handshake state C13_wait_Finished1 ******)

//19-05-28 CF: could we use vale-style metaprogramming on message lists? fine as is. 


/// Handshake state C13_wait_Finished1 expects three flights:
///
/// [ EncryptedExtensions13; Certificate13; CertificateVerify13; Finished13 ]
/// [ EncryptedExtensions13; CertificateRequest13; Certificate13; CertificateVerify13; Finished13 ]
/// [ EncryptedExtensions13; Finished13 ]
///
/// The following type covers all these cases

noeq type c13_wait_Finished1 (b:C.const_buffer LP.byte) = {
  c13_w_f1_ee   : HSM13R.ee13_pos b;
  c13_w_f1_cr   : option (HSM13R.cr13_pos b);
  c13_w_f1_c_cv : option (HSM13R.c13_pos b & HSM13R.cv13_pos b);
  c13_w_f1_fin  : HSM13R.fin13_pos b
}


/// The validity predicate, such as the following, are underspecified in that
///   they only say that all the messages in the flight are between from and to
///   and don't say that they are actually stitched in order


unfold
let valid_c13_wait_Finished1
  (#b:C.const_buffer LP.byte) (f_begin f_end:uint_32)
  (flt:c13_wait_Finished1 b) (h:HS.mem)
= R.(flt.c13_w_f1_ee.start_pos == f_begin /\
     end_pos flt.c13_w_f1_fin == f_end)   /\  //flight begins at from and finishes at to

  in_range_and_valid flt.c13_w_f1_ee f_begin f_end h /\
    
  (Some? flt.c13_w_f1_cr ==> in_range_and_valid (Some?.v flt.c13_w_f1_cr) f_begin f_end h) /\
    
  (Some? flt.c13_w_f1_c_cv ==>
    (let c13_msg, cv13_msg = Some?.v flt.c13_w_f1_c_cv in
     in_range_and_valid c13_msg f_begin f_end h /\
     in_range_and_valid cv13_msg f_begin f_end h)) /\

  in_range_and_valid flt.c13_w_f1_fin f_begin f_end h


val receive_c13_wait_Finished1
  (st:state) (b:C.const_buffer LP.byte) (len: uint_32 { v len == C.length b }) (f_begin f_end:uint_32)
: ST (TLS.Result.result (option (c13_wait_Finished1 b) & state))
  (requires receive_pre st b f_begin f_end F_c13_wait_Finished1)
  (ensures  receive_post st b f_begin f_end F_c13_wait_Finished1 valid_c13_wait_Finished1)


(****** Handshake state S13_wait_Finished2 ******)


/// Handshake state S13_wait_Finished2 expects two flights:
///
/// [ Finished13 ]
/// [ Certificate13; CertificateVerify13; Finished13 ]
///
/// The following type covers both these cases


noeq type s13_wait_Finished2 (b:C.const_buffer LP.byte) = {
  s13_w_f2_c_cv : option (HSM13R.c13_pos b & HSM13R.cv13_pos b);
  s13_w_f2_fin  : HSM13R.fin13_pos b
}

unfold
let valid_s13_wait_Finished2
  (#b:C.const_buffer LP.byte) (f_begin f_end:uint_32)
  (flt:s13_wait_Finished2 b) (h:HS.mem)
= match flt.s13_w_f2_c_cv with
  | Some (c_msg, cv_msg) ->
    R.(c_msg.start_pos == f_begin    /\
       end_pos flt.s13_w_f2_fin == f_end) /\

    in_range_and_valid c_msg f_begin f_end h /\

    in_range_and_valid cv_msg f_begin f_end h /\

    in_range_and_valid flt.s13_w_f2_fin f_begin f_end h

  | None ->
    R.(flt.s13_w_f2_fin.start_pos == f_begin /\
       end_pos flt.s13_w_f2_fin   == f_end)  /\

    in_range_and_valid flt.s13_w_f2_fin f_begin f_end h


val receive_s13_wait_Finished2 (st:state) (b:C.const_buffer LP.byte) (len: uint_32 { v len == C.length b }) (f_begin f_end:uint_32)
: ST (TLS.Result.result (option (s13_wait_Finished2 b) & state))
  (requires receive_pre st b f_begin f_end F_s13_wait_Finished2)
  (ensures  receive_post st b f_begin f_end F_s13_wait_Finished2 valid_s13_wait_Finished2)


(****** Handshake state S13_wait_EOED ******)


/// Handshake state S13_wait_EOED expects
///
/// [ EndOfEarlyData13 ]
///
/// The following flight type covers this


noeq type s13_wait_EOED (b:C.const_buffer LP.byte) = {
  eoed : HSM13R.eoed13_pos b
}


unfold
let valid_s13_wait_EOED
  (#b:C.const_buffer LP.byte) (f_begin f_end:uint_32)
  (flt:s13_wait_EOED b) (h:HS.mem)
= let open R in

  flt.eoed.start_pos == f_begin /\
  end_pos flt.eoed == f_end     /\

  valid_repr_pos flt.eoed h

val receive_s13_wait_EOED (st:state) (b:C.const_buffer LP.byte) (len: uint_32 { v len == C.length b }) (f_begin f_end:uint_32)
: ST (TLS.Result.result (option (s13_wait_EOED b) & state))
  (requires receive_pre st b f_begin f_end F_s13_wait_EOED)
  (ensures  receive_post st b f_begin f_end F_s13_wait_EOED valid_s13_wait_EOED)


(****** Handshake state C13_Complete ******)


/// Handshake state C13_Complete expects
///
/// [ NewSessionTicket13 ]
///
/// The following flight type covers this


noeq type c13_Complete (b:C.const_buffer LP.byte) = {
  c13_c_nst : HSM13R.nst13_pos b
}

unfold
let valid_c13_Complete
  (#b:C.const_buffer LP.byte) (f_begin f_end:uint_32)
  (flt:c13_Complete b) (h:HS.mem)
= let open R in

  flt.c13_c_nst.start_pos == f_begin /\
  R.end_pos flt.c13_c_nst == f_end     /\
  valid_repr_pos flt.c13_c_nst h


val receive_c13_Complete (st:state) (b:C.const_buffer LP.byte) (len: uint_32 { v len == C.length b }) (f_begin f_end:uint_32)
: ST (TLS.Result.result (option (c13_Complete b & uint_32) & state))
  (requires receive_pre st b f_begin f_end F_c13_Complete)
  (ensures receive_post_with_leftover_bytes st b f_begin f_end F_c13_Complete valid_c13_Complete)


(*** 1.2 flights ***)


(****** Handshake state C12_wait_ServerHelloDone ******)


/// Handshake state C12_wait_ServerHelloDone expects two flights
///
/// [ Certificate12; ServerKeyExchange12; ServerHelloDone12 ]
/// [ Certificate12; ServerKeyExchange12; CertificateRequest12; ServerHelloDone12 ]
///
/// The following flight type covers both these cases


noeq type c12_wait_ServerHelloDone (b:C.const_buffer LP.byte) = {
  c   : HSM12R.c12_pos b;
  ske : HSM12R.ske12_pos b;
  cr  : option (HSM12R.cr12_pos b);
  shd : HSM12R.shd12_pos b
}

unfold
let valid_c12_wait_ServerHelloDone
  (#b:C.const_buffer LP.byte) (f_begin f_end:uint_32)
  (flt:c12_wait_ServerHelloDone b) (h:HS.mem)
= R.(flt.c.start_pos == f_begin /\
     end_pos flt.shd == f_end)  /\

  in_range_and_valid flt.c f_begin f_end h /\

  in_range_and_valid flt.ske f_begin f_end h /\

  (Some? flt.cr ==> in_range_and_valid (Some?.v flt.cr) f_begin f_end h) /\

  in_range_and_valid flt.shd f_begin f_end h
  

val receive_c12_wait_ServerHelloDone (st:state) (b:C.const_buffer LP.byte)  (len: uint_32 { v len == C.length b }) (f_begin f_end:uint_32)
: ST (TLS.Result.result (option (c12_wait_ServerHelloDone b) & state))
  (requires receive_pre st b f_begin f_end F_c12_wait_ServerHelloDone)
  (ensures  receive_post st b f_begin f_end F_c12_wait_ServerHelloDone valid_c12_wait_ServerHelloDone)


(****** Handshake states C12_wait_Finished2, C12_wait_R_Finished1, S12_wait_Finished1, and S12_wait_CF2 ******)


/// All the above mentioned Handshake states expect the following flight
///
/// [ Finished12 ]
///
/// The following flight type covers this case


noeq type cs12_wait_Finished (b:C.const_buffer LP.byte) = {
  fin : HSM12R.fin12_pos b
}


unfold
let valid_cs12_wait_Finished
  (#b:C.const_buffer LP.byte) (f_begin f_end:uint_32)
  (flt:cs12_wait_Finished b) (h:HS.mem)
= let open R in

  flt.fin.start_pos == f_begin /\
  end_pos flt.fin == f_end /\

  valid_repr_pos flt.fin h


val receive_cs12_wait_Finished (st:state) (b:C.const_buffer LP.byte) (len: uint_32 { v len == C.length b }) (f_begin f_end:uint_32)
: ST (TLS.Result.result (option (cs12_wait_Finished b) & state))
  (requires receive_pre st b f_begin f_end F_cs12_wait_Finished)
  (ensures  receive_post st b f_begin f_end F_cs12_wait_Finished valid_cs12_wait_Finished)


(****** Handshake state C12_wait_NST ******)


/// Handshake state C12_wait_NST expects the following flight
///
/// [ NewSessionticket12 ]
///
/// The following flight type covers this case

noeq type c12_wait_NST (b:C.const_buffer LP.byte) = {
  c12_w_n_nst : HSM12R.nst12_pos b
}


unfold
let valid_c12_wait_NST
  (#b:C.const_buffer LP.byte) (f_begin f_end:uint_32)
  (flt:c12_wait_NST b) (h:HS.mem)
= let open R in

  flt.c12_w_n_nst.start_pos == f_begin /\

  end_pos flt.c12_w_n_nst == f_end /\

  valid_repr_pos flt.c12_w_n_nst h


val receive_c12_wait_NST (st:state) (b:C.const_buffer LP.byte) (len: uint_32 { v len == C.length b }) (f_begin f_end:uint_32)
: ST (TLS.Result.result (option (c12_wait_NST b) & state))
  (requires receive_pre st b f_begin f_end F_c12_wait_NST)
  (ensures  receive_post st b f_begin f_end F_c12_wait_NST valid_c12_wait_NST)



(****** Handshake state S12_wait_CCS1 ******)


/// Handshake state S12_wait_CCS1 expects the following flight
///
/// [ ClientKeyExchange12 ]
///
/// The following flight type covers this case


noeq type s12_wait_CCS1 (b:C.const_buffer LP.byte) = {
  cke : HSM12R.cke12_pos b
}


unfold
let valid_s12_wait_CCS1
  (#b:C.const_buffer LP.byte) (f_begin f_end:uint_32)
  (flt:s12_wait_CCS1 b) (h:HS.mem)
= let open R in

  flt.cke.start_pos == f_begin /\
  end_pos flt.cke == f_end /\

  valid_repr_pos flt.cke h


val receive_s12_wait_CCS1 (st:state) (b:C.const_buffer LP.byte) (len: uint_32 { v len == C.length b }) (f_begin f_end:uint_32)
: ST (TLS.Result.result (option (s12_wait_CCS1 b) & state))
  (requires receive_pre st b f_begin f_end F_s12_wait_CCS1)
  (ensures  receive_post st b f_begin f_end F_s12_wait_CCS1 valid_s12_wait_CCS1)
