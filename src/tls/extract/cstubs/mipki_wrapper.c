#include <krmllib.h>
#include <mipki.h>
#include <mitlsffi.h>
#include <PKI.h>
#include <TLSConstants.h>
#include <Negotiation.h>

#define DEBUG 0

/* Accumulating a few aliases at krml's code-gen changes for monomorphized types
 * (hint: PICK A TYPE ABBREVIATION OF YOUR CHOICE INSTEAD OF RELYING ON THE
 * AUTO-GENERATED NAMES!!) */
#define FStar_Pervasives_Native_option___uint64_t_Parsers_SignatureScheme_signatureScheme Negotiation_certNego
typedef TLSConstants_alpn_gc Prims_list__FStar_Bytes_bytes;

static size_t list_sa_len(Parsers_SignatureSchemeList_signatureSchemeList l)
{
  if (l->tag == Prims_Cons)
  {
    return 1 + list_sa_len(l->tl);
  }
  return 0;
}

static size_t list_bytes_len(Prims_list__FStar_Bytes_bytes* l)
{
  if (l->tag == Prims_Cons)
  {
    return 1 + list_bytes_len(l->tl);
  }
  return 0;
}

static Parsers_SignatureScheme_signatureScheme_tags tls_of_pki(mitls_signature_scheme sa)
{
  switch(sa)
  {
    //  rsa_pkcs1_sha1(0x0201),
    case 0x0201: return Parsers_SignatureScheme_Rsa_pkcs1_sha1;
    //  rsa_pkcs1_sha256(0x0401),
    case 0x0401: return Parsers_SignatureScheme_Rsa_pkcs1_sha256;
    //  rsa_pkcs1_sha384(0x0501),
    case 0x0501: return Parsers_SignatureScheme_Rsa_pkcs1_sha384;
    //  rsa_pkcs1_sha512(0x0601),
    case 0x0601: return Parsers_SignatureScheme_Rsa_pkcs1_sha512;
    //  rsa_pss_sha256(0x0804),
    case 0x0804: return Parsers_SignatureScheme_Rsa_pss_rsae_sha256;
    //  rsa_pss_sha384(0x0805),
    case 0x0805: return Parsers_SignatureScheme_Rsa_pss_rsae_sha384;
    //  rsa_pss_sha512(0x0806),
    case 0x0806: return Parsers_SignatureScheme_Rsa_pss_rsae_sha512;
    //  ecdsa_sha1(0x0203),
    case 0x0203: return Parsers_SignatureScheme_Ecdsa_sha1;
    //  ecdsa_secp256r1_sha256(0x0403),
    case 0x0403: return Parsers_SignatureScheme_Ecdsa_secp256r1_sha256;
    //  ecdsa_secp384r1_sha384(0x0503),
    case 0x0503: return Parsers_SignatureScheme_Ecdsa_secp384r1_sha384;
    //  ecdsa_secp521r1_sha512(0x0603),
    case 0x0603: return Parsers_SignatureScheme_Ecdsa_secp521r1_sha512;
    //  ed25519(0x0807),
    //  ed448(0x0808),
    default:
      KRML_HOST_PRINTF("tls_of_pki: unsupported (%04x)\n", sa);
      KRML_HOST_EXIT(1);
  }
}

