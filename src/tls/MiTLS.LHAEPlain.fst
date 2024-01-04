module MiTLS.LHAEPlain
open MiTLS

open FStar.Seq
open FStar.Bytes
open FStar.Error

open MiTLS.TLSError
open MiTLS.TLSConstants
open MiTLS.TLSInfo
module Parse = MiTLS.Parse
open MiTLS.Parse

module Range = MiTLS.Range
let range = Range.range
let rbytes = Range.rbytes

//--------------------------------------------------------------------
// `Plain' interface towards LHAE
//--------------------------------------------------------------------

// We define payloads and additional data from those of StatefulPlain,
// adding an 8-byte sequence number to its additional data.

type id = i:id { ID12? i }

type seqn = n:nat{repr_bytes n <= 8}
let ad_Length i = 8 + StatefulPlain.ad_Length i

val parseAD: b:bytes { length b >= 8 } -> Tot bytes
let parseAD b = snd(split b 8ul)

type adata (i:id) = b:lbytes (ad_Length i)
  { exists (ad:StatefulPlain.adata i). ad == parseAD b}

#set-options "--admit_smt_queries true"
let makeAD i seqn (ad:StatefulPlain.adata i) : adata i =
  let b = bytes_of_seq seqn @| ad in
  cut(Bytes.equal ad (parseAD b));
  b
#reset-options

#reset-options "--using_facts_from '* -LowParse.Spec.Base'"

val seqN: i:id -> adata i -> Tot seqn
let seqN i ad =
//18-02-26 review?
//    let snb,ad = FStar.Bytes.split_eq ad 8 in //TODO bytes NS 09/27
    let snb,ad = FStar.Bytes.split ad 8ul in    
    seq_of_bytes snb

val lemma_makeAD_seqN: i:id -> n:seqn -> ad:StatefulPlain.adata i
          -> Lemma (requires (True))
                   (ensures (seqN i (makeAD i n ad) = n))
                   [SMTPat (makeAD i n ad)]

let lemma_makeAD_seqN i n ad = admit() 
    //TODO bytes NS 09/27
    // cut (Seq.equal (fst (Seq.split_eq (bytes_of_seq n @| ad) 8)) (bytes_of_seq n));
    // int_of_bytes_of_int (Seq.length (bytes_of_seq n)) n

#set-options "--admit_smt_queries true"
val lemma_makeAD_parseAD: i:id -> n:seqn -> ad:StatefulPlain.adata i
          -> Lemma (requires (True))
                   (ensures (parseAD (makeAD i n ad) = ad))
                   [SMTPat (makeAD i n ad)]
let lemma_makeAD_parseAD i n ad = cut (Bytes.equal ad (parseAD (makeAD i n ad)))
#reset-options

// let test i (n:seqn) (m:seqn{m<>n}) (ad:adata i) =
//   assert (makeAD i n ad <> makeAD i m ad)

type plain (i:id) (ad:adata i) (r:range) = StatefulPlain.plain i (parseAD ad) r

val ghost_repr: #i:id -> #ad:adata i -> #rg:range -> plain i ad rg -> GTot bytes
let ghost_repr #i #ad #rg pf = StatefulPlain.ghost_repr #i #(parseAD ad) #rg pf

val repr: i:id{ ~(safeId i)} -> ad:adata i -> r:range -> p:plain i ad r -> Tot (b:rbytes r {b = ghost_repr #i #ad #r p})
let repr i ad rg p = StatefulPlain.repr i (parseAD ad) rg p

val mk_plain: i:id{ ~(authId i)} -> ad:adata i -> 
  rg:(Range.frange i){ StatefulPlain.wf_ad_rg i (parseAD ad) rg } ->
  b:rbytes rg { StatefulPlain.wf_payload_ad_rg i (parseAD ad) rg b } ->
    Tot (p:plain i ad rg {b = ghost_repr #i #ad #rg p})
let mk_plain i ad rg b = StatefulPlain.mk_plain i (parseAD ad) rg b


(*Revive extending padding at some point?*)

let makeExtPad id ad rg p = p
// StatefulPlain.makeExtPad id (parseAD id ad) rg p

let parseExtPad id ad rg p = Correct p
//    match StatefulPlain.parseExtPad id (parseAD id ad) rg p with
//    | Error x -> Error x
//    | Correct c -> Correct c

