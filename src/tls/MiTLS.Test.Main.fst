module MiTLS.Test.Main
open MiTLS

open FStar.HyperStack.ST
open FStar.HyperStack.IO

#set-options "--admit_smt_queries true"

inline_for_extraction
let check s (f: unit -> St C.exit_code): St unit =
  match f () with
  | C.EXIT_SUCCESS ->
      C.(ignore (fflush stdout); ignore (fflush stderr));
      print_string "✔ ";
      print_string s;
      print_string "\n"
  | C.EXIT_FAILURE ->
      C.(ignore (fflush stdout); ignore (fflush stderr));
      print_string "✘ ";
      print_string s;
      print_string "\n";
      C.exit 255l

let rec iter (xs:list (string * (unit -> St C.exit_code))) : St unit =
  match xs with
  | [] -> ()
  | (s,f) :: xs -> check s f; iter xs

let handshake () =
  Test.Handshake.main "CAFile.pem" "server-ecdsa.crt" "server-ecdsa.key" ()

let iv () = 
  IV.test(); 
  C.EXIT_SUCCESS

let main (): St C.exit_code =
  ignore (FStar.Test.dummy ());
  if Random.init () = 0ul then
    begin
    print_string "✘ RNG initialization\n";
    C.EXIT_FAILURE
    end
  else
    begin
    print_string "✔ RNG initialization\n";
    iter [
      "BufferBytes", MiTLS.Test.BufferBytes.main;
      "TLSConstants", MiTLS.Test.TLSConstants.main;
      "AEAD", MiTLS.Test.AEAD.main;
      "StAE", MiTLS.Test.StAE.main;
      "CommonDH", MiTLS.Test.CommonDH.main;
      // 2018.04.25: Enable once the regression is fixed
      "Handshake", handshake;
      "IV", iv;
      "Rekey", KDF.Rekey.test_rekey;
//      "Parsers", MiTLS.Test.Parsers.main;
      (* ADD NEW TESTS HERE *)
    ];
    C.EXIT_SUCCESS
    end
