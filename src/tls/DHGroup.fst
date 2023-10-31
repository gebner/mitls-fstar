﻿module DHGroup

open FStar.Bytes
open FStar.Error

open TLSError
open Mem
module Parse = Parse

module LP = LowParse.SLow

val make_ffdhe: (p:string{length (bytes_of_hex p) < 65536}) -> s:string{length (bytes_of_hex s) < 65536} -> Tot params
let make_ffdhe p q =
  {
    dh_p = bytes_of_hex p;
    dh_g = abyte 2z;
    dh_q = Some (bytes_of_hex q);
    safe_prime = true
  }

let ffdhe2048 =
  let p = "ffffffffffffffffadf85458a2bb4a9aafdc5620273d3cf1d8b9c583ce2d3695a9e13641146433fbcc939dce249b3ef97d2fe363630c75d8f681b202aec4617ad3df1ed5d5fd65612433f51f5f066ed0856365553ded1af3b557135e7f57c935984f0c70e0e68b77e2a689daf3efe8721df158a136ade73530acca4f483a797abc0ab182b324fb61d108a94bb2c8e3fbb96adab760d7f4681d4f42a3de394df4ae56ede76372bb190b07a7c8ee0a6d709e02fce1cdf7e2ecc03404cd28342f619172fe9ce98583ff8e4f1232eef28183c3fe3b1b4c6fad733bb5fcbc2ec22005c58ef1837d1683b2c6f34a26c1b2effa886b423861285c97ffffffffffffffff" in
  let q = "7fffffffffffffffd6fc2a2c515da54d57ee2b10139e9e78ec5ce2c1e7169b4ad4f09b208a3219fde649cee7124d9f7cbe97f1b1b1863aec7b40d901576230bd69ef8f6aeafeb2b09219fa8faf83376842b1b2aa9ef68d79daab89af3fabe49acc278638707345bbf15344ed79f7f4390ef8ac509b56f39a98566527a41d3cbd5e0558c159927db0e88454a5d96471fddcb56d5bb06bfa340ea7a151ef1ca6fa572b76f3b1b95d8c8583d3e4770536b84f017e70e6fbf176601a0266941a17b0c8b97f4e74c2c1ffc7278919777940c1e1ff1d8da637d6b99ddafe5e17611002e2c778c1be8b41d96379a51360d977fd4435a11c30942e4bffffffffffffffff" in
  assume (length (bytes_of_hex p) < 65536);
  assume (length (bytes_of_hex q) < 65536);
  make_ffdhe p q

let ffdhe3072 =
  let p = "ffffffffffffffffadf85458a2bb4a9aafdc5620273d3cf1d8b9c583ce2d3695a9e13641146433fbcc939dce249b3ef97d2fe363630c75d8f681b202aec4617ad3df1ed5d5fd65612433f51f5f066ed0856365553ded1af3b557135e7f57c935984f0c70e0e68b77e2a689daf3efe8721df158a136ade73530acca4f483a797abc0ab182b324fb61d108a94bb2c8e3fbb96adab760d7f4681d4f42a3de394df4ae56ede76372bb190b07a7c8ee0a6d709e02fce1cdf7e2ecc03404cd28342f619172fe9ce98583ff8e4f1232eef28183c3fe3b1b4c6fad733bb5fcbc2ec22005c58ef1837d1683b2c6f34a26c1b2effa886b4238611fcfdcde355b3b6519035bbc34f4def99c023861b46fc9d6e6c9077ad91d2691f7f7ee598cb0fac186d91caefe130985139270b4130c93bc437944f4fd4452e2d74dd364f2e21e71f54bff5cae82ab9c9df69ee86d2bc522363a0dabc521979b0deada1dbf9a42d5c4484e0abcd06bfa53ddef3c1b20ee3fd59d7c25e41d2b66c62e37ffffffffffffffff" in
  let q = "7fffffffffffffffd6fc2a2c515da54d57ee2b10139e9e78ec5ce2c1e7169b4ad4f09b208a3219fde649cee7124d9f7cbe97f1b1b1863aec7b40d901576230bd69ef8f6aeafeb2b09219fa8faf83376842b1b2aa9ef68d79daab89af3fabe49acc278638707345bbf15344ed79f7f4390ef8ac509b56f39a98566527a41d3cbd5e0558c159927db0e88454a5d96471fddcb56d5bb06bfa340ea7a151ef1ca6fa572b76f3b1b95d8c8583d3e4770536b84f017e70e6fbf176601a0266941a17b0c8b97f4e74c2c1ffc7278919777940c1e1ff1d8da637d6b99ddafe5e17611002e2c778c1be8b41d96379a51360d977fd4435a11c308fe7ee6f1aad9db28c81adde1a7a6f7cce011c30da37e4eb736483bd6c8e9348fbfbf72cc6587d60c36c8e577f0984c289c9385a098649de21bca27a7ea229716ba6e9b279710f38faa5ffae574155ce4efb4f743695e2911b1d06d5e290cbcd86f56d0edfcd216ae22427055e6835fd29eef79e0d90771feacebe12f20e95b363171bffffffffffffffff" in
  assume (length (bytes_of_hex p) < 65536);
  assume (length (bytes_of_hex q) < 65536);
  make_ffdhe p q

