module MiTLS.Random
open MiTLS

open FStar.Bytes
open FStar.Error

open MiTLS.Mem
open MiTLS.TLSError

val discard: bool -> ST unit
  (requires (fun _ -> True))
  (ensures (fun h0 _ h1 -> h0 == h1))
let discard _ = ()
let print s = discard (IO.debug_print_string ("RNG| "^s^"\n"))
unfold val trace: s:string -> ST unit
  (requires (fun _ -> True))
  (ensures (fun h0 _ h1 -> h0 == h1))
unfold let trace = if DebugFlags.debug_KS then print else (fun _ -> ())

(*
RNG is provided by EverCrypt and must be seeded before use
This is done by FF_mitls_init and automatically in Evercrypt
when possible
*)

let init () : ST UInt32.t
  (requires fun h0 -> True)
  (ensures fun h0 _ h1 -> modifies_none h0 h1)
  =
//  let h0 = get() in
//  assume(EverCrypt.Specs.random_init_pre h0);
  assume false;
  EverCrypt.AutoConfig2.(init ());
  EverCrypt.random_init ()

let cleanup () : ST unit
  (requires fun h0 -> True)
  (ensures fun h0 _ h1 -> modifies_none h0 h1)
  =
  assume false; // Precondition of random_cleanup in EverCrypt
  EverCrypt.random_cleanup ()

let sample32 (len:UInt32.t) : ST (lbytes (UInt32.v len))
  (requires fun h0 -> True)
  (ensures fun h0 _ h1 -> modifies_none h0 h1)
  =
  if len = 0ul then Bytes.empty_bytes else (
  push_frame ();
  let b = LowStar.Buffer.alloca 0uy len in
  assume false; // Precondition of random_sample in EverCrypt
  EverCrypt.random_sample len b;
  let r = Bytes.of_buffer len b in
  trace ("Sampled: "^(hex_of_bytes r));
  pop_frame ();
  r)

let sample (len:nat{len < pow2 32}) : ST (lbytes len)
  (requires fun h0 -> True)
  (ensures fun h0 _ h1 -> modifies_none h0 h1)
  =
  sample32 (UInt32.uint_to_t len)
