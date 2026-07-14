APP      := build/CallScribe.app
IDENTITY := CallScribe Dev
BUNDLE_ID := com.slavayus.callscribe

# The CommandLineTools toolchain ships Testing.framework outside the default
# search paths; swift test needs them spelled out (not needed for swift build).
DEVDIR     := $(shell xcode-select -p)/Library/Developer
TEST_FLAGS := -Xswiftc -F$(DEVDIR)/Frameworks \
              -Xlinker -F$(DEVDIR)/Frameworks \
              -Xlinker -rpath -Xlinker $(DEVDIR)/Frameworks \
              -Xlinker -rpath -Xlinker $(DEVDIR)/usr/lib

.PHONY: build app run install test golden cert clean

build:
	swift build -c release

app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp .build/release/callscribe $(APP)/Contents/MacOS/callscribe
	cp Support/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign "$(IDENTITY)" --identifier $(BUNDLE_ID) $(APP)

run: app
	open $(APP)

install: app
	mkdir -p ~/Applications
	rm -rf ~/Applications/CallScribe.app
	cp -R $(APP) ~/Applications/CallScribe.app

test:
	swift test $(TEST_FLAGS)

golden:
	CALLSCRIBE_GOLDEN=1 swift test $(TEST_FLAGS) --filter GoldenPipelineTests

cert:
	scripts/make-cert.sh

clean:
	rm -rf build .build
