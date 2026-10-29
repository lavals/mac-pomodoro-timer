CLT_PATH := /Library/Developer/CommandLineTools

# Command Line Tools ship the Swift Testing macro plugin outside the default search path,
# so `swift test` fails once the package has an executable target. Add the plugin path
# only on CLT machines; Xcode toolchains (CI) run plain `swift test`.
ifeq ($(shell xcode-select -p 2>/dev/null),$(CLT_PATH))
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc "$$(dirname "$$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
else
TEST_FLAGS :=
endif

.PHONY: build test app run install verify-app check-cask check-docs clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

# assemble build/Pomodoro.app (release binary, Info.plist, icon, ad-hoc signature)
app:
	scripts/build-app.sh

run: app
	open build/Pomodoro.app

install: app
	rm -rf /Applications/Pomodoro.app
	ditto build/Pomodoro.app /Applications/Pomodoro.app

verify-app:
	scripts/verify-app.sh

# render the cask with dummy values, check Ruby syntax, fail on any unrendered placeholder,
# then (when brew is installed) load it read-only with HOMEBREW_DEVELOPER=1 so deprecated DSL fails
check-cask:
	@set -e; dir="$$(mktemp -d -t pomodoro-cask)"; trap 'rm -rf "$$dir"' EXIT; out="$$dir/pomodoro.rb"; \
	scripts/render-cask.sh 0.0.0 "$$(printf '0%.0s' $$(seq 64))" > "$$out"; \
	ruby -c "$$out" > /dev/null; \
	if grep -n '__' "$$out"; then echo "unrendered placeholder in cask" >&2; exit 1; fi; \
	if command -v brew > /dev/null; then \
	  HOMEBREW_DEVELOPER=1 HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_FROM_API=1 HOMEBREW_NO_ENV_HINTS=1 \
	    brew ruby -e 'Cask::CaskLoader.load(ARGV.first)' "$$out"; \
	else echo "brew not found; skipped loading the cask with Homebrew"; fi; \
	echo "cask OK"

# both Focus shortcut names must appear verbatim in the README and the setup guide,
# and the README must link the guide (the app links to it too)
FOCUS_DOCS := README.md docs/focus-shortcuts.md
check-docs:
	@set -e; for f in $(FOCUS_DOCS); do \
	  for name in "Pomodoro Focus On" "Pomodoro Focus Off"; do \
	    grep -qF "$$name" "$$f" || { echo "$$f does not mention \"$$name\"" >&2; exit 1; }; \
	  done; \
	done; \
	grep -qF "docs/focus-shortcuts.md" README.md || { echo "README.md does not link docs/focus-shortcuts.md" >&2; exit 1; }; \
	echo "docs OK"

clean:
	swift package clean
	rm -rf .build build
