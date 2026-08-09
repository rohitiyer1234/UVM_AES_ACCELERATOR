# =============================================================================
#  tb/sim/Makefile
#
#  Top-level driver for both Vivado XSIM and ModelSim flows.
#
#  Examples:
#    make TEST=test_smoke
#    make TEST=test_random_stress SEED=42
#    make SIM=vsim TEST=test_backpressure
#    make all
#    make clean
# =============================================================================

SIM   ?= xsim
TEST  ?= test_smoke
SEED  ?= 12345
WAVE  ?= 0

PLUSARGS = +TEST=$(TEST) +SEED=$(SEED)
ifeq ($(WAVE),1)
  PLUSARGS += +WAVE
endif

ALL_TESTS = test_smoke test_random_stress test_backpressure test_reset \
            test_mode_switch test_long_stream test_gcm_stress test_dual_bank

# =============================================================================
#  Vivado XSIM flow
# =============================================================================
ifeq ($(SIM),xsim)

XVLOG_FLAGS = -sv --nolog
XELAB_FLAGS = -relax --nolog --debug typical
XSIM_FLAGS  = --nolog --runall

run: compile elab
	xsim work.tb_aes_top $(XSIM_FLAGS) --testplusarg "TEST=$(TEST)" \
	     --testplusarg "SEED=$(SEED)"

compile:
	xvlog $(XVLOG_FLAGS) -f filelist.f

elab:
	xelab $(XELAB_FLAGS) tb_aes_top -s work.tb_aes_top

clean:
	rm -rf xsim.dir xelab.* xvlog.* webtalk* *.jou *.log *.pb *.wdb

endif

# =============================================================================
#  ModelSim flow
# =============================================================================
ifeq ($(SIM),vsim)

run: compile
	vsim -c -do "run_modelsim.do" $(PLUSARGS) work.tb_aes_top

compile:
	vlib work
	vlog -sv -f filelist.f

clean:
	rm -rf work transcript *.wlf *.vstf

endif

# =============================================================================
#  Convenience: run every test, abort on first failure
# =============================================================================
all:
	@for t in $(ALL_TESTS); do \
	  echo "===== running $$t =====" ; \
	  $(MAKE) TEST=$$t || exit 1 ; \
	done
