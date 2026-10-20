.PHONY: test build gen setup check sims

# Simulator used for build/test. Override if yours differs: make test SIM="iPhone 17 Pro Max"
SIM ?= iPhone 17 Pro

setup:
	./scripts/setup.sh

check:
	./scripts/check-env.sh

gen:
	xcodegen generate

build:
	xcodebuild build -scheme Dayline -destination 'platform=iOS Simulator,name=$(SIM)' CODE_SIGNING_ALLOWED=NO

test:
	xcodebuild test -scheme Dayline -destination 'platform=iOS Simulator,name=$(SIM)' CODE_SIGNING_ALLOWED=NO

sims:
	xcrun simctl list devices available | grep -i iphone | head -20