let ffdhe4096 =
  let p = "ffffffffffffffffadf85458a2bb4a9aafdc5620273d3cf1d8b9c583ce2d3695a9e13641146433fbcc939dce249b3ef97d2fe363630c75d8f681b202aec4617ad3df1ed5d5fd65612433f51f5f066ed0856365553ded1af3b557135e7f57c935984f0c70e0e68b77e2a689daf3efe8721df158a136ade73530acca4f483a797abc0ab182b324fb61d108a94bb2c8e3fbb96adab760d7f4681d4f42a3de394df4ae56ede76372bb190b07a7c8ee0a6d709e02fce1cdf7e2ecc03404cd28342f619172fe9ce98583ff8e4f1232eef28183c3fe3b1b4c6fad733bb5fcbc2ec22005c58ef1837d1683b2c6f34a26c1b2effa886b4238611fcfdcde355b3b6519035bbc34f4def99c023861b46fc9d6e6c9077ad91d2691f7f7ee598cb0fac186d91caefe130985139270b4130c93bc437944f4fd4452e2d74dd364f2e21e71f54bff5cae82ab9c9df69ee86d2bc522363a0dabc521979b0deada1dbf9a42d5c4484e0abcd06bfa53ddef3c1b20ee3fd59d7c25e41d2b669e1ef16e6f52c3164df4fb7930e9e4e58857b6ac7d5f42d69f6d187763cf1d5503400487f55ba57e31cc7a7135c886efb4318aed6a1e012d9e6832a907600a918130c46dc778f971ad0038092999a333cb8b7a1a1db93d7140003c2a4ecea9f98d0acc0a8291cdcec97dcf8ec9b55a7f88a46b4db5a851f44182e1c68a007e5e655f6affffffffffffffff" in
  let q = "7fffffffffffffffd6fc2a2c515da54d57ee2b10139e9e78ec5ce2c1e7169b4ad4f09b208a3219fde649cee7124d9f7cbe97f1b1b1863aec7b40d901576230bd69ef8f6aeafeb2b09219fa8faf83376842b1b2aa9ef68d79daab89af3fabe49acc278638707345bbf15344ed79f7f4390ef8ac509b56f39a98566527a41d3cbd5e0558c159927db0e88454a5d96471fddcb56d5bb06bfa340ea7a151ef1ca6fa572b76f3b1b95d8c8583d3e4770536b84f017e70e6fbf176601a0266941a17b0c8b97f4e74c2c1ffc7278919777940c1e1ff1d8da637d6b99ddafe5e17611002e2c778c1be8b41d96379a51360d977fd4435a11c308fe7ee6f1aad9db28c81adde1a7a6f7cce011c30da37e4eb736483bd6c8e9348fbfbf72cc6587d60c36c8e577f0984c289c9385a098649de21bca27a7ea229716ba6e9b279710f38faa5ffae574155ce4efb4f743695e2911b1d06d5e290cbcd86f56d0edfcd216ae22427055e6835fd29eef79e0d90771feacebe12f20e95b34f0f78b737a9618b26fa7dbc9874f272c42bdb563eafa16b4fb68c3bb1e78eaa81a00243faadd2bf18e63d389ae44377da18c576b50f0096cf34195483b00548c0986236e3bc7cb8d6801c0494ccd199e5c5bd0d0edc9eb8a0001e15276754fcc68566054148e6e764bee7c764daad3fc45235a6dad428fa20c170e345003f2f32afb57fffffffffffffff" in
  assume (length (bytes_of_hex p) < 65536);
  assume (length (bytes_of_hex q) < 65536);
  make_ffdhe p q

