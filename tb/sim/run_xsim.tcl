# =========================================================================
#  tb/sim/run_xsim.tcl
#
#  Vivado XSIM runscript.  Invoked by the Makefile:
#      xsim work.tb_aes_top --tclbatch run_xsim.tcl --testplusarg TEST=$TEST
# =========================================================================
log_wave -recursive *
run all
quit
