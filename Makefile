APP_NAME := nixos
BUILD_VAR_PKG := github.com/water-sucks/nixos/internal/build

VERSION ?= $(shell git describe --tags --always)
COMMIT_HASH ?= $(shell git rev-parse HEAD)

# Configurable parameters
FLAKE ?= true
NIXPKGS_REVISION ?= 24.11

LDFLAGS := -X $(BUILD_VAR_PKG).Version=$(VERSION)
LDFLAGS += -X $(BUILD_VAR_PKG).GitRevision=$(COMMIT_HASH)
LDFLAGS += -X $(BUILD_VAR_PKG).Flake=$(FLAKE)
LDFLAGS += -X $(BUILD_VAR_PKG).NixpkgsVersion=$(NIXPKGS_REVISION)

all: build

.PHONY: build
build:
	@echo "building $(APP_NAME)..."
	go build -o ./$(APP_NAME) -ldflags="$(LDFLAGS)" .

.PHONY: clean
clean:
	@echo "cleaning up..."
	go clean

.PHONY: test
test:
	@echo "running tests..."
	go test ./...
