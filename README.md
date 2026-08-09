# UVM AES Accelerator

### SystemVerilog AES-128 Hardware Accelerator + UVM Verification Environment

> ⚠️ **Work in progress.** This project is under active development and is **not yet complete or verified**. RTL modules, testbench components, and documentation in this repo may be partial, unstable, or subject to significant rework. Do not treat this as a finished or production-ready core.

---

## Overview

This repository implements an AES-128 hardware accelerator in SystemVerilog, covering the core encryption/decryption datapath, key expansion, and GCM/GHASH support, alongside a UVM-based verification environment.

Planned/in-progress scope includes:

- **Encrypt / decrypt pipelines** — `AES_Encrypt_Pipe.sv`, `AES_Decrypt_Pipe.sv`
- **Core AES transforms** — `SubBytes` / `InvSubBytes`, `ShiftRows` / `InvShiftRows`, `MixColumns` / `InvMixColumns`
- **Key management** — `AES_Key_Expansion_128.sv`, `key_controller.sv`, `key_fifo.sv`, `keymem_dual.sv`, `key_system_top.sv`
- **Mode support (GCM)** — `gcm_orchestrator.sv`, `gcm_ctr_gen.sv`, `ghash_core.sv`, `ghash_gf128_mul.sv` / `ghash_gf128_mul_4b.sv`
- **Top-level integration** — `aes_top.sv`, `aes_mode_datapath.sv`, `aes_pkg.sv`
- **Verification** — a `tb/` directory containing the UVM testbench environment (agents, sequences, scoreboard, etc.)
- **Documentation** — a `report/` directory for design/verification write-ups

## Current Status

- Core RTL modules for the AES datapath, key expansion, and GCM/GHASH path exist in `rtl_fixed/` and at the repo root.
- A UVM testbench structure is present under `tb/`.
- **Verification is incomplete.** Not all modules have passing, self-checking UVM tests yet, and integration between the datapath and the full UVM environment is still being debugged and expanded.
- Expect bugs, incomplete coverage, and interfaces that may still change.

## Roadmap

- [ ] Finish UVM agents/sequences for all datapath interfaces (encrypt, decrypt, key expansion, GCM)
- [ ] Build out functional coverage and close on all AES modes (ECB/CBC/CTR/CFB/OFB/GCM, as applicable)
- [ ] Add a scoreboard with a golden-model reference checker for all modes
- [ ] Regression run across directed + constrained-random sequences
- [ ] Write up final verification report in `report/`

## Notes

This README will be updated as the RTL stabilizes and the UVM environment reaches full coverage. Until then, treat all modules as pre-verification.
