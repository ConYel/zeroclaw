# ─── ZeroClaw StageX Container ──────────────────────────────────────────────

IMAGE_NAME    = zeroclaw
IMAGE_TAG     = stagex
CONFIG_DIR   ?= $(HOME)/.zeroclaw
LLAMA_DIR    ?= $(HOME)/projects/llama.cpp

HIPFIRE_DIR  ?= $(HOME)/.hipfire
HIPFIRE_CLI  ?= $(HIPFIRE_DIR)/bin/hipfire
BUN_DIR      ?= $(HOME)/.bun

ORCHESTRATOR_MODEL ?= $(HOME)/projects/models/hipfire/qwen3.5-9b.mq4
ORCHESTRATOR_PORT  ?= 8080
ORCHESTRATOR_CTX  ?= 32768

CODER_MODEL ?= $(HOME)/projects/models/qwen2.5-coder-1.5b/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf
CODER_PORT  ?= 8081
CODER_CTX   ?= 8192

.PHONY: build extract run-daemon run-tui shell-debug clean
.PHONY: orchestrator coder start stop status logs
.PHONY: run-daemon-native run-tui-native

# Clean the stale TheRock ROCm env vars that hipfire's dlopen chokes on.
# HIPFIRE_MODEL and HIPFIRE_KV_MODE are read by the CLI's serve function;
# positional [host] [port] are the only CLI flags serve accepts.
HIPFIRE_ENV = env -u HIP_PATH -u ROCM_PATH -u LD_LIBRARY_PATH \
	HIPFIRE_MODEL=$(ORCHESTRATOR_MODEL) \
	HIPFIRE_KV_MODE=asym2 \
	PATH="/usr/local/bin:/usr/bin:/bin:$(BUN_DIR)/bin"

# ─── Servers ──────────────────────────────────────────────────────────────────

orchestrator:
	$(HIPFIRE_ENV) $(HIPFIRE_CLI) serve 127.0.0.1 $(ORCHESTRATOR_PORT)

coder:
	$(LLAMA_DIR)/build_vulkan/bin/llama-server \
		-m $(CODER_MODEL) \
		-ngl 0 \
		--host 127.0.0.1 \
		--port $(CODER_PORT) \
		-c $(CODER_CTX)

# ─── ZeroClaw daemon (native) ───────────────────────────────────────────────

run-daemon-native:
	./zeroclaw --config-dir $(CONFIG_DIR) daemon

run-tui-native:
	./zerocode --config-dir $(CONFIG_DIR) --agent orchestrator

# ─── ZeroClaw daemon (container) ────────────────────────────────────────────

run-daemon:
	podman run --rm \
		--name zeroclaw-daemon \
		-v $(CONFIG_DIR):/cfg:Z \
		--network host \
		--userns=keep-id \
		-u 1002:1002 \
		-e HOME=/cfg \
		--entrypoint '["/usr/bin/zeroclaw"]' \
		$(IMAGE_NAME):$(IMAGE_TAG) daemon --config-dir /cfg

run-tui:
	podman run --rm -it \
		--name zeroclaw-tui \
		-v $(CONFIG_DIR):/root/.zeroclaw:Z \
		--network host \
		$(IMAGE_NAME):$(IMAGE_TAG) /usr/bin/zerocode

# ─── Orchestrated workflow ──────────────────────────────────────────────────

# Dual-server mode (orchestrator GPU via hipfire + coder CPU via llama.cpp)
start: stop
	@echo "=== Starting orchestrator (hipfire, GPU, :$(ORCHESTRATOR_PORT)) ==="
	$(HIPFIRE_ENV) $(HIPFIRE_CLI) serve 127.0.0.1 $(ORCHESTRATOR_PORT) \
		> /tmp/hipfire-orchestrator.log 2>&1 &
	@echo "  PID: $$!"
	@sleep 5
	@echo "=== Starting coder (llama.cpp, CPU, :$(CODER_PORT)) ==="
	$(LLAMA_DIR)/build_vulkan/bin/llama-server \
		-m $(CODER_MODEL) \
		-ngl 0 \
		--host 127.0.0.1 \
		--port $(CODER_PORT) \
		-c $(CODER_CTX) \
		> /tmp/llama-coder.log 2>&1 &
	@echo "  PID: $$!"
	@sleep 5
	@echo "=== Starting zeroclaw daemon ==="
	./zeroclaw --config-dir $(CONFIG_DIR) daemon \
		> /tmp/zeroclaw-daemon.log 2>&1 &
	@echo "  PID: $$!"
	@sleep 3
	@$(MAKE) --no-print-directory status

