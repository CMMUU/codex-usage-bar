.PHONY: build test integration-test package run docs-screenshot public-release-check clean

build:
	swift build

test:
	swift run CodexUsageVerifier

integration-test:
	swift run CodexUsageVerifier --integration

package:
	./Scripts/package.sh

run: package
	open "dist/Codex Usage Bar.app"

docs-screenshot:
	./Scripts/render-documentation-snapshot.sh

public-release-check:
	python3 Scripts/public_release_check.py

clean:
	swift package clean
	rm -rf dist
