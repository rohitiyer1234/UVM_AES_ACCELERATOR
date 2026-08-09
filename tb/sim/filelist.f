// ============================================================================
//  tb/sim/filelist.f
//
//  Compile order for both Vivado XSIM (`xvlog -f filelist.f`) and ModelSim
//  (`vlog -f filelist.f`).  Each file is rooted at the workspace root.
//
//  Order is critical:
//      1.  Package (aes_pkg)
//      2.  Sub-modules (S-box / ShiftRows / MixColumns ...)
//      3.  Pipeline + key system + ghash + orchestrator
//      4.  rtl_fixed/*  (override originals where applicable)
//      5.  TB package + interfaces
//      6.  TB top (which `include`s the class library)
// ============================================================================

+incdir+../../tb
+incdir+../../tb/interfaces
+incdir+../../tb/transactions
+incdir+../../tb/refmodel
+incdir+../../tb/drivers
+incdir+../../tb/monitors
+incdir+../../tb/scoreboards
+incdir+../../tb/coverage
+incdir+../../tb/env
+incdir+../../tb/tests

// ---- Common helpers (original RTL - unchanged) ----
../../aes_pkg.sv
../../SubBytes.sv
../../ShiftRows.sv
../../MixColumns.sv
../../InvSubBytes.sv
../../InvShiftRows.sv
../../InvMixColumns.sv

// ---- AES pipelines ----
../../AES_Encrypt_Pipe.sv
../../AES_Decrypt_Pipe.sv

// ---- Key subsystem ----
../../AES_Key_Expansion_128.sv
../../key_fifo.sv
../../key_controller.sv
../../keymem_dual.sv
../../key_system_top.sv

// ---- GCM helpers ----
../../gcm_ctr_gen.sv
../../ghash_gf128_mul.sv
../../ghash_gf128_mul_4b.sv
../../ghash_core.sv

// ---- FIXED RTL  (these REPLACE the originals - compile last so they win) ----
../../rtl_fixed/aes_mode_datapath.sv
../../rtl_fixed/gcm_orchestrator.sv
../../rtl_fixed/aes_top.sv

// ---- TB package + interfaces ----
../../tb/aes_tb_pkg.sv
../../tb/interfaces/aes_ctrl_if.sv
../../tb/interfaces/aes_stream_if.sv
../../tb/interfaces/key_if.sv
../../tb/interfaces/gcm_if.sv

// ---- Assertions (binds itself to aes_top) ----
../../tb/assertions/aes_assertions.sv

// ---- TB top (includes the class library) ----
../../tb/top/tb_aes_top.sv
