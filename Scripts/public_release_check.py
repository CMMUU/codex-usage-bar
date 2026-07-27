#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
IGNORED_PARTS = {
    ".git",
    ".build",
    ".swiftpm",
    ".wrangler",
    "dist",
    "node_modules",
}
IGNORED_SUFFIXES = {
    ".a",
    ".dylib",
    ".gif",
    ".icns",
    ".jpeg",
    ".jpg",
    ".o",
    ".pdf",
    ".png",
    ".swiftmodule",
    ".zip",
}
REQUIRED_PATHS = {
    "LICENSE",
    "README.md",
    "README.zh-CN.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    ".github/workflows/ci.yml",
    ".github/workflows/release.yml",
    "docs/images/usage-popover.png",
    "project.yml",
}
FORBIDDEN_PATTERNS = {
    "absolute macOS user path": re.compile(r"/Users/[A-Za-z0-9._-]+/"),
    "private workspace path": re.compile(r"/opt/workspace"),
    "OpenAI-style secret": re.compile(r"\bsk-[A-Za-z0-9_-]{16,}\b"),
    "GitHub OAuth token": re.compile(r"\bgho_[A-Za-z0-9]{16,}\b"),
    "private key": re.compile(r"BEGIN (?:RSA |OPENSSH )?PRIVATE KEY"),
    "bearer credential": re.compile(r"Bearer\s+[A-Za-z0-9._~-]{20,}"),
}


def iter_text_files() -> list[Path]:
    files: list[Path] = []
    this_script = Path(__file__).resolve()
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        if path.resolve() == this_script:
            continue
        if any(part in IGNORED_PARTS for part in path.relative_to(ROOT).parts):
            continue
        if path.suffix.lower() in IGNORED_SUFFIXES:
            continue
        files.append(path)
    return files


def main() -> int:
    failures: list[str] = []

    for relative_path in sorted(REQUIRED_PATHS):
        if not (ROOT / relative_path).is_file():
            failures.append(f"missing required file: {relative_path}")

    for path in iter_text_files():
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue

        relative_path = path.relative_to(ROOT)
        for label, pattern in FORBIDDEN_PATTERNS.items():
            for match in pattern.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                failures.append(f"{relative_path}:{line}: {label}")

    if failures:
        print("Public release check failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print("Public release check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
