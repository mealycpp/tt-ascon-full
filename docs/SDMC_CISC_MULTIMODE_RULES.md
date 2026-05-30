# SDMC-CISC Multimode Architecture Rules

This branch extends the GDS-passing AEAD single-UART rescue design.

Locked baseline:
- Local branch: sdmc-aead-single-uart-gds-pass
- Local tag: sdmc-aead-single-uart-gds-pass-26667052221
- GitHub Actions GDS run: 26667052221
- AEAD official ASCON-C massive validation: PASS
- Cocotb RTL test: PASS
- Viewer/precheck/GDS: PASS

Hard architecture rules:
1. Keep one RX UART.
2. Keep one TX UART.
3. Keep one command-framed byte stream.
4. Keep the existing depth-4 output token queue.
5. Do not return to three UARTs.
6. Do not create separate key/nonce/AD/message/tag/custom/message FIFOs.
7. Do not create deep bulk FIFOs.
8. Use FIFO/skid only as timing isolation.
9. Add HASH/XOF/CXOF/XOF-chain/CXOF-chain as CISC microprogram routines, not as independent wide engines.
10. Reuse the shared ASCON datapath/microsequencer style.
11. Validate every mode against official or derived KATs before GDS.
12. Run GDS after each major mode addition.

Allowed storage:
- key/nonce registers for AEAD
- one input token/packer stage
- local counters
- local 256-bit chain digest register for XOF/CXOF feedback
- depth-4 output token queue

Forbidden storage:
- full AD FIFO
- full message FIFO
- separate semantic FIFOs
- duplicated mode-specific ASCON engines unless explicitly proven necessary
