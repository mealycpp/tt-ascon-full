#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int ascon_xof(uint8_t* out, uint64_t outlen, const uint8_t* in, uint64_t inlen);

static int hexval(int c) {
    if ('0' <= c && c <= '9') return c - '0';
    if ('a' <= c && c <= 'f') return c - 'a' + 10;
    if ('A' <= c && c <= 'F') return c - 'A' + 10;
    return -1;
}

static uint8_t* parse_hex(const char* s, size_t* out_len) {
    size_t n = strlen(s);
    if (n % 2) return NULL;
    uint8_t* b = (uint8_t*)calloc(n / 2 ? n / 2 : 1, 1);
    if (!b) return NULL;
    for (size_t i = 0; i < n / 2; i++) {
        int hi = hexval(s[2*i]);
        int lo = hexval(s[2*i + 1]);
        if (hi < 0 || lo < 0) {
            free(b);
            return NULL;
        }
        b[i] = (uint8_t)((hi << 4) | lo);
    }
    *out_len = n / 2;
    return b;
}

int main(int argc, char** argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s <outlen> <msg_hex>\n", argv[0]);
        return 2;
    }

    uint64_t outlen = strtoull(argv[1], NULL, 0);
    size_t msg_len = 0;
    uint8_t* msg = parse_hex(argv[2], &msg_len);
    uint8_t* out = (uint8_t*)calloc(outlen ? outlen : 1, 1);

    if (!msg || !out) return 3;

    int rc = ascon_xof(out, outlen, msg, msg_len);
    if (rc != 0) return 4;

    for (uint64_t i = 0; i < outlen; i++) {
        printf("%02x", out[i]);
    }
    printf("\n");

    free(msg);
    free(out);
    return 0;
}
