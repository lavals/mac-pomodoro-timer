CLT_PATH := /Library/Developer/CommandLineTools

# Command Line Tools ship the Swift Testing macro plugin outside the default search path,
# so `swift test` fails once the package has an executable target. Add the plugin path
# only on CLT machines; Xcode toolchains (CI) run plain `swift test`.
ifeq ($(shell xcode-select -p 2>/dev/null),$(CLT_PATH))
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc "$$(dirname "$$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
else
TEST_FLAGS :=
endif

.PHONY: build test app run install verify-app check-cask clean

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

# render the cask with dummy values, check Ruby syntax, fail on any unrendered placeholder
check-cask:
	@set -e; out="$$(mktemp -t pomodoro-cask)"; trap 'rm -f "$$out"' EXIT; \
	scripts/render-cask.sh 0.0.0 "$$(printf '0%.0s' $$(seq 64))" > "$$out"; \
	ruby -c "$$out" > /dev/null; \
	if grep -n '__' "$$out"; then echo "unrendered placeholder in cask" >&2; exit 1; fi; \
	echo "cask OK"

clean:
	swift package clean
	rm -rf .build build
