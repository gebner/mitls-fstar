module LowParse.Low.Base
include LowParse.Spec.Base

module B = LowStar.Buffer
module M = LowStar.ModifiesPat
module U32 = FStar.UInt32
module HS = FStar.HyperStack
module HST = FStar.HyperStack.ST
module I32 = FStar.Int32
module Cast = FStar.Int.Cast
module MA = LowParse.Math

let int32_to_uint32_pos
  (x: I32.t)
: Lemma
  (requires (I32.v x >= 0))
  (ensures (U32.v (Cast.int32_to_uint32 x) == I32.v x))
  [SMTPat (U32.v (Cast.int32_to_uint32 x))]
= MA.modulo_lemma (I32.v x) (pow2 32)

let uint32_to_int32_bounded
  (x: U32.t)
: Lemma
  (requires (U32.v x < 2147483648))
  (ensures (I32.v (Cast.uint32_to_int32 x) == U32.v x))
  [SMTPat (I32.v (Cast.uint32_to_int32 x))]
= MA.modulo_lemma (U32.v x) (pow2 32)

inline_for_extraction
type buffer8 = B.buffer FStar.UInt8.t

inline_for_extraction
type pointer (t: Type) = (b: B.buffer t { B.length b == 1 } )

let is_slice (h: HS.mem) (#t: Type) (b: B.buffer t) (len: I32.t) : GTot Type0 =
  B.live h b /\
  B.length b == I32.v len

unfold
let gsub
  (#t: Type)
  (b: B.buffer t)
  (i: U32.t)
  (len: U32.t)
: Ghost (B.buffer t)
  (requires (U32.v i + U32.v len <= B.length b))
  (ensures (fun b' -> B.length b' == U32.v len))
= B.gsub b i len

let is_tail_of (#t: Type) (b' b : B.buffer t) : GTot Type0 =
  B.length b' <= B.length b /\
  b' == gsub b (U32.uint_to_t (B.length b - B.length b')) (U32.uint_to_t (B.length b'))

let tail_ptr (h h' : HS.mem) (#t: Type) (p: pointer (B.buffer t)) : GTot Type0 =
  B.live h p /\
  B.live h' p /\ (
    let b = B.get h p 0 in
    let b' = B.get h' p 0 in
    B.live h b /\
    B.live h' b /\
    b' `is_tail_of` b
  )

let parse_from_slice
  (#k: parser_kind)
  (#t: Type0)
  (p: parser k t)
  (h: HS.mem)
  (b: buffer8)
  (sz: I32.t)
: Ghost (option (t * nat))
  (requires (is_slice h b sz))
  (ensures (fun y ->
    match y with
    | None -> parse p (B.as_seq h b) == None
    | Some (x, len) -> len <= B.length b /\ parse p (B.as_seq h b) == Some (x, len)
  ))
= match parse p (B.as_seq h b) with
  | Some (x, len) -> Some (x, len)
  | _ -> None

let exactly_parse_from_slice
  (#k: parser_kind)
  (#t: Type0)
  (p: parser k t)
  (h: HS.mem)
  (b: buffer8)
  (sz: I32.t)
: Ghost (option t)
  (requires (is_slice h b sz))
  (ensures (fun y ->
    match y with
    | None ->
      begin match parse p (B.as_seq h b) with
      | None -> True
      | Some (_, consumed) -> consumed <> B.length b
      end
    | Some x -> parse p (B.as_seq h b) == Some (x, B.length b)
  ))
= match parse p (B.as_seq h b) with
  | Some (x, len) ->
    if len = I32.v sz
    then Some x
    else None
  | _ -> None

let exactly_parse_from_slice_intro'
  (#k: parser_kind)
  (#t: Type0)
  (p: parser k t)
  (h: HS.mem)
  (b: buffer8)
  (sz: I32.t)
  (x: t)
  (consumed: nat)
  (u: unit {
    is_slice h b sz /\
    parse_from_slice p h b sz == Some (x, consumed)
  })
: Lemma
  (ensures (
    is_slice h b sz /\
    consumed <= I32.v sz /\
    exactly_parse_from_slice p h (gsub b 0ul (U32.uint_to_t consumed)) (I32.int_to_t consumed) == Some x
  ))
= assert (no_lookahead_weak_on p (B.as_seq h b) (B.as_seq h (gsub b 0ul (U32.uint_to_t consumed))))

let exactly_parse_from_slice_intro
  (#k: parser_kind)
  (#t: Type0)
  (p: parser k t)
  (h: HS.mem)
  (b: buffer8)
  (sz: I32.t)
: Lemma
  (requires (
    is_slice h b sz /\
    Some? (parse_from_slice p h b sz)
  ))
  (ensures (
    let (Some (x, consumed)) = parse_from_slice p h b sz in
    consumed <= I32.v sz /\
    exactly_parse_from_slice p h (gsub b 0ul (U32.uint_to_t consumed)) (I32.int_to_t consumed) == Some x
  ))
//  [SMTPat (parse_from_slice p h b sz)]
= let (Some (x, consumed)) = parse_from_slice p h b sz in
  exactly_parse_from_slice_intro' p h b sz x consumed ()

(* A validator, if succeeds, returns the remaining length; otherwise returns a negative number. *)

let validator32_postcond
  (#k: parser_kind)
  (#t: Type0)
  (p: parser k t)
  (input: buffer8)
  (sz: I32.t)
  (h: HS.mem)
  (res: Int32.t)
  (h' : HS.mem)
: GTot Type0
= is_slice h input sz /\
  M.modifies M.loc_none h h' /\ (
    let pv = parse_from_slice p h input sz in
    if I32.v res >= 0
    then
      Some? pv /\ (
        let Some (_, consumed) = pv in
        I32.v res == I32.v sz - consumed
      )
    else
      None? pv
  )

inline_for_extraction
let validator32
  (#k: parser_kind)
  (#t: Type0)
  (p: parser k t)
: Tot Type0
= (input: buffer8) ->
  (sz: I32.t) ->
  HST.Stack I32.t
  (requires (fun h ->
    is_slice h input sz
  ))
  (ensures (fun h res h' ->
    validator32_postcond p input sz h res h'
  ))

inline_for_extraction
let validate32
  (#k: parser_kind)
  (#t: Type0)
  (#p: parser k t)
  (v: validator32 p)
  (input: buffer8)
  (sz: I32.t)
: HST.Stack bool
  (requires (fun h ->
    is_slice h input sz
  ))
  (ensures (fun h res h' ->
    is_slice h input sz /\
    M.modifies M.loc_none h h' /\ (
    let pv = parse_from_slice p h input sz in
    res == Some? pv
 )))
= let res = v input sz in
  not (res `I32.lt` 0l)

inline_for_extraction
let parser32
  (#k: parser_kind)
  (#t: Type0)
  (p: parser k t)
: Tot Type0
= (input: buffer8) ->
  HST.Stack t
  (requires (fun h ->
    B.live h input /\
    Some? (parse p (B.as_seq h input))
  ))
  (ensures (fun h res h' ->
    M.modifies M.loc_none h h' /\
    B.live h' input /\ (
    let ps = parse p (B.as_seq h input) in
    let (Some (res', _)) = ps in
    res == res'
  )))

inline_for_extraction
let validator_nochk32
  (#k: parser_kind)
  (#t: Type0)
  (p: parser k t)
: Tot Type0
= (input: buffer8) ->
  HST.Stack U32.t
  (requires (fun h ->
    B.live h input /\
    Some? (parse p (B.as_seq h input))
  ))
  (ensures (fun h res h' ->
    M.modifies M.loc_none h h' /\
    B.live h' input /\
    U32.v res <= B.length input /\ (
    let (Some (x, res')) = parse p (B.as_seq h input) in
    U32.v res == res'
  )))

inline_for_extraction
let accessor
  (#k1: parser_kind)
  (#t1: Type)
  (p1: parser k1 t1)
  (#k2: parser_kind)
  (#t2: Type)
  (p2: parser k2 t2)
  (rel: (t1 -> t2 -> GTot Type0))
: Tot Type
= (input: buffer8) ->
  HST.Stack buffer8
  (requires (fun h ->
    B.live h input /\
    Some? (parse p1 (B.as_seq h input))
  ))
  (ensures (fun h res h' ->
    M.modifies (M.loc_none) h h' /\
    B.live h' input /\
    B.includes input res /\ (
    let Some (x1, _) = parse p1 (B.as_seq h input) in
    let ps2 = parse p2 (B.as_seq h res) in
    Some? ps2 /\ (
    let Some (x2, _) = ps2 in
    rel x1 x2
  ))))

inline_for_extraction
let read_from_buffer
  (#k1: parser_kind)
  (#t1: Type)
  (#p1: parser k1 t1)
  (#k2: parser_kind)
  (#t2: Type)
  (#p2: parser k2 t2)
  (#rel: (t1 -> t2 -> GTot Type0))
  (a12: accessor p1 p2 rel)
  (p2' : parser32 p2)
  (input: buffer8)
: HST.Stack t2
  (requires (fun h ->
    B.live h input /\
    Some? (parse p1 (B.as_seq h input))
  ))
  (ensures (fun h y h' ->
    M.modifies M.loc_none h h' /\ (
    let (Some (x, _)) = parse p1 (B.as_seq h input) in
    rel x y
  )))
= p2' (a12 input)

let exactly_contains_valid_data
  (#k: parser_kind)
  (#t: Type)
  (h: HS.mem)
  (p: parser k t)
  (b: buffer8)
  (lo: U32.t)
  (x: t)
  (hi: U32.t)
: GTot Type0
= B.live h b /\
  U32.v lo <= U32.v hi /\
  U32.v hi <= B.length b /\
  parse p (B.as_seq h (B.gsub b lo (U32.sub hi lo))) == Some (x, U32.v hi - U32.v lo)

let exactly_contains_valid_data_injective
  (#k: parser_kind)
  (#t: Type)
  (h: HS.mem)
  (p: parser k t)
  (b: buffer8)
  (lo: U32.t)
  (x1: t)
  (hi: U32.t)
  (x2: t)
: Lemma
  (requires (
    exactly_contains_valid_data h p b lo x1 hi /\
    exactly_contains_valid_data h p b lo x2 hi
  ))
  (ensures (
    x1 == x2
  ))
  [SMTPat (exactly_contains_valid_data h p b lo x1 hi);
   SMTPat (exactly_contains_valid_data h p b lo x2 hi);]
= ()

let exactly_contains_valid_data_injective_strong'
  (#k: parser_kind)
  (#t: Type)
  (h: HS.mem)
  (p: parser k t)
  (b: buffer8)
  (lo: U32.t)
  (x1: t)
  (hi1: U32.t)
  (x2: t)
  (hi2: U32.t)
: Lemma
  (requires (
    exactly_contains_valid_data h p b lo x1 hi1 /\
    exactly_contains_valid_data h p b lo x2 hi2 /\
    k.parser_kind_subkind == Some ParserStrong /\
    U32.v hi1 <= U32.v hi2
  ))
  (ensures (
    x1 == x2 /\ hi1 == hi2
  ))
= assert (no_lookahead_on p (B.as_seq h (B.gsub b lo (U32.sub hi1 lo))) (B.as_seq h (B.gsub b lo (U32.sub hi2 lo))));
  assert (injective_precond p (B.as_seq h (B.gsub b lo (U32.sub hi2 lo))) (B.as_seq h (B.gsub b lo (U32.sub hi1 lo)))) 

let exactly_contains_valid_data_injective_strong
  (#k: parser_kind)
  (#t: Type)
  (h: HS.mem)
  (p: parser k t)
  (b: buffer8)
  (lo: U32.t)
  (x1: t)
  (hi1: U32.t)
  (x2: t)
  (hi2: U32.t)
: Lemma
  (requires (
    exactly_contains_valid_data h p b lo x1 hi1 /\
    exactly_contains_valid_data h p b lo x2 hi2 /\
    k.parser_kind_subkind == Some ParserStrong
  ))
  (ensures (
    x1 == x2 /\ hi1 == hi2
  ))
  [SMTPat (exactly_contains_valid_data h p b lo x1 hi1);
   SMTPat (exactly_contains_valid_data h p b lo x2 hi2);]
= if U32.v hi1 <= U32.v hi2
  then exactly_contains_valid_data_injective_strong' h p b lo x1 hi1 x2 hi2
  else exactly_contains_valid_data_injective_strong' h p b lo x2 hi2 x1 hi1

let exactly_contains_valid_data_invariant
  (#k: parser_kind)
  (#t: Type)
  (l: M.loc)
  (h h' : HS.mem)
  (p: parser k t)
  (b: buffer8)
  (lo: U32.t)
  (x: t)
  (hi: U32.t)
: Lemma
  (requires (
    M.modifies l h h' /\
    exactly_contains_valid_data h p b lo x hi /\
    M.loc_disjoint l (M.loc_buffer (B.gsub b lo (U32.sub hi lo)))
  ))
  (ensures (
    exactly_contains_valid_data h' p b lo x hi
  ))
  [SMTPat (M.modifies l h h'); SMTPat (exactly_contains_valid_data h p b lo x hi)]
= ()
