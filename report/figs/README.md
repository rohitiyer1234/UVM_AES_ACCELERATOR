# Figure Placeholders

This directory holds the rendered figures referenced from `aes_report.tex`.
Each figure path that is delivered as a placeholder describes (in its caption)
what the rendered illustration should contain.  Recreate using
TikZ/draw.io/Inkscape and save as `.pdf` for inclusion via `\includegraphics`.

| File                | Content                                                       |
|---------------------|---------------------------------------------------------------|
| `fig_arch.pdf`      | Top-level block diagram of the accelerator                    |
| `fig_pipeline.pdf`  | 11-stage AES-128 encrypt pipeline                              |
| `fig_decrypt.pdf`   | 10-stage AES-128 decrypt pipeline                              |
| `fig_keysys.pdf`    | Dual-bank key subsystem (FIFO -> controller -> expansion -> dual bank) |
| `fig_gcm_fsm.pdf`   | GCM orchestrator state machine                                |
| `fig_tb_arch.pdf`   | Pure-SV verification environment architecture                  |
| `fig_uvm_map.pdf`   | UVM equivalence diagram                                       |
| `wave_ecb.pdf`      | Waveform: simple ECB stream                                   |
| `wave_cbc_serial.pdf` | Waveform: CBC encrypt feedback-serialised handshake          |
| `wave_gcm_phases.pdf` | Waveform: GCM session showing H-gen, J0-gen, AAD, payload, len, tag |
