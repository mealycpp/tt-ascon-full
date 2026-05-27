#ifndef CRYPTO_HASH_H
#define CRYPTO_HASH_H

int crypto_hash(unsigned char *out,
                const unsigned char *in,
                unsigned long long inlen);

#endif
