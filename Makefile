.PHONY: build test integration-test package run docs-screenshot public-release-check web-check web-dev web-deploy clean

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

web-check:
	cd web && npm run check && npm test && npx wrangler deploy --dry-run

web-dev:
	cd web && npm run dev

web-deploy:
	cd web && npm run deploy

clean:
	swift package clean
	rm -rf dist
