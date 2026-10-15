VERSION := $(shell cat VERSION)

.PHONY: version release macos macos-dmg test-macos windows linux all

version:
	@echo $(VERSION)

# Tag and push a release. CI builds all three apps and publishes a GitHub Release.
# Usage: make release V=1.2.0
release:
	@test -n "$(V)" || { echo "usage: make release V=X.Y.Z"; exit 1; }
	@./scripts/release.sh $(V)

macos:
	@apps/macos/scripts/build-app.sh

macos-dmg: macos
	@apps/macos/scripts/make-dmg.sh

test-macos:
	@apps/macos/scripts/test.sh

# Wired up when the apps land in apps/<platform>.
windows linux:
	@echo "$@: not scaffolded yet, see apps/$@/README.md"; exit 1

all: macos windows linux