let ffdhe6144 =
  let p = "ffffffffffffffffadf85458a2bb4a9aafdc5620273d3cf1d8b9c583ce2d3695a9e13641146433fbcc939dce249b3ef97d2fe363630c75d8f681b202aec4617ad3df1ed5d5fd65612433f51f5f066ed0856365553ded1af3b557135e7f57c935984f0c70e0e68b77e2a689daf3efe8721df158a136ade73530acca4f483a797abc0ab182b324fb61d108a94bb2c8e3fbb96adab760d7f4681d4f42a3de394df4ae56ede76372bb190b07a7c8ee0a6d709e02fce1cdf7e2ecc03404cd28342f619172fe9ce98583ff8e4f1232eef28183c3fe3b1b4c6fad733bb5fcbc2ec22005c58ef1837d1683b2c6f34a26c1b2effa886b4238611fcfdcde355b3b6519035bbc34f4def99c023861b46fc9d6e6c9077ad91d2691f7f7ee598cb0fac186d91caefe130985139270b4130c93bc437944f4fd4452e2d74dd364f2e21e71f54bff5cae82ab9c9df69ee86d2bc522363a0dabc521979b0deada1dbf9a42d5c4484e0abcd06bfa53ddef3c1b20ee3fd59d7c25e41d2b669e1ef16e6f52c3164df4fb7930e9e4e58857b6ac7d5f42d69f6d187763cf1d5503400487f55ba57e31cc7a7135c886efb4318aed6a1e012d9e6832a907600a918130c46dc778f971ad0038092999a333cb8b7a1a1db93d7140003c2a4ecea9f98d0acc0a8291cdcec97dcf8ec9b55a7f88a46b4db5a851f44182e1c68a007e5e0dd9020bfd64b645036c7a4e677d2c38532a3a23ba4442caf53ea63bb454329b7624c8917bdd64b1c0fd4cb38e8c334c701c3acdad0657fccfec719b1f5c3e4e46041f388147fb4cfdb477a52471f7a9a96910b855322edb6340d8a00ef092350511e30abec1fff9e3a26e7fb29f8c183023c3587e38da0077d9b4763e4e4b94b2bbc194c6651e77caf992eeaac0232a281bf6b3a739c1226116820ae8db5847a67cbef9c9091b462d538cd72b03746ae77f5e62292c311562a846505dc82db854338ae49f5235c95b91178ccf2dd5cacef403ec9d1810c6272b045b3b71f9dc6b80d63fdd4a8e9adb1e6962a69526d43161c1a41d570d7938dad4a40e329cd0e40e65ffffffffffffffff" in
  let q = "7fffffffffffffffd6fc2a2c515da54d57ee2b10139e9e78ec5ce2c1e7169b4ad4f09b208a3219fde649cee7124d9f7cbe97f1b1b1863aec7b40d901576230bd69ef8f6aeafeb2b09219fa8faf83376842b1b2aa9ef68d79daab89af3fabe49acc278638707345bbf15344ed79f7f4390ef8ac509b56f39a98566527a41d3cbd5e0558c159927db0e88454a5d96471fddcb56d5bb06bfa340ea7a151ef1ca6fa572b76f3b1b95d8c8583d3e4770536b84f017e70e6fbf176601a0266941a17b0c8b97f4e74c2c1ffc7278919777940c1e1ff1d8da637d6b99ddafe5e17611002e2c778c1be8b41d96379a51360d977fd4435a11c308fe7ee6f1aad9db28c81adde1a7a6f7cce011c30da37e4eb736483bd6c8e9348fbfbf72cc6587d60c36c8e577f0984c289c9385a098649de21bca27a7ea229716ba6e9b279710f38faa5ffae574155ce4efb4f743695e2911b1d06d5e290cbcd86f56d0edfcd216ae22427055e6835fd29eef79e0d90771feacebe12f20e95b34f0f78b737a9618b26fa7dbc9874f272c42bdb563eafa16b4fb68c3bb1e78eaa81a00243faadd2bf18e63d389ae44377da18c576b50f0096cf34195483b00548c0986236e3bc7cb8d6801c0494ccd199e5c5bd0d0edc9eb8a0001e15276754fcc68566054148e6e764bee7c764daad3fc45235a6dad428fa20c170e345003f2f06ec8105feb25b2281b63d2733be961c29951d11dd2221657a9f531dda2a194dbb126448bdeeb258e07ea659c74619a6380e1d66d6832bfe67f638cd8fae1f2723020f9c40a3fda67eda3bd29238fbd4d4b4885c2a99176db1a06c500778491a8288f1855f60fffcf1d1373fd94fc60c1811e1ac3f1c6d003becda3b1f2725ca595de0ca63328f3be57cc97755601195140dfb59d39ce091308b4105746dac23d33e5f7ce4848da316a9c66b9581ba3573bfaf311496188ab15423282ee416dc2a19c5724fa91ae4adc88bc66796eae5677a01f64e8c08631395822d9db8fcee35c06b1feea5474d6d8f34b1534a936a18b0e0d20eab86bc9c6d6a5207194e68720732ffffffffffffffff" in
  assume (length (bytes_of_hex p) < 65536);
  assume (length (bytes_of_hex q) < 65536);
  make_ffdhe p q