static mitls_signature_scheme pki_of_tls(Parsers_SignatureScheme_signatureScheme_tags sa)
{
  switch(sa)
  {
    //  rsa_pkcs1_sha1(0x0201),
    case Parsers_SignatureScheme_Rsa_pkcs1_sha1: return 0x0201;
    //  rsa_pkcs1_sha256(0x0401),
    case Parsers_SignatureScheme_Rsa_pkcs1_sha256: return 0x0401;
    //  rsa_pkcs1_sha384(0x0501),
    case Parsers_SignatureScheme_Rsa_pkcs1_sha384: return 0x0501;
    //  rsa_pkcs1_sha512(0x0601),
    case Parsers_SignatureScheme_Rsa_pkcs1_sha512: return 0x0601;
    //  rsa_pss_sha256(0x0804),
    case Parsers_SignatureScheme_Rsa_pss_rsae_sha256: return 0x0804;
    //  rsa_pss_sha384(0x0805),
    case Parsers_SignatureScheme_Rsa_pss_rsae_sha384: return 0x0805;
    //  rsa_pss_sha512(0x0806),
    case Parsers_SignatureScheme_Rsa_pss_rsae_sha512: return 0x0806;
    //  ecdsa_sha1(0x0203),
    case Parsers_SignatureScheme_Ecdsa_sha1: return 0x0203;
    //  ecdsa_secp256r1_sha256(0x0403),
    case Parsers_SignatureScheme_Ecdsa_secp256r1_sha256: return 0x0403;
    //  ecdsa_secp384r1_sha384(0x0503),
    case Parsers_SignatureScheme_Ecdsa_secp384r1_sha384: return 0x0503;
    //  ecdsa_secp521r1_sha512(0x0603),
    case Parsers_SignatureScheme_Ecdsa_secp521r1_sha512: return 0x0603;
    //  ed25519(0x0807), ed448(0x0808),
    default:
      KRML_HOST_PRINTF("pki_of_tls: unsupported (%d)\n", sa);
      KRML_HOST_EXIT(1);
  }
}

void
PKI_select_(FStar_Dyn_dyn cbs, FStar_Dyn_dyn st, Parsers_ProtocolVersion_protocolVersion pv,
  FStar_Bytes_bytes sni, FStar_Bytes_bytes alpn, Parsers_SignatureSchemeList_signatureSchemeList sal,
  FStar_Pervasives_Native_option___uint64_t_Parsers_SignatureScheme_signatureScheme *res)
{
  mitls_signature_scheme sel;
  mipki_state *pki = (mipki_state*)cbs;

  #if DEBUG
    KRML_HOST_PRINTF("PKI| SELECT callback <%08x>\n", cbs);
  #endif

  size_t sigalgs_len = list_sa_len(sal);
  mitls_signature_scheme *sigalgs = alloca(sigalgs_len*sizeof(mitls_signature_scheme));
  Parsers_SignatureSchemeList_signatureSchemeList cur = sal;

  for(size_t i = 0; i < sigalgs_len; i++)
  {
    sigalgs[i] = pki_of_tls(cur->hd.tag);
    cur = cur->tl;
  }

  mipki_chain chain = mipki_select_certificate(pki, sni.data, sni.length, sigalgs, sigalgs_len, &sel);

  #if DEBUG
    KRML_HOST_PRINTF("PKI| Selected chain <%08x>, sigalg = %04x\n", chain, sel);
  #endif

  if(chain == NULL)
  {
    res->tag = FStar_Pervasives_Native_None;
  }
  else
  {
    K___uint64_t_Parsers_SignatureScheme_signatureScheme sig;

    // silence a GCC warning about sig.snd._0.length possibly uninitialized
    memset(&sig, 0, sizeof(sig));

    res->tag = FStar_Pervasives_Native_Some;
    sig.fst = (uint64_t)chain;
    sig.snd.tag = tls_of_pki(sel);
    res->v = sig;
  }
}

FStar_Pervasives_Native_option___uint64_t_Parsers_SignatureScheme_signatureScheme
PKI_select(FStar_Dyn_dyn cbs, FStar_Dyn_dyn st, Parsers_ProtocolVersion_protocolVersion pv,
  FStar_Bytes_bytes sni, FStar_Bytes_bytes alpn,
  Parsers_SignatureSchemeList_signatureSchemeList sal)
{
  FStar_Pervasives_Native_option___uint64_t_Parsers_SignatureScheme_signatureScheme dst;
  PKI_select_(cbs, st, pv, sni, alpn, sal, &dst);
  return dst;
}

static void* append(void* chain, size_t len, char **buf)
{
  #if DEBUG
    printf("PKI| FORMAT::append adding %d bytes element\n", len);
  #endif

  *buf = KRML_HOST_MALLOC(len);

  Prims_list__FStar_Bytes_bytes* cur = (Prims_list__FStar_Bytes_bytes*) chain;
  Prims_list__FStar_Bytes_bytes* new = KRML_HOST_MALLOC(sizeof(Prims_list__FStar_Bytes_bytes));

  new->tag = Prims_Nil;
  cur->tag = Prims_Cons;

  cur->hd = (FStar_Bytes_bytes){.length = len, .data = *buf};
  cur->tl = new;
  return (void*)new;
}

