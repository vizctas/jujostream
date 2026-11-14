#pragma once

#include <stdbool.h>

#ifdef USE_MBEDTLS
#include <mbedtls/cipher.h>
#else
// Hide the real OpenSSL definition from other code
typedef struct evp_cipher_ctx_st EVP_CIPHER_CTX;
#endif

typedef struct _PLT_CRYPTO_CONTEXT {
#ifdef USE_MBEDTLS
    mbedtls_cipher_context_t ctx;
    bool initialized;
#else
    EVP_CIPHER_CTX* ctx;
    bool initialized;
#endif
} PLT_CRYPTO_CONTEXT, *PPLT_CRYPTO_CONTEXT;

#define ROUND_TO_PKCS7_PADDED_LEN(x) ((((x) + 15) / 16) * 16)

PPLT_CRYPTO_CONTEXT PltCreateCryptoContext(void);
void PltDestroyCryptoContext(PPLT_CRYPTO_CONTEXT ctx);

#define ALGORITHM_AES_CBC 1
#define ALGORITHM_AES_GCM 2

#define CIPHER_FLAG_RESET_IV          0x01
#define CIPHER_FLAG_FINISH            0x02
#define CIPHER_FLAG_PAD_TO_BLOCK_SIZE 0x04

bool PltEncryptMessage(PPLT_CRYPTO_CONTEXT ctx, int algorithm, int flags,
                       unsigned char* key, int keyLength,
                       unsigned char* iv, int ivLength,
                       unsigned char* tag, int tagLength,
                       unsigned char* inputData, int inputDataLength,
                       unsigned char* outputData, int* outputDataLength);

bool PltDecryptMessage(PPLT_CRYPTO_CONTEXT ctx, int algorithm, int flags,
                       unsigned char* key, int keyLength,
                       unsigned char* iv, int ivLength,
                       unsigned char* tag, int tagLength,
                       unsigned char* inputData, int inputDataLength,
                       unsigned char* outputData, int* outputDataLength);

bool PltEncryptAesEcbBlock(const unsigned char* key, int keyLength,
                           const unsigned char* inputBlock, unsigned char* outputBlock);

bool PltEncryptAesGcmAad(const unsigned char* key, int keyLength,
                         const unsigned char* iv, int ivLength,
                         const unsigned char* aad, int aadLength,
                         const unsigned char* plaintext, int plaintextLength,
                         unsigned char* tagOut, int tagLength,
                         unsigned char* ciphertextOut);

bool PltDecryptAesGcmAad(const unsigned char* key, int keyLength,
                         const unsigned char* iv, int ivLength,
                         const unsigned char* aad, int aadLength,
                         const unsigned char* ciphertext, int ciphertextLength,
                         const unsigned char* tag, int tagLength,
                         unsigned char* plaintextOut);

void PltGenerateRandomData(unsigned char* data, int length);