let ffdhe8192 =
  let p = "ffffffffffffffffadf85458a2bb4a9aafdc5620273d3cf1d8b9c583ce2d3695a9e13641146433fbcc939dce249b3ef97d2fe363630c75d8f681b202aec4617ad3df1ed5d5fd65612433f51f5f066ed0856365553ded1af3b557135e7f57c935984f0c70e0e68b77e2a689daf3efe8721df158a136ade73530acca4f483a797abc0ab182b324fb61d108a94bb2c8e3fbb96adab760d7f4681d4f42a3de394df4ae56ede76372bb190b07a7c8ee0a6d709e02fce1cdf7e2ecc03404cd28342f619172fe9ce98583ff8e4f1232eef28183c3fe3b1b4c6fad733bb5fcbc2ec22005c58ef1837d1683b2c6f34a26c1b2effa886b4238611fcfdcde355b3b6519035bbc34f4def99c023861b46fc9d6e6c9077ad91d2691f7f7ee598cb0fac186d91caefe130985139270b4130c93bc437944f4fd4452e2d74dd364f2e21e71f54bff5cae82ab9c9df69ee86d2bc522363a0dabc521979b0deada1dbf9a42d5c4484e0abcd06bfa53ddef3c1b20ee3fd59d7c25e41d2b669e1ef16e6f52c3164df4fb7930e9e4e58857b6ac7d5f42d69f6d187763cf1d5503400487f55ba57e31cc7a7135c886efb4318aed6a1e012d9e6832a907600a918130c46dc778f971ad0038092999a333cb8b7a1a1db93d7140003c2a4ecea9f98d0acc0a8291cdcec97dcf8ec9b55a7f88a46b4db5a851f44182e1c68a007e5e0dd9020bfd64b645036c7a4e677d2c38532a3a23ba4442caf53ea63bb454329b7624c8917bdd64b1c0fd4cb38e8c334c701c3acdad0657fccfec719b1f5c3e4e46041f388147fb4cfdb477a52471f7a9a96910b855322edb6340d8a00ef092350511e30abec1fff9e3a26e7fb29f8c183023c3587e38da0077d9b4763e4e4b94b2bbc194c6651e77caf992eeaac0232a281bf6b3a739c1226116820ae8db5847a67cbef9c9091b462d538cd72b03746ae77f5e62292c311562a846505dc82db854338ae49f5235c95b91178ccf2dd5cacef403ec9d1810c6272b045b3b71f9dc6b80d63fdd4a8e9adb1e6962a69526d43161c1a41d570d7938dad4a40e329ccff46aaa36ad004cf600c8381e425a31d951ae64fdb23fcec9509d43687feb69edd1cc5e0b8cc3bdf64b10ef86b63142a3ab8829555b2f747c932665cb2c0f1cc01bd70229388839d2af05e454504ac78b7582822846c0ba35c35f5c59160cc046fd8251541fc68c9c86b022bb7099876a460e7451a8a93109703fee1c217e6c3826e52c51aa691e0e423cfc99e9e31650c1217b624816cdad9a95f9d5b8019488d9c0a0a1fe3075a577e23183f81d4a3f2fa4571efc8ce0ba8a4fe8b6855dfe72b0a66eded2fbabfbe58a30fafabe1c5d71a87e2f741ef8c1fe86fea6bbfde530677f0d97d11d49f7a8443d0822e506a9f4614e011e2a94838ff88cd68c8bb7c5c6424cffffffffffffffff" in
  let q = "7fffffffffffffffd6fc2a2c515da54d57ee2b10139e9e78ec5ce2c1e7169b4ad4f09b208a3219fde649cee7124d9f7cbe97f1b1b1863aec7b40d901576230bd69ef8f6aeafeb2b09219fa8faf83376842b1b2aa9ef68d79daab89af3fabe49acc278638707345bbf15344ed79f7f4390ef8ac509b56f39a98566527a41d3cbd5e0558c159927db0e88454a5d96471fddcb56d5bb06bfa340ea7a151ef1ca6fa572b76f3b1b95d8c8583d3e4770536b84f017e70e6fbf176601a0266941a17b0c8b97f4e74c2c1ffc7278919777940c1e1ff1d8da637d6b99ddafe5e17611002e2c778c1be8b41d96379a51360d977fd4435a11c308fe7ee6f1aad9db28c81adde1a7a6f7cce011c30da37e4eb736483bd6c8e9348fbfbf72cc6587d60c36c8e577f0984c289c9385a098649de21bca27a7ea229716ba6e9b279710f38faa5ffae574155ce4efb4f743695e2911b1d06d5e290cbcd86f56d0edfcd216ae22427055e6835fd29eef79e0d90771feacebe12f20e95b34f0f78b737a9618b26fa7dbc9874f272c42bdb563eafa16b4fb68c3bb1e78eaa81a00243faadd2bf18e63d389ae44377da18c576b50f0096cf34195483b00548c0986236e3bc7cb8d6801c0494ccd199e5c5bd0d0edc9eb8a0001e15276754fcc68566054148e6e764bee7c764daad3fc45235a6dad428fa20c170e345003f2f06ec8105feb25b2281b63d2733be961c29951d11dd2221657a9f531dda2a194dbb126448bdeeb258e07ea659c74619a6380e1d66d6832bfe67f638cd8fae1f2723020f9c40a3fda67eda3bd29238fbd4d4b4885c2a99176db1a06c500778491a8288f1855f60fffcf1d1373fd94fc60c1811e1ac3f1c6d003becda3b1f2725ca595de0ca63328f3be57cc97755601195140dfb59d39ce091308b4105746dac23d33e5f7ce4848da316a9c66b9581ba3573bfaf311496188ab15423282ee416dc2a19c5724fa91ae4adc88bc66796eae5677a01f64e8c08631395822d9db8fcee35c06b1feea5474d6d8f34b1534a936a18b0e0d20eab86bc9c6d6a5207194e67fa35551b5680267b00641c0f212d18eca8d7327ed91fe764a84ea1b43ff5b4f6e8e62f05c661defb258877c35b18a151d5c414aaad97ba3e499332e596078e600deb81149c441ce95782f22a282563c5bac1411423605d1ae1afae2c8b0660237ec128aa0fe3464e4358115db84cc3b523073a28d4549884b81ff70e10bf361c13729628d5348f07211e7e4cf4f18b286090bdb1240b66d6cd4afceadc00ca446ce05050ff183ad2bbf118c1fc0ea51f97d22b8f7e46705d4527f45b42aeff395853376f697dd5fdf2c5187d7d5f0e2eb8d43f17ba0f7c60ff437f535dfef29833bf86cbe88ea4fbd4221e8411728354fa30a7008f154a41c7fc466b4645dbe2e321267fffffffffffffff" in
  assume (length (bytes_of_hex p) < 65536);
  assume (length (bytes_of_hex q) < 65536);
  make_ffdhe p q

