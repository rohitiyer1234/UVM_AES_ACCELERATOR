# =========================================================================
#  tb/sim/run_modelsim.do
#
#  ModelSim runscript.  Invoked by the Makefile:
#      vsim -do run_modelsim.do +TEST=$TEST +SEED=$SEED
# =========================================================================
onerror {resume}
run -all
quit -f
