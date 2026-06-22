#!/usr/bin/env bash
set -euo pipefail

API_URL="${1:-}"
PROJECT_FILE="Equinox.xcodeproj/project.pbxproj"

if [[ -z "${API_URL}" ]]; then
  echo "Usage: scripts/set_release_api_url.sh https://your-cloud-run-url" >&2
  exit 1
fi

if [[ ! "${API_URL}" =~ ^https:// ]]; then
  echo "Release API URL must start with https:// for TestFlight/App Store builds." >&2
  exit 1
fi

/usr/bin/python3 - "${PROJECT_FILE}" "${API_URL}" <<'PY'
import re
import sys
from pathlib import Path

project_file = Path(sys.argv[1])
api_url = sys.argv[2]
escaped_url = api_url.replace("\\", "\\\\").replace('"', '\\"')
text = project_file.read_text()

pattern = re.compile(
    r'(\t\t[0-9A-F]+ /\* Release \*/ = \{\n'
    r'\t\t\tisa = XCBuildConfiguration;\n'
    r'\t\t\tbuildSettings = \{\n)'
    r'(.*?)'
    r'(\n\t\t\t\};\n\t\t\tname = Release;\n\t\t\};)',
    re.DOTALL,
)

updated = 0

def replace_block(match):
    global updated
    prefix, body, suffix = match.groups()
    if "PRODUCT_BUNDLE_IDENTIFIER = com.equinox.app;" not in body:
        return match.group(0)

    line = f'\n\t\t\t\tEQUINOX_API_BASE_URL = "{escaped_url}";'
    if "EQUINOX_API_BASE_URL =" in body:
        body = re.sub(r'\n\t\t\t\tEQUINOX_API_BASE_URL = "[^"]*";', line, body)
    else:
        marker = "\n\t\t\t\tGENERATE_INFOPLIST_FILE = NO;"
        body = body.replace(marker, line + marker)
    updated += 1
    return prefix + body + suffix

new_text = pattern.sub(replace_block, text)
if updated != 1:
    raise SystemExit(f"Expected to update 1 app Release build setting, updated {updated}.")

project_file.write_text(new_text)
print(f"Set Release EQUINOX_API_BASE_URL to {api_url}")
PY
