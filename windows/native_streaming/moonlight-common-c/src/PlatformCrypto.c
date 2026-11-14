#include "Limelight-internal.h"

#ifdef USE_MBEDTLS
#include <mbedtls/entropy.h>
#include <mbedtls/ctr_drbg.h>
#include <mbedtls/version.h>

mbedtls_entropy_context EntropyContext;
mbedtls_ctr_drbg_context CtrDrbgContext;
bool RandomStateInitialized = false;

#if MBEDTLS_VERSION_MAJOR > 2 || (MBEDTLS_VERSION_MAJOR == 2 && MBEDTLS_VERSION_MINOR >= 25)
#define USE_MBEDTLS_CRYPTO_EXT
#endif

#else
#include <openssl/evp.h>
#include <openssl/rand.h>
#endif

static int addPkcs7PaddingInPlace(unsigned char* plaintext, int plaintextLen) {
    int paddedLength = ROUND_TO_PKCS7_PADDED_LEN(plaintextLen);
    unsigned char paddingByte = (unsigned char)(16 - (plaintextLen % 16));

    memset(&plaintext[plaintextLen], paddingByte, paddedLength - plaintextLen);

    return paddedLength;
}

// When CIPHER_FLAG_PAD_TO_BLOCK_SIZE is used, inputData buffer must be allocated such that
// the buffer length is at least ROUND_TO_PKCS7_PADDED_LEN(inputDataLength) and inputData
// buffer may be modified!
// For GCM, the IV can change from message to message without CIPHER_FLAG_RESET_IV.
// CIPHER_FLAG_RESET_IV is only required for GCM when the IV length changes.
// Changing the key between encrypt/decrypt calls on a single context is not supported.
bool PltEncryptMessage(PPLT_CRYPTO_CONTEXT ctx, int algorithm, int flags,
                       unsigned char* key, int keyLength,
                       unsigned char* iv, int ivLength,
                       unsigned char* tag, int tagLength,
                       unsigned char* inputData, int inputDataLength,
                       unsigned char* outputData, int* outputDataLength) {
#ifdef USE_MBEDTLS
    mbedtls_cipher_mode_t cipherMode;
    size_t outLength;

    switch (algorithm) {
    case ALGORITHM_AES_CBC:
        LC_ASSERT(tag == NULL);
        LC_ASSERT(tagLength == 0);
        cipherMode = MBEDTLS_MODE_CBC;
        break;
    case ALGORITHM_AES_GCM:
        LC_ASSERT(tag != NULL);
        LC_ASSERT(tagLength > 0);
        cipherMode = MBEDTLS_MODE_GCM;
        break;
    default:
        LC_ASSERT(false);
        return false;
    }

    if (!ctx->initialized) {
        if (mbedtls_cipher_setup(&ctx->ctx, mbedtls_cipher_info_from_values(MBEDTLS_CIPHER_ID_AES, keyLength * 8, cipherMode)) != 0) {
            return false;
        }

        if (mbedtls_cipher_setkey(&ctx->ctx, key, keyLength * 8, MBEDTLS_ENCRYPT) != 0) {
            return false;
        }

        ctx->initialized = true;
    }

    if (tag != NULL) {
#ifdef USE_MBEDTLS_CRYPTO_EXT
        // In mbedTLS, tag is always after ciphertext, while we need to put tag BEFORE ciphertext here
        // To avoid frequent heap allocation, we will use some evil tricks...
        // We only support 16 bytes sized tag
        LC_ASSERT(tagLength == 16);
        // Assume outputData is right after tag
        LC_ASSERT(outputData == tag + tagLength);
#ifndef LC_DEBUG
        if (tagLength != 16 || outputData != tag + tagLength) {
            return false;
        }
#endif
        size_t encryptedLength = 0;
        unsigned char * encryptedData = tag;
        size_t encryptedCapacity = inputDataLength + tagLength;
        if (mbedtls_cipher_auth_encrypt_ext(&ctx->ctx, iv, ivLength, NULL, 0, inputData, inputDataLength, encryptedData,
                                            encryptedCapacity, &encryptedLength, tagLength) != 0) {
            return false;
        }
        outLength = encryptedLength - tagLength;

        unsigned char tagTemp[16];
        // Copy the tag to temp buffer
        memcpy(tagTemp, encryptedData + outLength, tagLength);
        // Move ciphertext to the end
        memmove(encryptedData + tagLength, encryptedData, outLength);
        // Copy back tag
        memcpy(encryptedData, tagTemp, tagLength);
#else
        if (mbedtls_cipher_auth_encrypt(&ctx->ctx, iv, ivLength, NULL, 0, inputData, inputDataLength, outputData, &outLength, tag, tagLength) != 0) {
            return false;
        }
#endif
    }
    else {
        if (flags & CIPHER_FLAG_RESET_IV) {
            if (mbedtls_cipher_set_iv(&ctx->ctx, iv, ivLength) != 0) {
                return false;
            }

            mbedtls_cipher_reset(&ctx->ctx);
        }

        if (flags & CIPHER_FLAG_PAD_TO_BLOCK_SIZE) {
            inputDataLength = addPkcs7PaddingInPlace(inputData, inputDataLength);
        }

        if (mbedtls_cipher_update(&ctx->ctx, inputData, inputDataLength, outputData, &outLength) != 0) {
            return false;
        }

        if (flags & CIPHER_FLAG_FINISH) {
            size_t finishLength;

            if (mbedtls_cipher_finish(&ctx->ctx, &outputData[outLength], &finishLength) != 0) {
                return false;
            }

            outLength += finishLength;
        }
    }

    *outputDataLength = outLength;
    return true;
#else
    LC_ASSERT(keyLength == 16);

    if (algorithm == ALGORITHM_AES_GCM) {
        LC_ASSERT(tag != NULL);
        LC_ASSERT(tagLength > 0);

        if (!ctx->initialized || (flags & CIPHER_FLAG_RESET_IV)) {
            // Perform a full initialization. This codepath also allows
            // us to change the IV length if required.
            if (EVP_EncryptInit_ex(ctx->ctx, EVP_aes_128_gcm(), NULL, NULL, NULL) != 1) {
                return false;
            }

            if (EVP_CIPHER_CTX_ctrl(ctx->ctx, EVP_CTRL_GCM_SET_IVLEN, ivLength, NULL) != 1) {
                return false;
            }

            if (EVP_EncryptInit_ex(ctx->ctx, NULL, NULL, key, iv) != 1) {
                return false;
            }

            ctx->initialized = true;
        }
        else {
            // Calling with cipher == NULL results in a parameter change
            // without requiring a reallocation of the internal cipher ctx.
            if (EVP_EncryptInit_ex(ctx->ctx, NULL, NULL, NULL, iv) != 1) {
                return false;
            }
        }
    }
    else if (algorithm == ALGORITHM_AES_CBC) {
        LC_ASSERT(tag == NULL);
        LC_ASSERT(tagLength == 0);

        if (!ctx->initialized) {
            // Perform a full initialization
            if (EVP_EncryptInit_ex(ctx->ctx, EVP_aes_128_cbc(), NULL, key, iv) != 1) {
                return false;
            }

            ctx->initialized = true;
        }
        else if (flags & CIPHER_FLAG_RESET_IV) {
            // Calling with cipher == NULL results in a parameter change
            // without requiring a reallocation of the internal cipher ctx.
            if (EVP_EncryptInit_ex(ctx->ctx, NULL, NULL, NULL, iv) != 1) {
                return false;
            }
        }

        if (flags & CIPHER_FLAG_PAD_TO_BLOCK_SIZE) {
            inputDataLength = addPkcs7PaddingInPlace(inputData, inputDataLength);
        }
    }
    else {
        LC_ASSERT(false);
        return false;
    }

    if (EVP_EncryptUpdate(ctx->ctx, outputData, outputDataLength, inputData, inputDataLength) != 1) {
        return false;
    }

    if (algorithm == ALGORITHM_AES_GCM) {
        int len;

        // GCM encryption won't ever fill ciphertext here but we have to call it anyway
        if (EVP_EncryptFinal_ex(ctx->ctx, outputData, &len) != 1) {
            return false;
        }
        LC_ASSERT(len == 0);

        if (EVP_CIPHER_CTX_ctrl(ctx->ctx, EVP_CTRL_GCM_GET_TAG, tagLength, tag) != 1) {
            return false;
        }
    }
    else if (flags & CIPHER_FLAG_FINISH) {
        int len;

        if (EVP_EncryptFinal_ex(ctx->ctx, &outputData[*outputDataLength], &len) != 1) {
            return false;
        }

        *outputDataLength += len;
    }

    return true;
#endif
}

