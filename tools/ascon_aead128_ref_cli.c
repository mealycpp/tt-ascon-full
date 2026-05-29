#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

int crypto_aead_encrypt(
    unsigned char *c, unsigned long long *clen,
    const unsigned char *m, unsigned long long mlen,
    const unsigned char *ad, unsigned long long adlen,
    const unsigned char *nsec,
    const unsigned char *npub,
    const unsigned char *k
);

int crypto_aead_decrypt(
    unsigned char *m, unsigned long long *mlen,
    unsigned char *nsec,
    const unsigned char *c, unsigned long long clen,
    const unsigned char *ad, unsigned long long adlen,
    const unsigned char *npub,
    const unsigned char *k
);

static int hexval(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static unsigned char *parse_hex(const char *s, size_t *out_len) {
    size_t n = strlen(s);
    if (n % 2 != 0) {
        fprintf(stderr, "hex length must be even\n");
        exit(2);
    }

    *out_len = n / 2;
    unsigned char *buf = NULL;

    if (*out_len == 0) {
        return NULL;
    }

    buf = (unsigned char *)malloc(*out_len);
    if (!buf) {
        fprintf(stderr, "malloc failed\n");
        exit(2);
    }

    for (size_t i = 0; i < *out_len; i++) {
        int hi = hexval(s[2 * i]);
        int lo = hexval(s[2 * i + 1]);
        if (hi < 0 || lo < 0) {
            fprintf(stderr, "invalid hex char\n");
            exit(2);
        }
        buf[i] = (unsigned char)((hi << 4) | lo);
    }

    return buf;
}

static void print_hex(const unsigned char *buf, size_t n) {
    for (size_t i = 0; i < n; i++) {
        printf("%02x", buf[i]);
    }
    printf("\n");
}

int main(int argc, char **argv) {
    if (argc != 6) {
        fprintf(stderr, "usage:\n");
        fprintf(stderr, "  %s enc key_hex nonce_hex ad_hex msg_hex\n", argv[0]);
        fprintf(stderr, "  %s dec key_hex nonce_hex ad_hex ct_tag_hex\n", argv[0]);
        return 2;
    }

    const char *mode = argv[1];

    size_t klen = 0, nlen = 0, adlen = 0, inlen = 0;
    unsigned char *key = parse_hex(argv[2], &klen);
    unsigned char *nonce = parse_hex(argv[3], &nlen);
    unsigned char *ad = parse_hex(argv[4], &adlen);
    unsigned char *in = parse_hex(argv[5], &inlen);

    if (klen != 16 || nlen != 16) {
        fprintf(stderr, "key and nonce must be 16 bytes\n");
        return 2;
    }

    if (strcmp(mode, "enc") == 0) {
        unsigned char *out = (unsigned char *)malloc(inlen + 32);
        unsigned long long outlen = 0;
        if (!out) return 2;

        int rc = crypto_aead_encrypt(
            out, &outlen,
            in, (unsigned long long)inlen,
            ad, (unsigned long long)adlen,
            NULL,
            nonce,
            key
        );

        if (rc != 0) {
            fprintf(stderr, "encrypt failed rc=%d\n", rc);
            return 1;
        }

        print_hex(out, (size_t)outlen);
        free(out);
    } else if (strcmp(mode, "dec") == 0) {
        unsigned char *out = (unsigned char *)malloc(inlen + 1);
        unsigned long long outlen = 0;
        if (!out) return 2;

        int rc = crypto_aead_decrypt(
            out, &outlen,
            NULL,
            in, (unsigned long long)inlen,
            ad, (unsigned long long)adlen,
            nonce,
            key
        );

        if (rc != 0) {
            fprintf(stderr, "decrypt failed rc=%d\n", rc);
            return 1;
        }

        print_hex(out, (size_t)outlen);
        free(out);
    } else {
        fprintf(stderr, "unknown mode: %s\n", mode);
        return 2;
    }

    free(key);
    free(nonce);
    free(ad);
    free(in);
    return 0;
}
