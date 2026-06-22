#!/usr/bin/env bash
set -euo pipefail

CLIENT_ID="${1:-}"
PROJECT_FILE="Equinox.xcodeproj/project.pbxproj"

if [[ ! "${CLIENT_ID}" =~ ^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$ ]]; then
  echo "Usage: scripts/set_google_ios_client_id.sh <iOS_CLIENT_ID>" >&2
  exit 1
fi

SCHEME="com.googleusercontent.apps.${CLIENT_ID%%.apps.googleusercontent.com}"

/usr/bin/python3 - "${PROJECT_FILE}" "${CLIENT_ID}" "${SCHEME}" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
client_id, scheme = sys.argv[2:]
text = path.read_text()

for key, value in {
    "GOOGLE_IOS_CLIENT_ID": client_id,
    "GOOGLE_OAUTH_REDIRECT_SCHEME": scheme,
}.items():
    pattern = rf'({key} = )"[^"]*";'
    text, count = re.subn(pattern, rf'\g<1>"{value}";', text)
    if count != 2:
        raise SystemExit(f"Expected Debug + Release {key}, updated {count} entries.")

path.write_text(text)
print(f"Configured Google iOS OAuth callback scheme: {scheme}")
PY