// When CBC is used, outputData buffer must be allocated such that the buffer length is
// at least ROUND_TO_PKCS7_PADDED_LEN(inputDataLength) to allow room for PKCS7 padding.
// For GCM, the IV can change from message to message without CIPHER_FLAG_RESET_IV.
// CIPHER_FLAG_RESET_IV is only required for GCM when the IV length changes.
// Changing the key between encrypt/decrypt calls on a single context is not supported.
bool PltDecryptMessage(PPLT_CRYPTO_CONTEXT ctx, int algorithm, int flags,
                       unsigned char* key, int keyLength,
                       unsigned char* iv, int ivLength,
                       unsigned char* tag, int tagLength,
                       unsigned char* inputData, int inputDataLength,
                       unsigned char* outputData, int* outputDataLength) {
#ifdef USE_MBEDTLS
    mbedtls_cipher_mode_t cipherMode;
    size_t outLength;

    switch (algorithm) {
    case ALGORITHM_AES_CBC:
        LC_ASSERT(tag == NULL);
        LC_ASSERT(tagLength == 0);
        cipherMode = MBEDTLS_MODE_CBC;
        break;
    case ALGORITHM_AES_GCM:
        LC_ASSERT(tag != NULL);
        LC_ASSERT(tagLength > 0);
        cipherMode = MBEDTLS_MODE_GCM;
        break;
    default:
        LC_ASSERT(false);
        return false;
    }

    if (!ctx->initialized) {
        if (mbedtls_cipher_setup(&ctx->ctx, mbedtls_cipher_info_from_values(MBEDTLS_CIPHER_ID_AES, keyLength * 8, cipherMode)) != 0) {
            return false;
        }

        if (mbedtls_cipher_setkey(&ctx->ctx, key, keyLength * 8, MBEDTLS_DECRYPT) != 0) {
            return false;
        }

        ctx->initialized = true;
    }

    if (tag != NULL) {
#ifdef USE_MBEDTLS_CRYPTO_EXT
        // We only support 16 bytes sized tag
        LC_ASSERT(tagLength == 16);
        // Assume inputData is right after tag
        LC_ASSERT(inputData == tag + tagLength);
#ifndef LC_DEBUG
        if (tagLength != 16 || inputData != tag + tagLength) {
            return false;
        }
#endif
        unsigned char * encryptedData = tag;
        size_t encryptedDataLen = inputDataLength + tagLength;
        unsigned char tagTemp[16];
        // Copy the tag to temp buffer
        memcpy(tagTemp, encryptedData, tagLength);
        // Move ciphertext to the beginning
        memmove(encryptedData, encryptedData + tagLength, inputDataLength);
        // Copy back tag to the end
        memcpy(encryptedData + inputDataLength, tagTemp, tagLength);
        if (mbedtls_cipher_auth_decrypt_ext(&ctx->ctx, iv, ivLength, NULL, 0, encryptedData, encryptedDataLen,
                                            outputData, inputDataLength, &outLength, tagLength) != 0) {
            return false;
        }
#else
        if (mbedtls_cipher_auth_decrypt(&ctx->ctx, iv, ivLength, NULL, 0, inputData, inputDataLength, outputData, &outLength, tag, tagLength) != 0) {
            return false;
        }
#endif
    }
    else {
        if (flags & CIPHER_FLAG_RESET_IV) {
            if (mbedtls_cipher_set_iv(&ctx->ctx, iv, ivLength) != 0) {
                return false;
            }

            mbedtls_cipher_reset(&ctx->ctx);
        }

        if (mbedtls_cipher_update(&ctx->ctx, inputData, inputDataLength, outputData, &outLength) != 0) {
            return false;
        }

        if (flags & CIPHER_FLAG_FINISH) {
            size_t finishLength;

            if (mbedtls_cipher_finish(&ctx->ctx, &outputData[outLength], &finishLength) != 0) {
                return false;
            }

            outLength += finishLength;
        }
    }

    *outputDataLength = outLength;
    return true;
#else
    LC_ASSERT(keyLength == 16);

    if (algorithm == ALGORITHM_AES_GCM) {
        LC_ASSERT(tag != NULL);
        LC_ASSERT(tagLength > 0);

        if (!ctx->initialized || (flags & CIPHER_FLAG_RESET_IV)) {
            // Perform a full initialization. This codepath also allows
            // us to change the IV length if required.
            if (EVP_DecryptInit_ex(ctx->ctx, EVP_aes_128_gcm(), NULL, NULL, NULL) != 1) {
                return false;
            }

            if (EVP_CIPHER_CTX_ctrl(ctx->ctx, EVP_CTRL_GCM_SET_IVLEN, ivLength, NULL) != 1) {
                return false;
            }

            if (EVP_DecryptInit_ex(ctx->ctx, NULL, NULL, key, iv) != 1) {
                return false;
            }

            ctx->initialized = true;
        }
        else {
            // Calling with cipher == NULL results in a parameter change
            // without requiring a reallocation of the internal cipher ctx.
            if (EVP_DecryptInit_ex(ctx->ctx, NULL, NULL, NULL, iv) != 1) {
                return false;
            }
        }
    }
    else if (algorithm == ALGORITHM_AES_CBC) {
        LC_ASSERT(tag == NULL);
        LC_ASSERT(tagLength == 0);

        if (!ctx->initialized) {
            // Perform a full initialization
            if (EVP_DecryptInit_ex(ctx->ctx, EVP_aes_128_cbc(), NULL, key, iv) != 1) {
                return false;
            }

            ctx->initialized = true;
        }
        else if (flags & CIPHER_FLAG_RESET_IV) {
            // Calling with cipher == NULL results in a parameter change
            // without requiring a reallocation of the internal cipher ctx.
            if (EVP_DecryptInit_ex(ctx->ctx, NULL, NULL, NULL, iv) != 1) {
                return false;
            }
        }
    }
    else {
        LC_ASSERT(false);
        return false;
    }

    if (EVP_DecryptUpdate(ctx->ctx, outputData, outputDataLength, inputData, inputDataLength) != 1) {
        return false;
    }

    if (algorithm == ALGORITHM_AES_GCM) {
        int len;

        // Set the GCM tag before calling EVP_DecryptFinal_ex()
        if (EVP_CIPHER_CTX_ctrl(ctx->ctx, EVP_CTRL_GCM_SET_TAG, tagLength, tag) != 1) {
            return false;
        }

        // GCM will never have additional plaintext here, but we need to call it to
        // ensure that the GCM authentication tag is correct for this data.
        if (EVP_DecryptFinal_ex(ctx->ctx, outputData, &len) != 1) {
            return false;
        }
        LC_ASSERT(len == 0);
    }
    else if (flags & CIPHER_FLAG_FINISH) {
        int len;

        if (EVP_DecryptFinal_ex(ctx->ctx, &outputData[*outputDataLength], &len) != 1) {
            return false;
        }

        *outputDataLength += len;
    }

    return true;
#endif
}