Prims_list__FStar_Bytes_bytes* PKI_format(FStar_Dyn_dyn cbs, FStar_Dyn_dyn st, uint64_t cert)
{
  mipki_state *pki = (mipki_state*)cbs;
  mipki_chain chain = (mipki_chain)cert;

  #if DEBUG
    KRML_HOST_PRINTF("PKI| FORMAT <%08x> CHAIN <%08x>\n", pki, chain);
  #endif

  Prims_list__FStar_Bytes_bytes *res = KRML_HOST_MALLOC(sizeof(Prims_list__FStar_Bytes_bytes));
  mipki_format_alloc(pki, chain, (void*)res, append);
  return res;
}

void PKI_sign_(FStar_Dyn_dyn cbs, FStar_Dyn_dyn st,
  uint64_t cert, Parsers_SignatureScheme_signatureScheme *sa, FStar_Bytes_bytes tbs,
  FStar_Pervasives_Native_option__FStar_Bytes_bytes *res)
{
  mipki_state *pki = (mipki_state*)cbs;
  mipki_chain chain = (mipki_chain)cert;

  #if DEBUG
    KRML_HOST_PRINTF("PKI| SIGN <%08x> CHAIN <%08x>\n", pki, chain);
  #endif

  char* sig = KRML_HOST_MALLOC(MAX_SIGNATURE_LEN);
  size_t slen = MAX_SIGNATURE_LEN;
  res->tag = FStar_Pervasives_Native_None;
  mipki_signature sigalg = pki_of_tls(sa->tag);

  if(mipki_sign_verify(pki, chain, sigalg, tbs.data, tbs.length, sig, &slen, MIPKI_SIGN))
  {
    #if DEBUG
      KRML_HOST_PRINTF("PKI| Success: produced %d bytes of signature.\n", pki, slen);
    #endif
    res->tag = FStar_Pervasives_Native_Some;
    res->v = (FStar_Bytes_bytes){.length = slen, .data = sig};
  }
}

FStar_Pervasives_Native_option__FStar_Bytes_bytes PKI_sign(FStar_Dyn_dyn cbs, FStar_Dyn_dyn st,
  uint64_t cert, Parsers_SignatureScheme_signatureScheme sa, FStar_Bytes_bytes tbs)
{
  FStar_Pervasives_Native_option__FStar_Bytes_bytes res;
  PKI_sign_(cbs, st, cert, &sa, tbs, &res);
  return res;
}

bool PKI_verify_(FStar_Dyn_dyn cbs, FStar_Dyn_dyn st,
  Prims_list__FStar_Bytes_bytes *certs, Parsers_SignatureScheme_signatureScheme *sa,
  FStar_Bytes_bytes tbs, FStar_Bytes_bytes sig)
{
  mipki_state *pki = (mipki_state*)cbs;
  size_t chain_len = list_bytes_len(certs);

  #if DEBUG
    KRML_HOST_PRINTF("PKI| VERIFY <%08x> (contains %d certificates)\n", pki, chain_len);
  #endif

  mipki_signature sigalg = pki_of_tls(sa->tag);
  size_t *lens = alloca(chain_len*sizeof(size_t));
  const char **ders = alloca(chain_len*sizeof(const char*));
  Prims_list__FStar_Bytes_bytes *cur = certs;

  for(size_t i = 0; i < chain_len; i++)
  {
    lens[i] = cur->hd.length;
    ders[i] = cur->hd.data;
    cur = cur->tl;
  }

  mipki_chain chain = mipki_parse_list(pki, ders, lens, chain_len);
  size_t slen = sig.length;

  if(chain == NULL)
  {
    #if DEBUG
      KRML_HOST_PRINTF("PKI| Failed to parse certificate chain.\n");
    #endif
    return false;
  }

  // We don't validate hostname, but could with the callback state
  if(!mipki_validate_chain(pki, chain, ""))
  {
    #if DEBUG
      KRML_HOST_PRINTF("PKI| WARNING: chain validation failed, ignoring.\n");
    #endif
    // return 0;
  }

  #if DEBUG
    KRML_HOST_PRINTF("PKI| Chain parsed, verifying %d bytes signature with %04x.\n", slen, sigalg);
  #endif

  char* sigp = (char *)sig.data;
  int r = mipki_sign_verify(pki, chain, sigalg, tbs.data, tbs.length,
    sigp, &slen, MIPKI_VERIFY);

  mipki_free_chain(pki, chain);
  return (r == 1);
}

