
// ============================================================================
//  tb/aes_tb_pkg.sv
//
//  Testbench-wide types, knobs, ID allocator and structured-log macros.
//  Imported by every TB file (no DUT/RTL file imports this).
// ============================================================================
`timescale 1ns/1ps

package aes_tb_pkg;

    import aes_pkg::*;

    // -----------------------------------------------------------------
    // Verbosity levels (UVM-equivalent levels expressed as ints)
    // -----------------------------------------------------------------
    typedef enum int {
        VRB_NONE   = 0,
        VRB_LOW    = 100,
        VRB_MED    = 200,
        VRB_HIGH   = 300,
        VRB_DEBUG  = 400
    } verbosity_e;

    // -----------------------------------------------------------------
    // Global TB knobs - set by aes_config and read everywhere
    // -----------------------------------------------------------------
    int unsigned tb_verbosity   = VRB_LOW;
    int unsigned tb_max_errors  = 64;
    int unsigned tb_seed        = 32'hC0FFEE;

    // -----------------------------------------------------------------
    // Transaction ID allocator - monotonic across all transactions for
    // unambiguous cross-monitor correlation.
    // -----------------------------------------------------------------
    int unsigned tb_txn_counter = 0;

    function automatic int unsigned tb_next_id();
        tb_next_id = tb_txn_counter;
        tb_txn_counter++;
    endfunction

    // -----------------------------------------------------------------
    // Mismatch record for the scoreboard's structured printer
    // -----------------------------------------------------------------
    typedef struct {
        int unsigned id;
        realtime     t_in;
        realtime     t_out;
        aes_mode_e   mode;
        bit          enc_dec;
        aes_block_t  data_in;
        aes_block_t  iv_or_ctr;
        aes_block_t  exp_out;
        aes_block_t  dut_out;
        bit          bank_at_accept;
        bit  [1:0]   bank_valid_at_accept;
        bit  [1:0]   bank_busy_at_accept;
        int unsigned meta_count_at_accept;
        string       note;
    } txn_log_t;

    // -----------------------------------------------------------------
    // Pretty printers
    // -----------------------------------------------------------------
    function automatic string mode_name(aes_mode_e m);
        case (m)
            MODE_ECB: return "ECB";
            MODE_CBC: return "CBC";
            MODE_CFB: return "CFB";
            MODE_OFB: return "OFB";
            MODE_CTR: return "CTR";
            MODE_GCM: return "GCM";
            default : return "RSV";
        endcase
    endfunction

    function automatic string hex_block(aes_block_t b);
        return $sformatf("%032h", b);
    endfunction

    // Bit popcount on diff_xor (vendor-portable, no $countones in 1995-Verilog
    // tools - SV $countones works in xsim/vsim).
    function automatic int unsigned popcount128(aes_block_t v);
        int unsigned c = 0;
        for (int i = 0; i < 128; i++) if (v[i]) c++;
        return c;
    endfunction

    function automatic string format_mismatch(txn_log_t r);
        aes_block_t dx;
        string      s;
        dx = r.exp_out ^ r.dut_out;
        s  = "";
        s = {s, $sformatf("--- MISMATCH id=%0d mode=%s enc=%0d t_in=%0t t_out=%0t ---\n",
                          r.id, mode_name(r.mode), r.enc_dec, r.t_in, r.t_out)};
        s = {s, $sformatf("    data_in : 0x%s\n", hex_block(r.data_in))};
        s = {s, $sformatf("    iv/ctr  : 0x%s\n", hex_block(r.iv_or_ctr))};
        s = {s, $sformatf("    exp_out : 0x%s\n", hex_block(r.exp_out))};
        s = {s, $sformatf("    dut_out : 0x%s\n", hex_block(r.dut_out))};
        s = {s, $sformatf("    diff_xor: 0x%s (%0d bits differ)\n",
                          hex_block(dx), popcount128(dx))};
        s = {s, $sformatf("    bank_at_accept=%0d  bank_valid=%02b  bank_busy=%02b\n",
                          r.bank_at_accept, r.bank_valid_at_accept,
                          r.bank_busy_at_accept)};
        s = {s, $sformatf("    meta_count_at_accept=%0d\n", r.meta_count_at_accept)};
        if (r.note != "") s = {s, $sformatf("    note: %s\n", r.note)};
        return s;
    endfunction

endpackage : aes_tb_pkg

// ============================================================================
//  Structured log macros - cheap call sites, expand to $display only when
//  verbosity allows.  Compile-time constant comparison keeps overhead minimal.
// ============================================================================
`ifndef AES_TB_LOG_SV
`define AES_TB_LOG_SV

`define LOG_LOW(MSG)   do if (aes_tb_pkg::tb_verbosity >= aes_tb_pkg::VRB_LOW)   $display("[%0t] [%s] %s", $time, get_name(), MSG); while (0)
`define LOG_MED(MSG)   do if (aes_tb_pkg::tb_verbosity >= aes_tb_pkg::VRB_MED)   $display("[%0t] [%s] %s", $time, get_name(), MSG); while (0)
`define LOG_HIGH(MSG)  do if (aes_tb_pkg::tb_verbosity >= aes_tb_pkg::VRB_HIGH)  $display("[%0t] [%s] %s", $time, get_name(), MSG); while (0)
`define LOG_DEBUG(MSG) do if (aes_tb_pkg::tb_verbosity >= aes_tb_pkg::VRB_DEBUG) $display("[%0t] [%s] %s", $time, get_name(), MSG); while (0)
`define LOG_ERROR(MSG) $error("[%0t] [%s] %s", $time, get_name(), MSG)
`define LOG_FATAL(MSG) $fatal(1, "[%0t] [%s] %s", $time, get_name(), MSG)

`endif
