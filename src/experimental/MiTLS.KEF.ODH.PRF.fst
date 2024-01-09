(** Expansion of secrets into expanded secrets and salts *)
module MiTLS.KEF.PRF_PSK
open MiTLS
module HST = FStar.HyperStack.ST //Added automatically

open FStar.Heap

open FStar.HyperStack

open FStar.Bytes
open FStar.Error
open MiTLS.TLSError
open MiTLS.TLSConstants
open MiTLS.TLSInfo

module MM = FStar.Monotonic.Map


module HS = FStar.HyperStack

assume val ideal_KEF_PSK : bool

(* Source index is a PSK index *)
type id = PSK.pskid

type extractor (i:id) =
  (j:secretId{EarlySecretID? j} & KDF.Expand.state j)
type saltor (i:id) =
  (j:secretId{EarlySecretID? j} & KDF.Salt.ODH.state j)
type entry (i:id) = extractor i * saltor i

private let r_kef_prf_psk:rgn = new_region tls_tables_region
private type ideal_mlog = MM.t r_kef_prf_psk id entry (fun _ -> True)
private type mlog_t = (if Flags.ideal_KEF then ideal_mlog else unit)
private let mlog : mlog_t =
  if Flags.ideal_KEF then MM.alloc #r_kef_prf_psk #id #entry #(fun _ -> True)
  else ()

let extract (i:id) (b:bool) : ST (entry i)
  (requires (fun h0 -> True))
  (ensures (fun h0 r h1 ->
    (if Flags.ideal_KEF then
      modifies_one r_kef_prf_psk h0 h1
    else modifies_none h0 h1)
  ))
  =
  let psk = PSK.psk_value i in
  let pski = PSK.psk_info i in
  let ha = pskInfo_hash pski in
  admit()

(*
let log_cmp (#i:id) (a:log i) (b:log i) =
  match a, b with
  | Some (u, v) , Some (u', v') -> u == u' /\ v == v'
  | None, _                     -> True
  | _                           -> False

type state (i:id) =
  | State:
    r:rgn ->
    key: PSK.app_psk i ->
    log: HST.m_rref r (log i) log_cmp ->
    state i
*)
