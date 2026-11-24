.PHONY: test build gen setup check sims

setup:
	./scripts/setup.sh

check:
	./scripts/check-env.sh

gen:
	xcodegen generate

build: gen
	xcodebuild build -scheme Dayline -destination 'platform=iOS Simulator,id=$(shell ./scripts/pick-sim.sh)' CODE_SIGNING_ALLOWED=NO

test: gen
	xcodebuild test -scheme Dayline -destination 'platform=iOS Simulator,id=$(shell ./scripts/pick-sim.sh)' CODE_SIGNING_ALLOWED=NO

sims:
	xcrun simctl list devices available | grep -i iphone | head -20