#reset-options "--z3rlimit 20"
let params_of_group = function
  | Named FFDHE2048 -> ffdhe2048
  | Named FFDHE3072 -> ffdhe3072
  | Named FFDHE4096 -> ffdhe4096
  | Named FFDHE6144 -> ffdhe6144
  | Named FFDHE8192 -> ffdhe8192
  | Explicit ps     -> ps
#reset-options

type _keyshare (g:group) = share g * EverCrypt.dh_state
let keyshare (g:group) = assume false; _keyshare g

let pubshare #g k = fst k

module LB = LowStar.Buffer

#reset-options "--admit_smt_queries true"
let keygen g =
  push_frame ();
  let p = params_of_group g in
  let q = match p.dh_q with
    |Some q -> q | None -> empty_bytes in
  let lp = B.len p.dh_p in
  let pb = LB.alloca 0uy lp in
  let lq = B.len q in
  let qb = LB.alloca 0uy lq in
  let lg = B.len p.dh_g in
  let gb = LB.alloca 0uy lg in  
  B.store_bytes p.dh_p pb;
  B.store_bytes q qb;
  B.store_bytes p.dh_g gb;
  let st = EverCrypt.dh_load_group pb lp gb lg qb lq in  
  let pub = LB.alloca 0uy lp in
  let lpub = EverCrypt.dh_keygen st pub in
  let s = B.of_buffer lpub pub in  
  pop_frame ();
  (s, st)