PPLT_CRYPTO_CONTEXT PltCreateCryptoContext(void) {
    PPLT_CRYPTO_CONTEXT ctx = malloc(sizeof(*ctx));
    if (!ctx) {
        return NULL;
    }

    ctx->initialized = false;

#ifdef USE_MBEDTLS
    mbedtls_cipher_init(&ctx->ctx);
#else
    ctx->ctx = EVP_CIPHER_CTX_new();
    if (!ctx->ctx) {
        free(ctx);
        return NULL;
    }
#endif

    return ctx;
}

void PltDestroyCryptoContext(PPLT_CRYPTO_CONTEXT ctx) {
#ifdef USE_MBEDTLS
    mbedtls_cipher_free(&ctx->ctx);
#else
    EVP_CIPHER_CTX_free(ctx->ctx);
#endif
    free(ctx);
}

void PltGenerateRandomData(unsigned char* data, int length) {
#ifdef USE_MBEDTLS
    // FIXME: This is not thread safe...
    if (!RandomStateInitialized) {
        mbedtls_entropy_init(&EntropyContext);
        mbedtls_ctr_drbg_init(&CtrDrbgContext);
        if (mbedtls_ctr_drbg_seed(&CtrDrbgContext, mbedtls_entropy_func, &EntropyContext, NULL, 0) != 0) {
            // Nothing we can really do here...
            Limelog("Seeding MbedTLS random number generator failed!\n");
            LC_ASSERT(false);
            return;
        }

        RandomStateInitialized = true;
    }

    mbedtls_ctr_drbg_random(&CtrDrbgContext, data, length);
#else
    RAND_bytes(data, length);
#endif
}