# Single-server mode (same model for both roles, llama.cpp fallback)
start-single: stop
	@echo "=== Patching coder URI to match orchestrator port ==="
	@cp $(CONFIG_DIR)/config.toml $(CONFIG_DIR)/config.toml.bak
	@sed -i 's|:$(CODER_PORT)/v1|:$(ORCHESTRATOR_PORT)/v1|' $(CONFIG_DIR)/config.toml
	@echo "=== Starting server ($(ORCHESTRATOR_MODEL)) ==="
	$(HIPFIRE_ENV) $(HIPFIRE_CLI) serve 127.0.0.1 $(ORCHESTRATOR_PORT) \
		> /tmp/hipfire-orchestrator.log 2>&1 &
	@echo "  PID: $$!"
	@sleep 8
	@echo "=== Starting zeroclaw daemon ==="
	./zeroclaw --config-dir $(CONFIG_DIR) daemon \
		> /tmp/zeroclaw-daemon.log 2>&1 &
	@echo "  PID: $$!"
	@sleep 3
	@$(MAKE) --no-print-directory status

stop:
	@echo "=== Stopping all services ==="
	-pkill -9 -f "hipfire.*serve" 2>/dev/null || true
	-pkill -9 -f "daemon.*hipfire" 2>/dev/null || true
	-pkill -9 -f "llama-server" 2>/dev/null || true
	-pkill -9 -f "zeroclaw daemon" 2>/dev/null || true
	@if [ -f $(CONFIG_DIR)/config.toml.bak ]; then \
		mv $(CONFIG_DIR)/config.toml.bak $(CONFIG_DIR)/config.toml; \
		echo "  Config restored from backup."; \
	fi
	@sleep 1
	@echo "Done."

status:
	@echo "=== Status ==="
	@pid=$$(pgrep -f 'hipfire.*serve.*8080' 2>/dev/null | head -1); \
	 if [ -n "$$pid" ]; then echo "  orchestrator (hipfire, :8080): RUNNING (PID $$pid)"; \
	 else echo "  orchestrator (hipfire, :8080): STOPPED"; fi
	@pid=$$(pgrep -f 'llama-server.*8081' 2>/dev/null | head -1); \
	 if [ -n "$$pid" ]; then echo "  coder        (CPU :8081): RUNNING (PID $$pid)"; \
	 else echo "  coder        (CPU :8081): STOPPED"; fi
	@pid=$$(pgrep -f 'zeroclaw daemon' 2>/dev/null | head -1); \
	 if [ -n "$$pid" ]; then echo "  zeroclaw              : RUNNING (PID $$pid)"; \
	 else echo "  zeroclaw              : STOPPED"; fi

logs:
	@echo "=== orchestrator (hipfire, :8080) ==="
	@tail -3 /tmp/hipfire-orchestrator.log 2>/dev/null || echo "(no log)"
	@echo ""
	@echo "=== coder (CPU :8081) ==="
	@tail -3 /tmp/llama-coder.log 2>/dev/null || echo "(no log)"
	@echo ""
	@echo "=== zeroclaw daemon ==="
	@tail -3 /tmp/zeroclaw-daemon.log 2>/dev/null || echo "(no log)"

# ─── StageX container build ─────────────────────────────────────────────────

build:
	podman build -t $(IMAGE_NAME):$(IMAGE_TAG) -f Containerfile .

extract:
	@if ! podman image exists $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null; then \
		$(MAKE) build; \
	fi
	podman create --name zeroclaw-extract $(IMAGE_NAME):$(IMAGE_TAG)
	podman cp zeroclaw-extract:/usr/bin/zeroclaw .
	podman cp zeroclaw-extract:/usr/bin/zerocode .
	podman rm zeroclaw-extract
	ls -lh zeroclaw zerocode

shell-debug:
	podman run --rm -it \
		--entrypoint /bin/sh \
		docker.io/stagex/pallet-rust@sha256:2d90b9552412ee2c4fa2a13b489c2f28c044be7fb5d6a942bfd5a480a5c288fd

clean:
	-podman rmi $(IMAGE_NAME):$(IMAGE_TAG) 2>/dev/null
	rm -f zeroclaw zerocode