let dh_initiator #g x gy =
  push_frame ();
  let (_, st) = x in
  let p = params_of_group g in
  let rb = LB.alloca 0uy (B.len p.dh_p) in
  let ly = B.len gy in
  let yb = LB.alloca 0uy ly in
  B.store_bytes gy yb;
  let lr = EverCrypt.dh_compute st yb ly rb in
  pop_frame ();
  B.of_buffer lr rb

#reset-options


private
let dhparam_parser_kind =
  let vlpk = LP.parse_bounded_vlbytes_kind 0 65535 in
  LP.and_then_kind vlpk
    (LP.and_then_kind vlpk
      (LP.and_then_kind vlpk vlpk))

private type vlb16 = b:bytes{length b < 65536}
private type dhparams = vlb16 * vlb16 * vlb16 * vlb16


private 
inline_for_extraction
let synth_vlb16 (x:LP.parse_bounded_vlbytes_t 0 65535)
  : Tot vlb16
  = assert (length x < 65536); 
    x

private 
inline_for_extraction
let unsynth_vlb16 (x:vlb16)
  : Tot (LP.parse_bounded_vlbytes_t 0 65535) 
  = x

private 
let vlb16_parser: LP.parser (LP.parse_bounded_vlbytes_kind 0 65535) vlb16 =
  let p = LP.parse_bounded_vlbytes 0 65535 in
  LP.parse_synth p synth_vlb16