bool PltEncryptAesEcbBlock(const unsigned char* key, int keyLength,
                           const unsigned char* inputBlock, unsigned char* outputBlock) {
    if (!key || !inputBlock || !outputBlock || keyLength != 16) {
        return false;
    }
#ifdef USE_MBEDTLS
    mbedtls_cipher_context_t c;
    mbedtls_cipher_init(&c);
    size_t olen = 0;
    size_t flen = 0;
    bool ok =
        mbedtls_cipher_setup(&c, mbedtls_cipher_info_from_values(MBEDTLS_CIPHER_ID_AES, keyLength * 8, MBEDTLS_MODE_ECB)) == 0 &&
        mbedtls_cipher_setkey(&c, key, keyLength * 8, MBEDTLS_ENCRYPT) == 0 &&
        mbedtls_cipher_update(&c, inputBlock, 16, outputBlock, &olen) == 0 &&
        olen == 16 &&
        mbedtls_cipher_finish(&c, outputBlock + olen, &flen) == 0;
    mbedtls_cipher_free(&c);
    return ok;
#else
    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        return false;
    }
    int outLen = 0;
    int finalLen = 0;
    bool ok =
        EVP_EncryptInit_ex(ctx, EVP_aes_128_ecb(), NULL, key, NULL) == 1 &&
        EVP_CIPHER_CTX_set_padding(ctx, 0) == 1 &&
        EVP_EncryptUpdate(ctx, outputBlock, &outLen, inputBlock, 16) == 1 &&
        outLen == 16 &&
        EVP_EncryptFinal_ex(ctx, outputBlock + outLen, &finalLen) == 1;
    EVP_CIPHER_CTX_free(ctx);
    return ok;
