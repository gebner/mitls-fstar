(** Expansion of secrets into expanded secrets and salts *)
module MiTLS.KDF.Expand
open MiTLS

open FStar.Heap

open FStar.HyperStack

open FStar.Bytes
open FStar.Error
open MiTLS.TLSError
open MiTLS.TLSConstants
open MiTLS.TLSInfo

module MM = FStar.Monotonic.Map


module HS = FStar.HyperStack

assume val ideal_Expand : bool

(* Source index is a secret index *)
type id = secretId

(* The kind of expansion, either salt of expanded secret *)
type expand_kind (i:id) =
  | ExpandSalt: expand_kind i
  | ExpandSecret:
     log: hashed_log ->
     li: logInfo{
         (EarlySecretID? i ==> LogInfo_CH? li) /\
         (HandshakeSecretID? i ==> LogInfo_SH? li) /\
         (ApplicationSecretID? i ==> LogInfo_SF? li) /\
         log_info li log
       } ->
     expand_kind i

type extracted_secret (#i:id) (x:expand_kind i) =
  lbytes (Hashing.Spec.Spec.Hash.Definitions.hash_len (secretId_hash i))

type expand_log (i:id) (r:rgn) =
  (if ideal_Expand then
    MM.t r (expand_kind i) extracted_secret (fun _ -> True)
  else
    unit)

type state (i:id) =
  | State:
    r:rgn ->
    log: expand_log i r ->
    state i

let kdf_region:rgn = new_region tls_tables_region
type kdf_instance_table =
  (if Flags.ideal_KEF then
    MM.t kdf_region id state (fun _ -> True)
  else
    unit)

let kdf_instances : kdf_instance_table =
  (if Flags.ideal_KEF then
    MM.alloc #kdf_region #id #state #(fun _ -> True)
  else
    ())

(*)
let create (i:id) (k:expand_kind i) : ST (state i)
  (requires ())
  (ensures ())
  =
*)

type salt (i:id) =
  (match i.kef_type with
  | PSK _  | DH _ _ -> unit
  | DH_PSK esId _ _ ->
    expanded_secret (EarlySecretID esId)
  | ZERO hsId ->
    expanded_secret (HandshakeSecretID hsId))

// The type of the input key material to extract
type ikm (i:id) (ir:role i) =
  (match i.kef_type with
  | PSK pski -> PSK.psk pski
  | DH g si | DH_PSK _ g si ->
    if ir = Initiator then CommonDH.secret g
    else unit
  | ZERO _ -> unit)

type extracted_secret (i:id) =
  lbytes (keflen i.alg)

type extractor_instance (i:id) =
  (match i.kef_type with
  | PSK _ | ZERO _ -> KEF_PRF.state i
  | DH _ _ _ -> KEF_PRF_ODH.state i
  | DH_PSK esId _ _ _ ->
    if honest_esId esId then
      KEF_PRF.state i
    else
      KEF_PRF_ODH.state i)
