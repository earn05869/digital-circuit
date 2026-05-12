IVERILOG ?= iverilog
VVP ?= vvp

BUILD_DIR := build
SIM_DIR := $(BUILD_DIR)/sim
VCD_DIR := $(BUILD_DIR)/vcd

TB_FILES := $(wildcard tb/tb_*.v)
TESTS := $(patsubst tb/tb_%.v,%,$(TB_FILES))

# Compile all DUT sources for each testbench.
SRC_FILES := \
	$(filter-out tb/%,$(wildcard *.v)) \
	$(wildcard share/*.v) \
	$(wildcard master/*.v) \
	$(wildcard slave/*.v)

.PHONY: all list clean

all: $(addprefix test-,$(TESTS))

list:
	@echo "Available tests:"
	@$(foreach t,$(TESTS),echo "  $(t)";)

$(SIM_DIR) $(VCD_DIR):
	@mkdir -p "$@"

test-%: $(SIM_DIR) $(VCD_DIR)
	@echo "==> Compiling tb_$*"
	@$(IVERILOG) -g2012 -s tb_$* -o "$(SIM_DIR)/$*.out" $(SRC_FILES) $(EXTRA_SRC_$*) "tb/tb_$*.v"
	@echo "==> Running tb_$*"
	@cd "$(VCD_DIR)" && $(VVP) "../sim/$*.out"
	@echo "==> VCD written to $(VCD_DIR)/"

clean:
	@rm -rf "$(BUILD_DIR)"