#endif
}

bool PltEncryptAesGcmAad(const unsigned char* key, int keyLength,
                         const unsigned char* iv, int ivLength,
                         const unsigned char* aad, int aadLength,
                         const unsigned char* plaintext, int plaintextLength,
                         unsigned char* tagOut, int tagLength,
                         unsigned char* ciphertextOut) {
    if (!key || !iv || !tagOut || !ciphertextOut || keyLength != 16 || ivLength <= 0 ||
        aadLength < 0 || plaintextLength < 0 || tagLength <= 0 || tagLength > 16 ||
        (aadLength > 0 && !aad) || (plaintextLength > 0 && !plaintext)) {
        return false;
    }
#ifdef USE_MBEDTLS
    mbedtls_cipher_context_t c;
    mbedtls_cipher_init(&c);
    bool ok =
        mbedtls_cipher_setup(&c, mbedtls_cipher_info_from_values(MBEDTLS_CIPHER_ID_AES, keyLength * 8, MBEDTLS_MODE_GCM)) == 0 &&
        mbedtls_cipher_setkey(&c, key, keyLength * 8, MBEDTLS_ENCRYPT) == 0;
    if (ok) {
#ifdef USE_MBEDTLS_CRYPTO_EXT
        unsigned char* combined = (unsigned char*)malloc((size_t)(plaintextLength + tagLength));
        size_t olen = 0;
        ok = combined != NULL &&
             mbedtls_cipher_auth_encrypt_ext(&c, iv, (size_t)ivLength, aad, (size_t)aadLength,
                                             plaintext, (size_t)plaintextLength,
                                             combined, (size_t)(plaintextLength + tagLength),
                                             &olen, (size_t)tagLength) == 0 &&
             olen == (size_t)(plaintextLength + tagLength);
        if (ok) {
            if (plaintextLength > 0) {
                memcpy(ciphertextOut, combined, (size_t)plaintextLength);
            }
            memcpy(tagOut, combined + plaintextLength, (size_t)tagLength);
        }
        free(combined);
#else
        size_t olen = 0;
        ok = mbedtls_cipher_auth_encrypt(&c, iv, (size_t)ivLength, aad, (size_t)aadLength,
                                         plaintext, (size_t)plaintextLength,
                                         ciphertextOut, &olen, tagOut, (size_t)tagLength) == 0 &&
             olen == (size_t)plaintextLength;
#endif
    }
    mbedtls_cipher_free(&c);
    return ok;
#else
    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        return false;
    }
    int len = 0;
    int total = 0;
    bool ok =
        EVP_EncryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL) == 1 &&
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, ivLength, NULL) == 1 &&
        EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv) == 1;
    if (ok && aadLength > 0) {
        ok = EVP_EncryptUpdate(ctx, NULL, &len, aad, aadLength) == 1;
    }
    if (ok && plaintextLength > 0) {
        ok = EVP_EncryptUpdate(ctx, ciphertextOut, &len, plaintext, plaintextLength) == 1;
        total = len;
    }
    if (ok) {
        ok = EVP_EncryptFinal_ex(ctx, ciphertextOut + total, &len) == 1 &&
             (total + len) == plaintextLength &&
             EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, tagLength, tagOut) == 1;
    }
    EVP_CIPHER_CTX_free(ctx);
    return ok;