private 
inline_for_extraction
let vlb16_parser32: LP.parser32 vlb16_parser =
  let p32 = LP.parse32_bounded_vlbytes 0 0ul 65535 65535ul in
  LP.parse32_synth _ synth_vlb16 (fun x -> synth_vlb16 x) p32 ()

private
let vlb16_serializer: LP.serializer vlb16_parser =
  let vls = LP.serialize_bounded_vlbytes 0 65535 in
  LP.serialize_synth _ synth_vlb16 vls unsynth_vlb16 ()

private
inline_for_extraction
let vlb16_serializer32: LP.serializer32 vlb16_serializer =
  let vls32 = LP.serialize32_bounded_vlbytes 0 65535 in
  LP.serialize32_synth _ synth_vlb16 _ vls32 unsynth_vlb16 (fun x -> unsynth_vlb16 x) ()
  
 
private
inline_for_extraction
let synth_dhparams ((a:vlb16), ((b:vlb16), ((c:vlb16), (d:vlb16)))): dhparams = (a, b, c, d)

private
inline_for_extraction
let unsynth_dhparams (x:dhparams): Tot (vlb16 * (vlb16 * (vlb16 * vlb16))) = 
  let a, b, c, d = x in
  (a, (b, (c, d)))

private
let dhparam_parser: LP.parser dhparam_parser_kind dhparams =
  let vlp = vlb16_parser in
  LP.parse_synth
    (LP.nondep_then vlp
      (LP.nondep_then vlp
        (LP.nondep_then vlp vlp)))
    synth_dhparams

private 
inline_for_extraction
let dhparam_parser32: LP.parser32 dhparam_parser =
  let vlp32 = vlb16_parser32 in
  LP.parse32_synth
    _ 
    synth_dhparams
    (fun x -> synth_dhparams x)
    (LP.parse32_nondep_then vlp32    
      (LP.parse32_nondep_then vlp32
        (LP.parse32_nondep_then vlp32 vlp32)))
    ()

private
let dhparam_serializer: LP.serializer dhparam_parser =
  let vls = vlb16_serializer in
  LP.serialize_synth
    _ 
    synth_dhparams
    (LP.serialize_nondep_then vls
      (LP.serialize_nondep_then vls
        (LP.serialize_nondep_then vls vls)))
    unsynth_dhparams
    ()

private
inline_for_extraction
let dhparam_serializer32: LP.serializer32 dhparam_serializer =
  let vls32 = vlb16_serializer32 in
  LP.serialize32_synth
    _
    synth_dhparams
    _
    (LP.serialize32_nondep_then vls32
      (LP.serialize32_nondep_then vls32
        (LP.serialize32_nondep_then vls32 vls32)
      )
    )
    unsynth_dhparams
    (fun x -> unsynth_dhparams x)
    ()
  
let serialize #g dh_Y =
  let x:params = params_of_group g in
  assert (length x.dh_p < 65536);
  assert (length x.dh_g < 65536);
  let r = dhparam_serializer32 (x.dh_p, x.dh_g, dh_Y, Bytes.empty_bytes) in
  r

#reset-options "--using_facts_from '* -LowParse'"
let serialize_public #g s l =
  lemma_repr_bytes_values l;
  let pad_len = l - length s in
  let (pad:lbytes pad_len) = Bytes.create_ pad_len 0z in
  Bytes.append pad s

let parse_partial (bs:bytes) =
  match dhparam_parser32 bs with 
  | Some ((p, g, gy, rem), _) ->
      // REMARK: In TLS 1.3 we MUST have length gy = length p
      if 0 < length gy && length gy <= length p then (
        let dhp = { dh_p = p; dh_g = g; dh_q = None; safe_prime = false } in
        Correct ((| Explicit dhp, gy |), rem)
      ) 
      else
        fatal Decode_error (perror __SOURCE_FILE__ __LINE__ "")
  | _ -> fatal Decode_error (perror __SOURCE_FILE__ __LINE__ "")
