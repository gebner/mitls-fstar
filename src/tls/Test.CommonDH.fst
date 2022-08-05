module Test.CommonDH

open FStar.Bytes
open FStar.Error
open FStar.Printf
open FStar.HyperStack
open FStar.HyperStack.ST

open TLSError
open TLSConstants
open Parsers.NamedGroup
open Parsers.NamedGroupList

module DH = CommonDH

#set-options "--admit_smt_queries true"

let prefix = "Test.CommonDH"

val discard: bool -> ST unit
  (requires (fun _ -> True))
  (ensures (fun h0 _ h1 -> h0 == h1))
let discard _ = ()
let print s = discard (IO.debug_print_string (prefix^": "^s^".\n"))
// let print = C.String,print
// let print = FStar.HyperStack.IO.print_string

val test: DH.group -> St bool
let test group =
  let initiator_key_and_share = DH.keygen group in
  let gx = DH.ipubshare initiator_key_and_share in
  let gy, gxy = DH.dh_responder group gx in
  let gxy' = DH.dh_initiator group initiator_key_and_share gy in
  let gxy  = hex_of_bytes gxy in
  let gxy' = hex_of_bytes gxy' in
  if gxy = gxy' then true
  else
    begin
      print ("Unexpected output: output = " ^ gxy' ^ "\nexpected = " ^ gxy);
      false
    end
 
let groups : namedGroupList =
  [
    Secp256r1;
    Secp384r1;
    Secp521r1;
    X25519;
    Ffdhe2048;
    Ffdhe3072;
    Ffdhe4096;
    Ffdhe6144;
    Ffdhe8192;
    // TODO: Not implemented; see ECGroup.fst
    //X448
  ]
  
let rec test_groups (groups:list namedGroup) : St bool =
  match groups with
  | g :: gs ->
    let Some group = DH.group_of_namedGroup g in
    print ("Testing " ^ DH.string_of_group group);
    if not (test group) then false else test_groups gs
  | _ -> true

// Called from Test.Main
let main () =
  if test_groups groups then C.EXIT_SUCCESS else C.EXIT_FAILURE