bool PKI_verify(FStar_Dyn_dyn cbs, FStar_Dyn_dyn st,
  Prims_list__FStar_Bytes_bytes *certs, Parsers_SignatureScheme_signatureScheme sa,
  FStar_Bytes_bytes tbs, FStar_Bytes_bytes sig) {
  return PKI_verify_(cbs, st, certs, &sa, tbs, sig);
}

static uint32_t config_len(Prims_list__Prims_string___Prims_string___bool *l)
{
  if (l->tag == Prims_Cons)
  {
    return 1 + config_len(l->tl);
  }
  return 0;
}

FStar_Dyn_dyn PKI_init(Prims_string cafile, Prims_list__Prims_string___Prims_string___bool *certs)
{
  uint32_t len = config_len(certs);
  Prims_list__Prims_string___Prims_string___bool* cur = certs;
  mipki_config_entry *pki_config = alloca(len*sizeof(mipki_config_entry));
  int err;

  for(int i = 0; i<len; i++)
  {
    K___Prims_string_Prims_string_bool cfg = cur->hd;

    #if DEBUG
      KRML_HOST_PRINTF("PKI| Adding cert <%s> with key <%s>\n", cfg.fst, cfg.snd);
    #endif

    pki_config[i] = (mipki_config_entry){
      .cert_file = cfg.fst,
      .key_file = cfg.snd,
      .is_universal = cfg.thd
    };
    cur = cur->tl;
  };

  #if DEBUG
    KRML_HOST_PRINTF("PKI| INIT\n");
  #endif

  mipki_state *pki = mipki_init(pki_config, len, NULL, &err);
  if(pki == NULL) {
     KRML_HOST_PRINTF("mipki_init failed at %s:%d. Do all files in the config exist?\n", __FILE__, __LINE__);
     KRML_HOST_EXIT(253);
  }

  #if DEBUG
    KRML_HOST_PRINTF("PKI| Created <%08x>, set CAFILE <%s>\n", pki, cafile);
  #endif

  if(cafile[0] != '\0') mipki_add_root_file_or_path(pki, cafile);

  return pki;
}

#ifdef KRML_NOSTRUCT_PASSING
void PKI_tls_callbacks(FStar_Dyn_dyn x0, TLSConstants_cert_cb *dst)
{
  dst->app_context = x0;
  dst->cert_select_ptr = NULL;
  dst->cert_select_cb = PKI_select_;
  dst->cert_format_ptr = NULL;
  dst->cert_format_cb = PKI_format;
  dst->cert_sign_ptr = NULL;
  dst->cert_sign_cb = PKI_sign_;
  dst->cert_verify_ptr = NULL;
  dst->cert_verify_cb = PKI_verify_;
}
#else
TLSConstants_cert_cb PKI_tls_callbacks(FStar_Dyn_dyn x0)
{
  return (TLSConstants_cert_cb){
    .app_context = x0,
    .cert_select_ptr = NULL,
    .cert_select_cb = PKI_select,
    .cert_format_ptr = NULL,
    .cert_format_cb = PKI_format,
    .cert_sign_ptr = NULL,
    .cert_sign_cb = PKI_sign,
    .cert_verify_ptr = NULL,
    .cert_verify_cb = PKI_verify
  };
}
#endif

void PKI_free(FStar_Dyn_dyn pki)
{
  mipki_free((mipki_state*)pki);
}
