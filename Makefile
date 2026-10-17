CLT_PATH := /Library/Developer/CommandLineTools

# Command Line Tools ship the Swift Testing macro plugin outside the default search path,
# so `swift test` fails once the package has an executable target. Add the plugin path
# only on CLT machines; Xcode toolchains (CI) run plain `swift test`.
ifeq ($(shell xcode-select -p 2>/dev/null),$(CLT_PATH))
TEST_FLAGS := -Xswiftc -plugin-path -Xswiftc "$$(dirname "$$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
else
TEST_FLAGS :=
endif

.PHONY: build test clean

build:
	swift build

test:
	swift test $(TEST_FLAGS)

clean:
	swift package clean
	rm -rf .build build