#endif
}

bool PltDecryptAesGcmAad(const unsigned char* key, int keyLength,
                         const unsigned char* iv, int ivLength,
                         const unsigned char* aad, int aadLength,
                         const unsigned char* ciphertext, int ciphertextLength,
                         const unsigned char* tag, int tagLength,
                         unsigned char* plaintextOut) {
    if (!key || !iv || !tag || !plaintextOut || keyLength != 16 || ivLength <= 0 ||
        aadLength < 0 || ciphertextLength < 0 || tagLength <= 0 || tagLength > 16 ||
        (aadLength > 0 && !aad) || (ciphertextLength > 0 && !ciphertext)) {
        return false;
    }
#ifdef USE_MBEDTLS
    mbedtls_cipher_context_t c;
    mbedtls_cipher_init(&c);
    bool ok =
        mbedtls_cipher_setup(&c, mbedtls_cipher_info_from_values(MBEDTLS_CIPHER_ID_AES, keyLength * 8, MBEDTLS_MODE_GCM)) == 0 &&
        mbedtls_cipher_setkey(&c, key, keyLength * 8, MBEDTLS_DECRYPT) == 0;
    if (ok) {
#ifdef USE_MBEDTLS_CRYPTO_EXT
        unsigned char* combined = (unsigned char*)malloc((size_t)(ciphertextLength + tagLength));
        size_t olen = 0;
        if (combined != NULL) {
            if (ciphertextLength > 0) {
                memcpy(combined, ciphertext, (size_t)ciphertextLength);
            }
            memcpy(combined + ciphertextLength, tag, (size_t)tagLength);
            ok = mbedtls_cipher_auth_decrypt_ext(&c, iv, (size_t)ivLength, aad, (size_t)aadLength,
                                                 combined, (size_t)(ciphertextLength + tagLength),
                                                 plaintextOut, (size_t)ciphertextLength,
                                                 &olen, (size_t)tagLength) == 0 &&
                 olen == (size_t)ciphertextLength;
            free(combined);
        }
        else {
            ok = false;
        }
#else
        size_t olen = 0;
        ok = mbedtls_cipher_auth_decrypt(&c, iv, (size_t)ivLength, aad, (size_t)aadLength,
                                         ciphertext, (size_t)ciphertextLength,
                                         plaintextOut, &olen, tag, (size_t)tagLength) == 0 &&
             olen == (size_t)ciphertextLength;
#endif
    }
    mbedtls_cipher_free(&c);
    return ok;
#else
    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        return false;
    }
    int len = 0;
    int total = 0;
    bool ok =
        EVP_DecryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL) == 1 &&
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, ivLength, NULL) == 1 &&
        EVP_DecryptInit_ex(ctx, NULL, NULL, key, iv) == 1;
    if (ok && aadLength > 0) {
        ok = EVP_DecryptUpdate(ctx, NULL, &len, aad, aadLength) == 1;
    }
    if (ok && ciphertextLength > 0) {
        ok = EVP_DecryptUpdate(ctx, plaintextOut, &len, ciphertext, ciphertextLength) == 1;
        total = len;
    }
    if (ok) {
        ok = EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, tagLength, (void*)tag) == 1 &&
             EVP_DecryptFinal_ex(ctx, plaintextOut + total, &len) > 0 &&
             (total + len) == ciphertextLength;
    }
    EVP_CIPHER_CTX_free(ctx);
    return ok;
#endif
}
