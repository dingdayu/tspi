# Makefile — TaishanPi RK3566 One-KVM appliance
# ---------------------------------------------------------------------------
# Discoverable top-level interface (AGENTS.md section 9).
# Host-side targets run directly; in-builder targets are wrapped through
# scripts/host/enter-builder.sh so a privileged container is used implicitly.
# ---------------------------------------------------------------------------

SHELL := /bin/bash
.DEFAULT_GOAL := help

PROJECT_ROOT := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
SCRIPTS := $(PROJECT_ROOT)/scripts

# Run a command inside the builder container (non-interactive).
IN_BUILDER := $(SCRIPTS)/host/enter-builder.sh --
# Run a command directly on the host.
HOST := $(PROJECT_ROOT)/scripts

.PHONY: help all doctor builder shell \
        sdk-check sdk-extract sdk-sync baseline \
        kernel-detect patch kernel-configure kernel kernel-verify \
        rootfs rootfs-customize rootfs-verify \
        image image-manifest \
        verify target-smoke clean

help: ## Show this help
	@echo "TaishanPi RK3566 One-KVM appliance — available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

## ----- Host environment ----------------------------------------------------

doctor: ## Validate the host (docker, git, sdk presence, config)
	@$(HOST)/host/doctor.sh

builder: ## Build the Ubuntu 22.04 builder container image
	@$(HOST)/host/build-builder.sh

shell: ## Enter an interactive privileged builder shell
	@$(HOST)/host/enter-builder.sh

## ----- SDK lifecycle -------------------------------------------------------

sdk-check: ## Detect SDK state and inspect the vendor tree
	@$(HOST)/sdk/inspect.sh

sdk-extract: ## Idempotently extract the downloaded multi-part SDK
	@$(IN_BUILDER) $(SCRIPTS)/sdk/extract.sh

sdk-sync: ## Idempotently sync the extracted tree (local .repo sync)
	@$(IN_BUILDER) $(SCRIPTS)/sdk/sync.sh

baseline: ## Smallest practical unmodified vendor baseline build
	@$(IN_BUILDER) $(SCRIPTS)/sdk/baseline-build.sh

## ----- Kernel / device tree ------------------------------------------------

kernel-detect: ## Detect the active TaishanPi board DTS + DWC3 node
	@$(HOST)/kernel/detect-board.sh

patch: ## Apply the DWC3 peripheral-mode patch (idempotent)
	@$(IN_BUILDER) $(SCRIPTS)/kernel/patch.sh

kernel-configure: ## Apply required kernel config fragment
	@$(IN_BUILDER) $(SCRIPTS)/kernel/configure.sh

kernel: patch kernel-configure ## Configure + build kernel/DTB + verify .config
	@$(IN_BUILDER) $(SCRIPTS)/kernel/build.sh
	@$(IN_BUILDER) $(SCRIPTS)/kernel/verify.sh

kernel-verify: ## Verify effective kernel .config / DTB DWC3 mode
	@$(IN_BUILDER) $(SCRIPTS)/kernel/verify.sh

## ----- Rootfs --------------------------------------------------------------

rootfs: ## Build + customize the Debian appliance rootfs
	@$(IN_BUILDER) $(SCRIPTS)/rootfs/build.sh

rootfs-customize: ## Re-run only the rootfs customization (existing unpacked tree) + repack
	@$(IN_BUILDER) env ROOTFS_CUSTOMIZE_ONLY=1 $(SCRIPTS)/rootfs/build.sh

rootfs-verify: ## Verify rootfs contents (ssh, NetworkManager, one-kvm, no docker)
	@$(HOST)/rootfs/verify.sh

## ----- Image ---------------------------------------------------------------

image: ## Package vendor images and collect artifacts into dist/
	@$(IN_BUILDER) $(SCRIPTS)/image/build.sh

image-manifest: ## Generate dist/MANIFEST.txt and dist/SHA256SUMS
	@$(HOST)/image/manifest.sh

## ----- Validation ----------------------------------------------------------

verify: ## Run all host/static validation gates
	@$(HOST)/verify/static.sh

target-smoke: ## Show how to run the on-device smoke test
	@echo "Copy scripts/verify/target-smoke.sh to the booted TaishanPi and run:"
	@echo "  sudo bash target-smoke.sh"

## ----- Pipeline ------------------------------------------------------------

all: doctor builder sdk-check ## Full pipeline (stops with guidance if SDK absent)
	@st=$$($(HOST)/host/doctor.sh --print-sdk-state 2>/dev/null || true); \
	 if [ "$$st" = "A" ]; then \
	   echo; echo "SDK absent — run: make sdk-extract && make sdk-sync after placing it."; \
	 else \
	   $(MAKE) baseline patch kernel rootfs image verify; \
	 fi

clean: ## Remove project build state (NOT the SDK or dist artifacts)
	@echo "Removing build/ ..."; rm -rf "$(PROJECT_ROOT)/build"; mkdir -p "$(PROJECT_ROOT)/build/logs"
	@echo "Done."
