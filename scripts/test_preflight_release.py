#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import plistlib
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("preflight_release.py")
SPEC = importlib.util.spec_from_file_location("preflight_release", SCRIPT_PATH)
preflight_release = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(preflight_release)


GOOD_CLIENT_ID = "123-abc.apps.googleusercontent.com"
GOOD_SCHEME = "com.googleusercontent.apps.123-abc"
GOOD_RELEASE_URL = "https://equinox-api.example.run.app"


def _build_settings(configuration: str, *, api_url: str, client_id: str, scheme: str) -> str:
    return f"""		ABCDEF /* {configuration} */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				EQUINOX_API_BASE_URL = "{api_url}";
				GOOGLE_IOS_CLIENT_ID = "{client_id}";
				GOOGLE_OAUTH_REDIRECT_SCHEME = "{scheme}";
				PRODUCT_BUNDLE_IDENTIFIER = com.equinox.app;
			}};
			name = {configuration};
		}};"""


def _project_text(*, release_url: str = GOOD_RELEASE_URL, client_id: str = GOOD_CLIENT_ID, scheme: str = GOOD_SCHEME) -> str:
    return "\n".join(
        [
            _build_settings("Debug", api_url="http://127.0.0.1:8000", client_id=client_id, scheme=scheme),
            _build_settings("Release", api_url=release_url, client_id=client_id, scheme=scheme),
        ]
    )


def _write_fixture(
    root: Path,
    *,
    release_url: str = GOOD_RELEASE_URL,
    client_id: str = GOOD_CLIENT_ID,
    scheme: str = GOOD_SCHEME,
    launch_logo: bool = True,
) -> None:
    project = root / "Equinox.xcodeproj"
    project.mkdir()
    (project / "project.pbxproj").write_text(
        _project_text(release_url=release_url, client_id=client_id, scheme=scheme),
        encoding="utf-8",
    )

    app_root = root / "Equinox"
    app_root.mkdir()
    entitlements = {"com.apple.developer.healthkit": True}
    with (app_root / "Equinox.entitlements").open("wb") as fh:
        plistlib.dump(entitlements, fh)

    logo_dir = app_root / "Assets.xcassets" / "LaunchLogo.imageset"
    logo_dir.mkdir(parents=True)
    images = [
        {"filename": "LaunchLogo.png", "idiom": "universal", "scale": "1x"},
        {"filename": "LaunchLogo@2x.png", "idiom": "universal", "scale": "2x"},
        {"filename": "LaunchLogo@3x.png", "idiom": "universal", "scale": "3x"},
    ]
    (logo_dir / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}), encoding="utf-8")
    if launch_logo:
        for image in images:
            (logo_dir / image["filename"]).write_bytes(b"png")


class XcodeReleasePreflightTests(unittest.TestCase):
    def test_complete_release_settings_pass(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _write_fixture(root)
            self.assertEqual(preflight_release.problems(root), [])

    def test_rejects_placeholder_release_url(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _write_fixture(root, release_url="https://equinox-api-xxxxx.asia-east1.run.app")
            self.assertIn(
                "Release EQUINOX_API_BASE_URL still looks like a placeholder/local URL",
                preflight_release.problems(root),
            )

    def test_rejects_missing_google_client_id(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _write_fixture(root, client_id="", scheme="")
            failures = preflight_release.problems(root)
            self.assertIn("Debug GOOGLE_IOS_CLIENT_ID is required", failures)
            self.assertIn("Release GOOGLE_IOS_CLIENT_ID is required", failures)

    def test_rejects_mismatched_google_redirect_scheme(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _write_fixture(root, scheme="com.example.bad")
            self.assertIn(
                "Debug GOOGLE_OAUTH_REDIRECT_SCHEME must match GOOGLE_IOS_CLIENT_ID",
                preflight_release.problems(root),
            )

    def test_rejects_missing_launch_logo_assets(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            _write_fixture(root, launch_logo=False)
            failures = preflight_release.problems(root)
            self.assertIn("LaunchLogo asset is missing LaunchLogo.png", failures)
            self.assertIn("LaunchLogo asset is missing LaunchLogo@2x.png", failures)
            self.assertIn("LaunchLogo asset is missing LaunchLogo@3x.png", failures)


if __name__ == "__main__":
    unittest.main()
