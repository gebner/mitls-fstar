module MiTLS.Old.KeySchedule
open MiTLS

open FStar.Heap
open FStar.HyperStack
open FStar.HyperStack.ST
open FStar.Seq
open FStar.Bytes
open FStar.Error
//open FStar.Integers 

open MiTLS.TLSError
open MiTLS.TLSConstants
open MiTLS.Extensions
open MiTLS.TLSInfo
open MiTLS.Range
open MiTLS.StatefulLHAE
open MiTLS.HKDF
open MiTLS.PSK

module MDM = FStar.Monotonic.DependentMap
module HS = FStar.HyperStack
module ST = FStar.HyperStack.ST
module H = MiTLS.Hashing.Spec

module HMAC_UFCMA = MiTLS.Old.HMAC.UFCMA

#set-options "--admit_smt_queries true"

let psk (i:esId) =
  b:bytes{len b = Hacl.Hash.Definitions.hash_len (esId_hash i)}

let es (i:esId) = H.tag (esId_hash i)

let hs (i:hsId) = H.tag (hsId_hash i)

let ams (i:asId) = H.tag (asId_hash i)

let rekey_secrets #li (i:expandId li) =
  H.tag (expandId_hash i) * H.tag (expandId_hash i)

let mk_binder (#rid) (pskid:psk_identifier) (t:ticket13)
  : ST ((i:binderId & bk:binderKey i) * (i:esId{~(NoPSK? i)} & es i))
  (requires fun h0 -> True)
  (ensures fun h0 _ h1 -> modifies_none h0 h1)
  =
  let i : esId = ResumptionPSK (Ticket.Ticket13?.rmsId t) in
  let pski = Some?.v (Ticket.ticket_pskinfo t) in
  let psk = Ticket.Ticket13?.rms t in
  let h = pski.early_hash in
  dbg ("Loaded pre-shared key "^(print_bytes pskid)^": "^(print_bytes psk));
  let es : es i = HKDF.extract #h (H.zeroHash h) psk in
  dbg ("Early secret: "^(print_bytes es));
  let ll, lb =
    if ApplicationPSK? i then ExtBinder, "ext binder"
    else ResBinder, "res binder" in
  let bId = Binder i ll in
  let bk = HKDF.derive_secret h es lb (H.emptyHash h) in
  dbg ("Binder key["^lb^"]: "^(print_bytes bk));
  let bk = finished_13 h bk in
  dbg ("Binder Finished key: "^(print_bytes bk));
  let bk : binderKey bId = HMAC_UFCMA.coerce (HMAC_UFCMA.HMAC_Binder bId) trivial rid bk in
  (| bId, bk|), (| i, es |)

let ks_client_13_ch ks (log:bytes): ST (exportKey * recordInstance)
  (requires fun h0 ->
    let kss = sel h0 (KS?.state ks) in
    C? kss /\ C_13_wait_SH? (C?.s kss))
  (ensures fun h0 r h1 ->
    let KS #rid st _ = ks in
    modifies_none h0 h1)
  =
  dbg ("ks_client_13_ch log="^(print_bytes log));
  let KS #rid st is_quic = ks in
  let C (C_13_wait_SH cr ((| i, es |) :: _) gs) = !st in

  let h = esId_hash i in
  let ae = esId_ae i in

  let li = LogInfo_CH0 ({
   li_ch0_cr = cr;
   li_ch0_ed_ae = ae;
   li_ch0_ed_hash = h;
   li_ch0_ed_psk = empty_bytes; }) in

  let log : hashed_log li = log in
  let expandId : expandId li = ExpandedSecret (EarlySecretID i) ClientEarlyTrafficSecret log in
  let ets = HKDF.derive_secret h es "c e traffic" log in
  dbg ("Client early traffic secret:     "^print_bytes ets);
  let expId : exportId li = EarlyExportID i log in
  let early_export : ems expId = HKDF.derive_secret h es "e exp master" log in
  dbg ("Early exporter master secret:    "^print_bytes early_export);
  let exporter0 = (| li, expId, early_export |) in

  // Expand all keys from the derived early secret
  let (ck, civ, pn) = keygen_13 h ets ae is_quic in
  dbg ("Client 0-RTT key:                "^print_bytes ck^", IV="^print_bytes civ);

  let id = ID13 (KeyID expandId) in
  let ckv: StreamAE.key id = ck in
  let civ: StreamAE.iv id  = civ in
  let rw = StAE.coerce HS.root id (ckv @| civ) in
  let r = StAE.genReader HS.root rw in
  let early_d = StAEInstance r rw (pn, pn) in
  exporter0, early_d

let ks_server_12_init_dh ks cr pv cs ems g =
  dbg "ks_server_12_init_dh";
  let KS #region st _ = ks in
  let S (S_Init sr) = !st in
  let CipherSuite kex sa ae = cs in
  let our_share = CommonDH.keygen g in
  let _ = print_share (CommonDH.ipubshare our_share) in
  let csr = cr @| sr in
  st := S (S_12_wait_CKE_DH csr (pv, cs, ems) (| g, our_share |));
  CommonDH.ipubshare our_share
  
let ks_server_13_init ks cr cs pskid g_gx =
  dbg ("ks_server_init");
  let KS #region st _ = ks in
  let S (S_Init sr) = !st in
  let CipherSuite13 ae h = cs in
  let esId, es, bk =
    match pskid with
    | Some id ->
      dbg ("Using negotiated PSK identity: "^(print_bytes id));
      let i, psk, h : esId * bytes * Hashing.Spec.alg =
        match Ticket.check_ticket false id with
        | Some (Ticket.Ticket13 cs li rmsId rms _ _ _ _) ->
          dbg ("Ticket RMS: "^(print_bytes rms));
          let i = ResumptionPSK #li rmsId in
          let CipherSuite13 _ h = cs in
          let nonce, _ = split id 12ul in
          let psk = HKDF.derive_secret h rms "resumption" nonce in
          (i, psk, h)
        | None ->
          let i, pski, psk = read_psk id in
          (i, psk, pski.early_hash)
        in
      dbg ("Pre-shared key: "^(print_bytes psk));
      let es: Hashing.Spec.tag h = HKDF.extract #h (H.zeroHash h) psk in
      let ll, lb =
        if ApplicationPSK? i then ExtBinder, "ext binder"
        else ResBinder, "res binder" in
      let bId: pre_binderId = Binder i ll in
      let bk = HKDF.derive_secret h es lb (H.emptyHash h) in
      dbg ("binder key:                      "^print_bytes bk);
      let bk = finished_13 h bk in
      dbg ("binder Finished key:             "^print_bytes bk);
      let bk : binderKey bId = HMAC_UFCMA.coerce (HMAC_UFCMA.HMAC_Binder bId) (fun _ -> True) region bk in
      i, es, Some (| bId, bk |)
    | None ->
      dbg "No PSK selected.";
      let esId = NoPSK h in
      let es : es esId = HKDF.extract #h (H.zeroHash h) (H.zeroHash h) in
      esId, es, None
    in
  dbg ("Computed early secret:           "^print_bytes es);
  let saltId = Salt (EarlySecretID esId) in
  let salt = HKDF.derive_secret h es "derived" (H.emptyHash h) in
  dbg ("Handshake salt:                  "^print_bytes salt);
  let (gy: option CommonDH.keyShareEntry), (hsId: pre_hsId), (hs: Hashing.Spec.tag h) =
    match g_gx with
    | Some (| g, gx |) ->
      let gy, gxy = CommonDH.dh_responder g gx in
      dbg ("DH shared secret: "^(print_bytes gxy));
      let hsId = HSID_DHE saltId g gx gy in
      let hs : hs hsId = HKDF.extract #h salt gxy in
      Some (CommonDH.Share g gy), hsId, hs
    | None ->
      let hsId = HSID_PSK saltId in
      let hs : hs hsId = HKDF.extract #h salt (H.zeroHash h) in
      None, hsId, hs
    in
  dbg ("Handshake secret:                "^print_bytes hs);
  st := S (S_13_wait_SH (ae, h) cr sr (| esId, es |) (| hsId, hs |));
  gy, bk

let ks_server_13_0rtt_key ks (log:bytes)
  : ST ((li:logInfo & i:exportId li & ems i) * recordInstance)
  (requires fun h0 ->
    let kss = sel h0 (KS?.state ks) in
    S? kss /\ S_13_wait_SH? (S?.s kss))
  (ensures fun h0 _ h1 -> modifies_none h0 h1)
  =
  dbg "ks_server_13_0rtt_key";
  let KS #region st is_quic = ks in
  let S (S_13_wait_SH (ae, h) cr sr (| esId, es |) _) = !st in

  let li = LogInfo_CH0 ({
    li_ch0_cr = cr;
    li_ch0_ed_ae = ae;
    li_ch0_ed_hash = h;
    li_ch0_ed_psk = empty_bytes;
  }) in
  let log : hashed_log li = log in
  let expandId : expandId li = ExpandedSecret (EarlySecretID esId) ClientEarlyTrafficSecret log in
  let ets = HKDF.derive_secret h es "c e traffic" log in
  dbg ("Client early traffic secret:     "^print_bytes ets);
  let expId : exportId li = EarlyExportID esId log in
  let early_export : ems expId = HKDF.derive_secret h es "e exp master" log in
  dbg ("Early exporter master secret:    "^print_bytes early_export);

  // Expand all keys from the derived early secret
  let (ck, civ, pn) = keygen_13 h ets ae is_quic in
  dbg ("Client 0-RTT key:                "^print_bytes ck^", IV="^print_bytes civ);

  let id = ID13 (KeyID expandId) in
  let ckv: StreamAE.key id = ck in
  let civ: StreamAE.iv id  = civ in
  let rw = StAE.coerce HS.root id (ckv @| civ) in
  let r = StAE.genReader HS.root rw in
  let early_d = StAEInstance r rw (pn, pn) in
  (| li, expId, early_export |), early_d

let ks_server_13_sh ks log =
  dbg ("ks_server_13_sh, hashed log = "^print_bytes log);
  let KS #region st is_quic = ks in
  let S (S_13_wait_SH (ae, h) cr sr _ (| hsId, hs |)) = !st in
  let secretId = HandshakeSecretID hsId in
  let li = LogInfo_SH ({
    li_sh_cr = cr;
    li_sh_sr = sr;
    li_sh_ae = ae;
    li_sh_hash = h;
    li_sh_psk = None;
  }) in
  let log : hashed_log li = log in

  let c_expandId = ExpandedSecret secretId ClientHandshakeTrafficSecret log in
  let s_expandId = ExpandedSecret secretId ServerHandshakeTrafficSecret log in

  // Derived handshake secret
  let cts = HKDF.derive_secret h hs "c hs traffic" log in
  dbg ("handshake traffic secret[C]:     "^print_bytes cts);
  let sts = HKDF.derive_secret h hs "s hs traffic" log in
  dbg ("handshake traffic secret[S]:     "^print_bytes sts);
  let (ck, civ, cpn) = keygen_13 h cts ae is_quic in
  dbg ("handshake key[C]:                "^print_bytes ck^", IV="^print_bytes civ);
  let (sk, siv, spn) = keygen_13 h sts ae is_quic in
  dbg ("handshake key[S]: "^print_bytes sk^", IV="^print_bytes siv);

  // Handshake traffic keys
  let id = ID13 (KeyID c_expandId) in
  let ckv: StreamAE.key id = ck in
  let civ: StreamAE.iv id  = civ in
  let skv: StreamAE.key (peerId id) = sk in
  let siv: StreamAE.iv (peerId id)  = siv in
  let w = StAE.coerce HS.root id (skv @| siv) in
  let rw = StAE.coerce HS.root id (ckv @| civ) in
  let r = StAE.genReader HS.root rw in

  // Finished keys
  let cfkId = FinishedID c_expandId in
  let sfkId = FinishedID s_expandId in
  let cfk1 = finished_13 h cts in
  dbg ("finished key[C]:                 "^print_bytes cfk1);
  let sfk1 = finished_13 h sts in
  dbg ("finished key[S]:                 "^print_bytes sfk1);

  let cfk1 : fink cfkId = HMAC_UFCMA.coerce (HMAC_UFCMA.HMAC_Finished cfkId) (fun _ -> True) region cfk1 in
  let sfk1 : fink sfkId = HMAC_UFCMA.coerce (HMAC_UFCMA.HMAC_Finished sfkId) (fun _ -> True) region sfk1 in

  let saltId = Salt (HandshakeSecretID hsId) in
  let salt = HKDF.derive_secret h hs "derived" (H.emptyHash h) in
  dbg ("Application salt:                "^print_bytes salt);

  // Replace handshake secret with application master secret
  let amsId = ASID saltId in
  let ams : ams amsId = HKDF.extract #h salt (H.zeroHash h) in
  dbg ("Application secret:              "^print_bytes ams);

  st := S (S_13_wait_SF (ae, h) (| cfkId, cfk1 |) (| sfkId, sfk1 |) (| amsId, ams |));
  StAEInstance r w (cpn, spn)

let ks_12_finished_key ks =
 let KS #region st _ = ks in
 let ms = match !st with
 | C (C_12_has_MS _ _ _ ms) -> ms
 | S (S_12_has_MS _ _ _ ms) -> ms in
 TLSPRF.coerce ms

let ks_12_record_key ks =
  dbg "ks_12_record_key";
  let KS #region st _ = ks in
  let role, csr, alpha, msId, ms =
    match !st with
    | C (C_12_has_MS csr alpha msId ms) -> Client, csr, alpha, msId, ms
    | S (S_12_has_MS csr alpha msId ms) -> Server, csr, alpha, msId, ms in
  let cr, sr = split csr 32ul in
  let (pv, cs, ems) = alpha in
  let kdf = kdfAlg pv cs in
  let ae = get_aeAlg cs in
  let id = ID12 pv msId kdf ae cr sr role in
  let AEAD alg _ = ae in (* 16-10-18 FIXME! only correct for AEAD *)
  let klen = EverCrypt.aead_keyLen alg in
  let slen = UInt32.uint_to_t (AEADProvider.salt_length id) in
  let expand = TLSPRF.kdf kdf ms (sr @| cr) FStar.Integers.(klen + klen + slen + slen) in
  dbg ("keystring (CK, CIV, SK, SIV) = "^(print_bytes expand));
  let k1, expand = split expand klen in
  let k2, expand = split expand klen in
  let iv1, iv2 = split expand slen in
  let wk, wiv, rk, riv =
    match role with
    | Client -> k1, iv1, k2, iv2
    | Server -> k2, iv2, k1, iv1 in
  let w = StAE.coerce HS.root id (wk @| wiv) in
  let rw = StAE.coerce HS.root id (rk @| riv) in
  let r = StAE.genReader HS.root rw in
  StAEInstance r w (None, None)

let ks_server_12_cke_dh ks gy hashed_log =
  dbg "ks_server_12_cke_dh";
  let KS #region st _ = ks in
  let S (S_12_wait_CKE_DH csr alpha (| g, gx |)) = !st in
  let (pv, cs, ems) = alpha in
  let (| _, gy |) = gy in
  let _ = print_share gy in
  let pmsb = CommonDH.dh_initiator g gx gy in
  dbg ("PMS: "^(print_bytes pmsb));
  let pmsId = PMS.DHPMS g (CommonDH.ipubshare gx) gy (PMS.ConcreteDHPMS pmsb) in
  let kef = kefAlg pv cs ems in
  let msId, ms =
    if ems then
      begin
      let ms = TLSPRF.prf (pv,cs) pmsb (utf8_encode "extended master secret") hashed_log 48ul in
      dbg ("extended master secret:"^(print_bytes ms));
      let msId = ExtendedMS pmsId hashed_log kef in
      msId, ms
      end
    else
      begin
      let ms = TLSPRF.extract kef pmsb csr 48ul in
      dbg ("master secret:"^(print_bytes ms));
      let msId = StandardMS pmsId csr kef in
      msId, ms
      end
    in
  st := S (S_12_has_MS csr alpha msId ms);
  ks_12_record_key ks


// ServerHello log breakpoint (client)
let ks_client_13_sh ks sr cs log gy accept_psk =
  dbg ("ks_client_13_sh hashed_log = "^(print_bytes log));
  let KS #region st is_quic = ks in
  let C (C_13_wait_SH cr esl gc) = !st in
  let CipherSuite13 ae h = cs in

  // Early secret: must derive zero here as hash is not known before
  let (| esId, es |): (i: esId & es i) =
    match esl, accept_psk with
    | l, Some n ->
      let Some (| i, es |) : option (i:esId & es i) = List.Tot.nth l n in
      dbg ("recallPSK early secret:          "^print_bytes es);
      (| i, es |)
    | _, None ->
      let es = HKDF.extract #h (H.zeroHash h) (H.zeroHash h) in
      dbg ("no PSK negotiated. Early secret: "^print_bytes es);
      (| NoPSK h, es |)
  in

  let saltId = Salt (EarlySecretID esId) in
  let salt = HKDF.derive_secret h es "derived" (H.emptyHash h) in
  dbg ("handshake salt:                  "^print_bytes salt);

  let (| hsId, hs |): (hsId: pre_hsId & hs: hs hsId) =
    match gy with
    | Some (| g, gy |) -> (* (PSK-)DHE *)
      let Some (| _, gx |) = List.Helpers.find_aux g group_matches gc in
      let gxy = CommonDH.dh_initiator g gx gy in
      dbg ("DH shared secret: "^(print_bytes gxy));
      let hsId = HSID_DHE saltId g (CommonDH.ipubshare gx) gy in
      let hs : hs hsId = HKDF.extract #h salt gxy in
      (| hsId, hs |)
    | None -> (* Pure PSK *)
      let hsId = HSID_PSK saltId in
      let hs : hs hsId = HKDF.extract #h salt (H.zeroHash h) in
      (| hsId, hs |)
    in
  dbg ("handshake secret:                "^print_bytes hs);

  let secretId = HandshakeSecretID hsId in
  let li = LogInfo_SH ({
    li_sh_cr = cr;
    li_sh_sr = sr;
    li_sh_ae = ae;
    li_sh_hash = h;
    li_sh_psk = None;
  }) in
  let log: hashed_log li = log in
  let c_expandId = ExpandedSecret secretId ClientHandshakeTrafficSecret log in
  let s_expandId = ExpandedSecret secretId ServerHandshakeTrafficSecret log in

  let cts = HKDF.derive_secret h hs "c hs traffic" log in
  dbg ("handshake traffic secret[C]:     "^print_bytes cts);
  let sts = HKDF.derive_secret h hs "s hs traffic" log in
  dbg ("handshake traffic secret[S]:     "^print_bytes sts);
  let (ck, civ, cpn) = keygen_13 h cts ae is_quic in
  dbg ("handshake key[C]:                "^print_bytes ck^", IV="^print_bytes civ);
  let (sk, siv, spn) = keygen_13 h sts ae is_quic in
  dbg ("handshake key[S]:                "^print_bytes sk^", IV="^print_bytes siv);

  // Finished keys
  let cfkId = FinishedID c_expandId in
  let sfkId = FinishedID s_expandId in
  let cfk1 = finished_13 h cts in
  dbg ("finished key[C]: "^(print_bytes cfk1));
  let sfk1 = finished_13 h sts in
  dbg ("finished key[S]: "^(print_bytes sfk1));

  let cfk1 : fink cfkId = HMAC_UFCMA.coerce (HMAC_UFCMA.HMAC_Finished cfkId) (fun _ -> True) region cfk1 in
  let sfk1 : fink sfkId = HMAC_UFCMA.coerce (HMAC_UFCMA.HMAC_Finished sfkId) (fun _ -> True) region sfk1 in

  let saltId = Salt (HandshakeSecretID hsId) in
  let salt = HKDF.derive_secret h hs "derived" (H.emptyHash h) in
  dbg ("application salt:                "^print_bytes salt);

  let asId = ASID saltId in
  let ams : ams asId = HKDF.extract #h salt (H.zeroHash h) in
  dbg ("application secret:              "^print_bytes ams);

  let id = ID13 (KeyID c_expandId) in
  assert_norm(ID13 (KeyID s_expandId) = peerId id);
  let ckv: StreamAE.key id = ck in
  let civ: StreamAE.iv id  = civ in
  let skv: StreamAE.key (peerId id) = sk in
  let siv: StreamAE.iv (peerId id)  = siv in
  let w = StAE.coerce HS.root id (ckv @| civ) in
  let rw = StAE.coerce HS.root id (skv @| siv) in
  let r = StAE.genReader HS.root rw in
  st := C (C_13_wait_SF (ae, h) (| cfkId, cfk1 |) (| sfkId, sfk1 |) (| asId, ams |));
  StAEInstance r w (spn, cpn)

(******************************************************************)

let ks_client_13_sf ks (log:bytes)
  : ST (( i:finishedId & sfk:fink i ) * ( i:finishedId & cfk:fink i ) * recordInstance * exportKey)
  (requires fun h0 ->
    let kss = sel h0 (KS?.state ks) in
    C? kss /\ C_13_wait_SF? (C?.s kss))
  (ensures fun h0 r h1 ->
    let KS #rid st _ = ks in
    modifies (Set.singleton rid) h0 h1
    /\ HS.modifies_ref rid (Set.singleton (Heap.addr_of (as_ref st))) ( h0) ( h1))
  =
  dbg ("ks_client_13_sf hashed_log = "^(print_bytes log));
  let KS #region st is_quic = ks in
  let C (C_13_wait_SF alpha cfk sfk (| asId, ams |)) = !st in
  let (ae, h) = alpha in

  let FinishedID #li _ = dfst cfk in // TODO loginfo
  let log : hashed_log li = log in
  let secretId = ApplicationSecretID asId in
  let c_expandId = ExpandedSecret secretId ClientApplicationTrafficSecret log in
  let s_expandId = ExpandedSecret secretId ClientApplicationTrafficSecret log in

  let cts = HKDF.derive_secret h ams "c ap traffic" log in
  dbg ("application traffic secret[C]:   "^print_bytes cts);
  let sts = HKDF.derive_secret h ams "s ap traffic" log in
  dbg ("application traffic secret[S]:   "^print_bytes sts);
  let emsId : exportId li = ExportID asId log in
  let ems = HKDF.derive_secret h ams "exp master" log in
  dbg ("exporter master secret:          "^print_bytes ems);
  let exporter1 = (| li, emsId, ems |) in

  let (ck,civ,cpn) = keygen_13 h cts ae is_quic in
  dbg ("application key[C]:              "^print_bytes ck^", IV="^print_bytes civ);
  let (sk,siv,spn) = keygen_13 h sts ae is_quic in
  dbg ("application key[S]:              "^print_bytes sk^", IV="^print_bytes siv);

  let id = ID13 (KeyID c_expandId) in
  assert_norm(peerId id = ID13 (KeyID s_expandId));
  let ckv: StreamAE.key id = ck in
  let civ: StreamAE.iv id  = civ in
  let w = StAE.coerce HS.root id (ckv @| civ) in
  let skv: StreamAE.key (peerId id) = sk in
  let siv: StreamAE.iv (peerId id)  = siv in
  let rw = StAE.coerce HS.root id (skv @| siv) in
  let r = StAE.genReader HS.root rw in

  st := C (C_13_wait_CF alpha cfk (| asId, ams |) (| li, c_expandId, (cts,sts)|));
  (sfk, cfk, StAEInstance r w (spn, cpn), exporter1)

let ks_server_13_sf ks (log:bytes)
  : ST (recordInstance * (li:logInfo & i:exportId li & ems i))
  (requires fun h0 ->
    let kss = sel h0 (KS?.state ks) in
    S? kss /\ C_13_wait_SF? (C?.s kss))
  (ensures fun h0 r h1 ->
    let KS #rid st _ = ks in
    modifies (Set.singleton rid) h0 h1
    /\ HS.modifies_ref rid (Set.singleton (Heap.addr_of (as_ref st))) ( h0) ( h1))
  =
  dbg ("ks_server_13_sf hashed_log = "^print_bytes log);
  let KS #region st is_quic = ks in
  let S (S_13_wait_SF alpha cfk _ (| asId, ams |)) = !st in
  let FinishedID #li _ = dfst cfk in // TODO loginfo
  let (ae, h) = alpha in

  let log : hashed_log li = log in
  let secretId = ApplicationSecretID asId in
  let c_expandId = ExpandedSecret secretId ClientApplicationTrafficSecret log in
  let s_expandId = ExpandedSecret secretId ClientApplicationTrafficSecret log in

  let cts = HKDF.derive_secret h ams "c ap traffic" log in
  dbg ("application traffic secret[C]:   "^print_bytes cts);
  let sts = HKDF.derive_secret h ams "s ap traffic" log in
  dbg ("application traffic secret[S]:   "^print_bytes sts);
  let emsId : exportId li = ExportID asId log in
  let ems = HKDF.derive_secret h ams "exp master" log in
  dbg ("exporter master secret:          "^print_bytes ems);
  let exporter1 = (| li, emsId, ems |) in

  let (ck,civ,cpn) = keygen_13 h cts ae is_quic in
  dbg ("application key[C]:              "^print_bytes ck^", IV="^print_bytes civ);
  let (sk,siv,spn) = keygen_13 h sts ae is_quic in
  dbg ("application key[S]:              "^print_bytes sk^", IV="^print_bytes siv);

  let id = ID13 (KeyID c_expandId) in
  assert_norm(peerId id = ID13 (KeyID s_expandId));
  let skv: StreamAE.key id = sk in
  let siv: StreamAE.iv id  = siv in
  let w = StAE.coerce HS.root id (skv @| siv) in
  let ckv: StreamAE.key (peerId id) = ck in
  let civ: StreamAE.iv (peerId id)  = civ in
  let rw = StAE.coerce HS.root id (ckv @| civ) in
  let r = StAE.genReader HS.root rw in

  st := S (S_13_wait_CF alpha cfk (| asId, ams |) (| li, c_expandId, (cts,sts) |));
  StAEInstance r w (cpn, spn), exporter1

let ks_server_13_cf ks (log:bytes) : ST unit
  (requires fun h0 ->
    let kss = sel h0 (KS?.state ks) in
    S? kss /\ S_13_wait_CF? (S?.s kss))
  (ensures fun h0 r h1 ->
    let KS #rid st _ = ks in
    modifies (Set.singleton rid) h0 h1
    /\ HS.modifies_ref rid (Set.singleton (Heap.addr_of (as_ref st))) ( h0) ( h1))
  =
  dbg ("ks_server_13_cf hashed_log = "^(print_bytes log));
  let KS #region st _ = ks in
  let S (S_13_wait_CF alpha cfk (| asId, ams |) rekey_info) = !st in
  let (ae, h) = alpha in
  let (| li, _, _ |) = rekey_info in
  let log : hashed_log li = log in
  let rmsId : rmsId li = RMSID asId log in
  let rms : rms rmsId = HKDF.derive_secret h ams "res master" log in
  dbg ("resumption master secret:        "^print_bytes rms);
  st := S (S_13_postHS alpha rekey_info (| li, rmsId, rms |))

// Handshake must call this when ClientFinished goes into log
let ks_client_13_cf ks (log:bytes) : ST unit
  (requires fun h0 ->
    let kss = sel h0 (KS?.state ks) in
    C? kss /\ C_13_wait_CF? (C?.s kss))
  (ensures fun h0 r h1 ->
    let KS #rid st _ = ks in
    modifies (Set.singleton rid) h0 h1
    /\ HS.modifies_ref rid (Set.singleton (Heap.addr_of (as_ref st))) ( h0) ( h1))
  =
  dbg ("ks_client_13_cf hashed_log = "^(print_bytes log));
  let KS #region st _ = ks in
  let C (C_13_wait_CF alpha cfk (| asId, ams |) rekey_info) = !st in
  let (ae, h) = alpha in

  // TODO loginfo CF
  let (| li, _, _ |) = rekey_info in
  let log : hashed_log li = log in
  let rmsId : rmsId li = RMSID asId log in

  let rms : rms rmsId = HKDF.derive_secret h ams "res master" log in
  dbg ("resumption master secret:        "^print_bytes rms);
  st := C (C_13_postHS alpha rekey_info (| li, rmsId, rms |))


let ks_13_rekey_secrets ks : ST (option raw_rekey_secrets)
  (requires fun h0 -> True)
  (ensures fun h0 r h1 ->
    let KS #rid st _ = ks in
    modifies_none h0 h1)
  =
  dbg "ks_13_get_rekey";
  let KS #r st _ = ks in
  let ori : option (li:logInfo & i:rekeyId li & rekey_secrets i) =
    match !st with
    | C (C_13_postHS _ ri _) -> Some ri
    | C (C_13_wait_CF _ _ _ ri) -> Some ri
    | S (S_13_postHS _ ri _ ) -> Some ri
    | S (S_13_wait_CF _ _ _ ri) -> Some ri
    | _ -> None in
  match ori with
  | None -> None
  | Some (| li, _, (crs, srs) |) -> Some ({
    rekey_aead = logInfo_ae li;
    rekey_hash = logInfo_hash li;
    rekey_client = crs;
    rekey_server = srs;
    })

(******************************************************************)

let ks_client_12_full_dh ks sr pv cs ems (|g,gx|) =
  let KS #region st _ = ks in
  let cr = match !st with
    | C (C_12_Full_CH cr) -> cr
    | C (C_12_Resume_CH cr _ _ _) -> cr
    | C (C_13_wait_SH cr _ _ ) -> cr in
  let csr = cr @| sr in
  let alpha = (pv, cs, ems) in
  let gy, pmsb = CommonDH.dh_responder g gx in
  let _ = print_share gx in
  let _ = print_share gy in
  dbg ("PMS: "^(print_bytes pmsb));
  let dhpmsId = PMS.DHPMS g gx gy (PMS.ConcreteDHPMS pmsb) in
  let ns =
    if ems then
      C_12_wait_MS csr alpha dhpmsId pmsb
    else
      let kef = kefAlg pv cs false in
      let ms = TLSPRF.extract kef pmsb csr 48ul in
      dbg ("master secret: "^(print_bytes ms));
      let msId = StandardMS dhpmsId csr kef in
      C_12_has_MS csr alpha msId ms in
  st := C ns; gy

let ks_client_12_full_rsa ks sr pv cs ems pk =
  let KS #region st _ = ks in
  let alpha = (pv, cs, ems) in
  let cr = match !st with
    | C (C_12_Full_CH cr) -> cr
    | C (C_12_Resume_CH cr _ _ _) -> cr in
  let csr = cr @| sr in
  let rsapms = PMS.genRSA pk pv in
  let pmsb = PMS.leakRSA pk pv rsapms in
  let encrypted = Random.sample 256 in //CoreCrypto.rsa_encrypt (RSAKey.repr_of_rsapkey pk) CoreCrypto.Pad_PKCS1 pmsb in
  let rsapmsId = PMS.RSAPMS(pk, pv, rsapms) in
  let ns =
    if ems then
      C_12_wait_MS csr alpha rsapmsId pmsb
    else
      let kef = kefAlg pv cs false in
      let ms = TLSPRF.extract kef pmsb csr 48ul in
      let msId = StandardMS rsapmsId csr kef in
      C_12_has_MS csr alpha msId ms in
  st := C ns; encrypted


let ks_client_12_set_session_hash ks log =
  dbg ("ks_client_12_set_session_hash hashed_log = "^(print_bytes log));
  let KS #region st _ = ks in
  let ms =
    match !st with
    | C (C_12_has_MS csr alpha msId ms) ->
      dbg ("master secret:"^(print_bytes ms));
      ms
    | C (C_12_wait_MS csr alpha pmsId pms) ->
      let (pv, cs, ems) = alpha in
      let kef = kefAlg pv cs ems in
      let h = verifyDataHashAlg_of_ciphersuite cs in
      let msId, ms =
        if ems then
          begin
          let ms = TLSPRF.prf (pv,cs) pms (utf8_encode "extended master secret") log 48ul in
          dbg ("extended master secret:"^(print_bytes ms));
          let msId = ExtendedMS pmsId log kef in
          msId, ms
          end
        else
          begin
          let ms = TLSPRF.extract kef pms csr 48ul in
          dbg ("master secret:"^(print_bytes ms));
          let msId = StandardMS pmsId csr kef in
          msId, ms
          end
      in
      st := C (C_12_has_MS csr alpha msId ms);
      ms
    in
  let appk = ks_12_record_key ks in
  (TLSPRF.coerce ms, appk)

// *********************************************************************************
//  All functions below assume that the MS is already computed (and thus they are
//  shared accross role, key exchange, handshake mode...)
// *********************************************************************************

(*)
let ks_client_12_client_finished ks
  : ST (cvd:bytes)
  (requires fun h0 ->
    let st = sel h0 (KS?.state ks) in
    C? st /\ C_12_has_MS? (C?.s st))
  (ensures fun h0 r h1 -> h1 == h0)
  =
  let KS #region st = ks in
  let C (C_12_has_MS csr alpha msId ms) = !st in
  let (pv, cs, ems) = alpha in
//  let h = verifyDataHashAlg_of_ciphersuite cs in
//  let log = HandshakeLog.getHash hsl h in
  let log = HandshakeLog.getBytes hsl in
  TLSPRF.verifyData (pv,cs) ms Client log

let ks_server_12_client_finished ks
  : ST (cvd:bytes)
  (requires fun h0 ->
    let st = sel h0 (KS?.state ks) in
    S? st /\ S_12_has_MS? (S?.s st))
  (ensures fun h0 r h1 -> h1 == h0)
  =
  let KS #region st = ks in
  let S (S_12_has_MS csr alpha msId ms) = !st in
  let (pv, cs, ems) = alpha in
//  let h = verifyDataHashAlg_of_ciphersuite cs in
//  let log = HandshakeLog.getHash hsl h in
  let log = HandshakeLog.getBytes hsl in
  TLSPRF.verifyData (pv,cs) ms Client log

let ks_server_12_server_finished ks
  : ST (svd:bytes)
  (requires fun h0 ->
    let st = sel h0 (KS?.state ks) in
    S? st /\ S_12_has_MS? (S?.s st))
  (ensures fun h0 r h1 ->
    let KS #rid st = ks in
    modifies (Set.singleton rid) h0 h1
    /\ HS.modifies_ref rid !{as_ref st} ( h0) ( h1))
  =
  let KS #region st = ks in
  let S (S_12_has_MS csr alpha msId ms) = !st in
  let (pv, cs, ems) = alpha in
//  let h = verifyDataHashAlg_of_ciphersuite cs in
//  let log = HandshakeLog.getHash hsl h in
  let log = HandshakeLog.getBytes hsl in
  st := S S_Done;
  TLSPRF.verifyData (pv,cs) ms Server log

let ks_client_12_server_finished ks
  : ST (svd:bytes)
  (requires fun h0 ->
    let st = sel h0 (KS?.state ks) in
    C? st /\ C_12_has_MS? (C?.s st))
  (ensures fun h0 r h1 ->
    let KS #rid st = ks in
    modifies (Set.singleton rid) h0 h1
    /\ HS.modifies_ref rid !{as_ref st} ( h0) ( h1))
  =
  let KS #region st = ks in
  let C (C_12_has_MS csr alpha msId ms) = !st in
  let (pv, cs, ems) = alpha in
//  let h = verifyDataHashAlg_of_ciphersuite cs in
//  let log = HandshakeLog.getHash hsl h in
  let log = HandshakeLog.getBytes hsl in
  st := C C_Done;
  TLSPRF.verifyData (pv,cs) ms Server log
*)
