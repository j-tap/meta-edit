VERSION := $(shell cat VERSION)

.PHONY: version release macos windows linux all

version:
	@echo $(VERSION)

# Tag and push a release. CI builds all three apps and publishes a GitHub Release.
# Usage: make release V=1.2.0
release:
	@test -n "$(V)" || { echo "usage: make release V=X.Y.Z"; exit 1; }
	@./scripts/release.sh $(V)

# Per-platform builds. Each target is wired up when its app lands in apps/<platform>.
macos windows linux:
	@echo "$@: not scaffolded yet, see apps/$@/README.md"; exit 1

all: macos windows linux
