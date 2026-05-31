SDMC-CISC ASCON TinyTapeout Evidence Bundle
Run ID: 26702939008
Branch: sdmc-cisc-multimode-stream
Commit: 4bcf1e0c0c91e3e6bad0b48a13900d9f69bd2988

Result:
- GitHub test workflow: PASS
- GitHub docs workflow: PASS
- GitHub GDS workflow: PASS
- TinyTapeout gl_test: PASS

Key physical result:
- Utilisation: 58.601%
- Routed wire length: 2,041,630 um

Architecture:
- SDMC-CISC ASCON-family processor
- One shared ASCON permutation datapath
- AEAD, HASH, XOF, CXOF, XOF-chain, and CXOF-chain routed through the shared architecture
- No duplicated ASCON permutation engines in the GDS source list

Notes:
- Synthesis warnings about replacing small RTL memories with registers are expected.
- The arrays are shallow staging/caching structures and do not require SRAM macros.
