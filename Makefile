.PHONY: build test integration-test widget-build xcode-project package dmg release-package run docs-screenshot public-release-check web-check web-dev web-deploy clean

build:
	swift build

test:
	swift run CodexUsageVerifier

integration-test:
	swift run CodexUsageVerifier --integration

widget-build:
	swift build --product CodexUsageWidget

xcode-project:
	./Scripts/generate-project.sh

package:
	./Scripts/package.sh

dmg: package
	./Scripts/create_dmg.sh

release-package:
	./Scripts/release_package.sh

run: package
	open "dist/Codex Usage Bar.app"

docs-screenshot:
	./Scripts/render-documentation-snapshot.sh

public-release-check:
	python3 Scripts/public_release_check.py

web-check:
	cd web && npm run check && npm test && npx wrangler deploy --dry-run

web-dev:
	cd web && npm run dev

web-deploy:
	cd web && npm run deploy

clean:
	swift package clean
	rm -rf dist
