# Makefile for building the TUI and moving the binary to the repo root
CARGO ?= cargo
TARGET_DIR = target/release
BIN_NAME = kas-tui
DIST_DIR = ../../dist
OUT_NAME = ../../builder-tui

.PHONY: all build post-build clean

all: build post-build

build:
	$(CARGO) build --release

post-build:
	@echo "Running post-build steps..."
	mkdir -p $(DIST_DIR)
	cp $(TARGET_DIR)/$(BIN_NAME) $(OUT_NAME)
	cp $(TARGET_DIR)/$(BIN_NAME) $(DIST_DIR)/
	chmod +x $(OUT_NAME) || true
	@echo "Artifacts moved to $(DIST_DIR)/ and $(OUT_NAME)"

clean:
	$(CARGO) clean
	rm -rf $(DIST_DIR)
	rm -f $(OUT_NAME)
