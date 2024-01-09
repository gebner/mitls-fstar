module MiTLS.AEADOpenssl
open MiTLS

open FStar.Heap
open FStar.HyperStack
open FStar.Seq
open FStar.Bytes
open MiTLS.CoreCrypto

open MiTLS.Mem
open MiTLS.TLSConstants
open MiTLS.TLSInfo

module MDM = FStar.Monotonic.DependentMap
module HS = FStar.HyperStack
module HST = FStar.HyperStack.ST

type id = i:id{~(PlaintextID? i) /\ AEAD? (aeAlg_of_id i)}
let alg (i:id) = AEAD?._0 (aeAlg_of_id i)

let keylen i = aeadKeySize (alg i)
let taglen i = aeadTagSize (alg i)
let ivlen i = aeadRealIVSize (alg i)

type key (i:id) = lbytes (keylen i)
type iv  (i:id) = lbytes (ivlen i)

// ADL: experimental style for plaintexts
// Built-in plaintext abstraction using "irreductible"
// (to simulate abstract plaintexts within the same module)
type plainlen = n:nat{n <= max_TLSPlaintext_fragment_length}
(* irreducible *) type plain (i:id) (l:plainlen) = lbytes l
let repr (#i:id) (#l:plainlen) (p:plain i l) : Tot (lbytes l) = p

// Additional data
let adlen i = match pv_of_id i with
  | TLS_1p3 -> 0 | _ -> 13
type adata i = lbytes (adlen i)

// Ciphertexts
let cipherlen i (l:plainlen) : n:nat{n >= taglen i} = l + taglen i
type cipher i (l:plainlen) = lbytes (cipherlen i l)

// Log
type entry (#i:id) (iv:iv i) =
  | Entry:
    #l:plainlen  ->
    ad:adata i   ->
    p:plain i l  ->
    c:cipher i l ->
    entry iv

type no_inv m = True
let ideal_log (r:rgn) (i:id) = MDM.t r (iv i) entry no_inv
let log_ref (r:rgn) (i:id) : Tot Type0 =
  if authId i then ideal_log r i else unit

let ilog (#r:rgn) (#i:id) (l:log_ref r i{authId i})
 : Tot (ideal_log r i) = l

let ilog_as_ref (#r:rgn) (#i:id) (l:ideal_log r i{authId i})
 : Tot (log_ref r i) = l

let unit_as_ref (r:rgn) (i:id{~ (authId i)})
 : Tot (log_ref r i) = ()

noeq type state (i:id) (rw:rw) =
  | State:
    region: rgn ->
    #log_region:rgn{
       if rw = Writer then region = log_region
       else HS.disjoint region log_region} ->
    key: key i ->
    log: log_ref log_region i ->
    state i rw

type empty_log (#i:id) (#rw:rw) (st:state i rw) h =
  authId i ==>
    (h `HS.contains` (ilog st.log) /\
     HS.sel h (ilog st.log) == MDM.empty)

type writer i = s:state i Writer
type reader i = s:state i Reader

let genPost (#i:id) (parent:rgn) h0 (w:writer i) h1 =
  modifies Set.empty h0 h1 /\
  extends w.region parent /\
  HS.fresh_region w.region h0 h1 /\
  color w.region = color parent /\
  empty_log w h1

#set-options "--z3rlimit 100 --initial_fuel 1 --max_fuel 1 --initial_ifuel 1 --max_ifuel 1"
val gen: parent:rgn -> i:id -> ST (writer i)
  (requires (fun h0 -> True))
  (ensures  (genPost parent))
let gen parent i =
  let kv : key i = Random.sample (keylen i) in
  let writer_r = new_region parent in
  cut (is_eternal_region writer_r);
  if authId i then
    let log : ideal_log writer_r i = MDM.alloc () in
    State writer_r kv (ilog_as_ref log)
  else
    State writer_r kv (unit_as_ref writer_r i)

// A reader r peered with the writer w
type peered (#i:id) (w:writer i) =
  r:reader i{
   w.key = r.key /\
   r.log_region = w.region /\
   eq2 #(log_ref w.region i) w.log r.log
  }

val genReader: parent:rgn -> #i:id -> w:writer i -> ST (peered w)
  (requires (fun h0 -> HS.disjoint parent w.region))
  (ensures (fun h0 r h1 ->
    modifies Set.empty h0 h1 /\
    extends r.region parent /\
    color r.region = color parent /\
    HS.fresh_region r.region h0 h1))
let genReader parent #i w =
  let reader_r = new_region parent in
  if authId i then
    let log : ideal_log w.region i = w.log in
    State reader_r #w.region w.key log
  else
    State reader_r #w.region w.key ()

val coerce: parent:rgn -> i:id{~(authId i)} -> kv:key i -> ST (writer i)
  (requires (fun h0 -> True))
  (ensures  (genPost parent))
let coerce parent i kv =
  let writer_r = new_region parent in
  State writer_r kv (unit_as_ref writer_r i)

val leak: #i:id -> #role:rw -> state i role -> ST (key i)
  (requires (fun h0 -> ~(authId i)))
  (ensures  (fun h0 r h1 -> modifies_none h0 h1))
let leak #i #role s = State?.key s

type fresh_iv (#i:id{authId i}) (w:writer i) (iv:iv i) h =
  MDM.fresh (ilog w.log) iv h

type defined_iv (#i:id{authId i}) (#rw:rw) (s:state i rw) (iv:iv i) h =
  MDM.defined (ilog s.log) iv h

let logged_iv (#i:id{authId i}) (#rw:rw) (s:state i rw) (iv:iv i) (e:entry #i iv) h =
  MDM.contains (ilog s.log) iv e h

val encrypt: #i:id -> #l:plainlen -> e:writer i ->
             iv:iv i -> ad:adata i -> p:plain i l -> ST (cipher i l)
  (requires (fun h0 -> authId i ==> fresh_iv #i e iv h0))
  (ensures (fun h0 c h1 ->
    modifies_one e.log_region h0 h1 /\
    (authId i ==> logged_iv #i #Writer e iv (Entry ad p c) h1) /\
    (~(authId i) ==> c = aead_encryptT (alg i) (State?.key e) iv ad p)))

let encrypt #i #l e iv ad p =
  if authId i then
    begin
      let log = ilog e.log in
      HST.recall log;
      let c = Random.sample (cipherlen i l) in
      MDM.extend log iv (Entry ad p c);
      c
    end
  else
    aead_encrypt (alg i) (State?.key e) iv ad p

type correct_decrypt (#i:id) (#l:plainlen) (r:reader i) (iv:iv i) (ad:adata i)
                     (c:cipher i l) (po:option (plain i l)) (h:HS.mem) =
  (authId i ==>
    (defined_iv #i r iv h ==>
      (let Entry ad' p c' = MDM.value_of (ilog r.log) iv h in
        ((ad'=ad /\ c'=c) ==> po = Some p)))) /\
  (~(authId i) ==>
    (forall (p:plain i l).{:pattern (aead_encryptT (alg i) (State?.key r) iv ad p)}
      c = aead_encryptT (alg i) (State?.key r) iv ad p ==> po = Some p))

val decrypt: #i:id -> #l:plainlen -> d:reader i ->
  iv:iv i -> ad:adata i -> c:cipher i l -> ST (option (plain i l))
  (requires (fun h0 -> True))
  (ensures  (fun h0 res h1 ->
     modifies_none h0 h1 /\
     ((authId i /\ Some? res) ==> logged_iv #i #Reader d iv (Entry ad (Some?.v res) c) h1) /\
     correct_decrypt d iv ad c res h1
  ))

#set-options "--admit_smt_queries true" //18-02-18 
let decrypt #i #l d iv ad c =
  if authId i then
   begin
    let log = ilog d.log in
    HST.recall log;
    match MDM.lookup log iv with
    | None -> assume false; None
    | Some (Entry ad' p c') ->
      if ad' = ad && c' = c then
       begin
        Some p
       end
      else None
   end
  else
    match aead_decrypt (alg i) (State?.key d) iv ad c with
    | Some p ->
      cut (length p + taglen i = length c);
      Some p
    | None -> None

(* Functional correctness test: decrypt iv ad (encrypt iv ad p) = p *)
(* (regardless of authId i)*)
let test_correctness (i:id{pv_of_id i = TLS_1p3}) : St unit =
  let wr = new_region tls_region in
  let rr = new_region tls_region in
  let w = gen wr i in
  let l : plainlen = 0 in
  let ad : adata i = empty_bytes in
  let plain : plain i l = empty_bytes in
  let iv : iv i = Random.sample (ivlen i) in
  let cipher : cipher i l = encrypt w iv ad plain in
  let r = genReader rr w in
  let p' = decrypt r iv ad cipher in
  assert(p' = Some plain)
