#!/usr/bin/env python3
"""Fail fast when the Xcode app is still carrying local/demo release settings.

The checks intentionally print only setting names and placeholders, never
credential values. Run from `Xcode/Equinox`:

    python3 scripts/preflight_release.py
"""
from __future__ import annotations

import json
import plistlib
import re
import sys
from pathlib import Path


APP_BUNDLE_ID = "com.equinox.app"
GOOGLE_CLIENT_ID_RE = re.compile(
    r"^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$"
)


def _project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _app_build_settings(project_text: str) -> dict[str, dict[str, str]]:
    blocks = re.finditer(
        r"/\* (Debug|Release) \*/ = \{\n"
        r"\s+isa = XCBuildConfiguration;\n"
        r"\s+buildSettings = \{\n"
        r"(?P<body>.*?)"
        r"\n\s+\};\n"
        r"\s+name = \1;\n"
        r"\s+\};",
        project_text,
        re.DOTALL,
    )
    settings: dict[str, dict[str, str]] = {}
    for match in blocks:
        body = match.group("body")
        if f"PRODUCT_BUNDLE_IDENTIFIER = {APP_BUNDLE_ID};" not in body:
            continue
        values: dict[str, str] = {}
        for line in body.splitlines():
            stripped = line.strip()
            if " = " not in stripped or not stripped.endswith(";"):
                continue
            key, raw_value = stripped[:-1].split(" = ", 1)
            values[key] = raw_value.strip('"')
        settings[match.group(1)] = values
    return settings


def _google_scheme(client_id: str) -> str:
    return f"com.googleusercontent.apps.{client_id.removesuffix('.apps.googleusercontent.com')}"


def _launch_logo_failures(root: Path) -> list[str]:
    image_dir = root / "Equinox" / "Assets.xcassets" / "LaunchLogo.imageset"
    contents_path = image_dir / "Contents.json"
    if not contents_path.exists():
        return ["LaunchLogo.imageset/Contents.json is missing"]
    try:
        contents = json.loads(_read_text(contents_path))
    except json.JSONDecodeError:
        return ["LaunchLogo.imageset/Contents.json is not valid JSON"]

    failures: list[str] = []
    for image in contents.get("images", []):
        filename = image.get("filename")
        if not filename:
            continue
        path = image_dir / filename
        if not path.exists():
            failures.append(f"LaunchLogo asset is missing {filename}")
        elif path.stat().st_size == 0:
            failures.append(f"LaunchLogo asset is empty: {filename}")
    return failures


def _entitlement_failures(root: Path) -> list[str]:
    path = root / "Equinox" / "Equinox.entitlements"
    if not path.exists():
        return ["Equinox.entitlements is missing"]
    try:
        with path.open("rb") as fh:
            entitlements = plistlib.load(fh)
    except Exception:
        return ["Equinox.entitlements is not a valid plist"]

    failures: list[str] = []
    if entitlements.get("com.apple.developer.healthkit") is not True:
        failures.append("HealthKit entitlement is missing")
    return failures


def problems(root: Path | None = None) -> list[str]:
    root = root or _project_root()
    project_file = root / "Equinox.xcodeproj" / "project.pbxproj"
    if not project_file.exists():
        return [f"Missing project file: {project_file}"]

    failures: list[str] = []
    settings = _app_build_settings(_read_text(project_file))
    for configuration in ("Debug", "Release"):
        if configuration not in settings:
            failures.append(f"{configuration} app build settings were not found")

    release = settings.get("Release", {})
    release_url = release.get("EQUINOX_API_BASE_URL", "")
    if not release_url.startswith("https://"):
        failures.append("Release EQUINOX_API_BASE_URL must be an HTTPS Cloud Run URL")
    placeholder_markers = ("xxxxx", "YOUR-", "your-", "localhost", "127.0.0.1")
    if any(marker in release_url for marker in placeholder_markers):
        failures.append("Release EQUINOX_API_BASE_URL still looks like a placeholder/local URL")

    for configuration, values in settings.items():
        if values.get("PRODUCT_BUNDLE_IDENTIFIER") != APP_BUNDLE_ID:
            failures.append(f"{configuration} PRODUCT_BUNDLE_IDENTIFIER must be {APP_BUNDLE_ID}")
        client_id = values.get("GOOGLE_IOS_CLIENT_ID", "")
        if not GOOGLE_CLIENT_ID_RE.match(client_id):
            failures.append(f"{configuration} GOOGLE_IOS_CLIENT_ID is required")
            continue
        expected_scheme = _google_scheme(client_id)
        if values.get("GOOGLE_OAUTH_REDIRECT_SCHEME") != expected_scheme:
            failures.append(f"{configuration} GOOGLE_OAUTH_REDIRECT_SCHEME must match GOOGLE_IOS_CLIENT_ID")

    failures.extend(_entitlement_failures(root))
    failures.extend(_launch_logo_failures(root))
    return failures


def main() -> int:
    failures = problems()
    if failures:
        print("Xcode release preflight failed:")
        for failure in failures:
            print(f"- {failure}")
        return 1
    print("Xcode release preflight passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
