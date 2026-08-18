#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

MODE="${1:---tracked}"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ "$MODE" == "--staged" ]]; then
        echo "A Git checkout is required for a staged-file scan." >&2
        exit 2
    fi
    echo "Public-safety Git scan skipped (source archive has no Git metadata)."
    exit 0
fi

case "$MODE" in
    --tracked)
        FILE_LIST_COMMAND=(git ls-files --cached --others --exclude-standard -z)
        ;;
    --staged)
        FILE_LIST_COMMAND=(git diff --cached --name-only --diff-filter=ACMR -z)
        ;;
    *)
        echo "Usage: $0 [--tracked|--staged]" >&2
        exit 2
        ;;
esac

readonly PATTERN='DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Z0-9]{10}|TEAM_ID[[:space:]]*=[[:space:]]*[A-Z0-9]{10}|CODE_SIGN_IDENTITY[[:space:]]*=[[:space:]]*"?Developer ID|(Developer ID Application|Apple Development):[^"[:cntrl:]]+\([A-Z0-9]{10}\)|/Users/[A-Za-z0-9._-]+|homelan\.kuehns|frigate\.homelan|://[^/@:[:space:]]+:[^/@[:space:]]+@|-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}'
readonly FORBIDDEN_EXTENSION='\.(p12|pfx|p8|key|pem|cer|certSigningRequest|mobileprovision|provisionprofile|developerprofile)$'

FAILED=false
scan_contents() {
    local file="$1"
    if [[ "$MODE" == "--staged" ]]; then
        git show ":$file"
    else
        /bin/cat "$file"
    fi
}

while IFS= read -r -d '' file; do
    if [[ "$MODE" == "--tracked" && ! -f "$file" ]]; then
        continue
    fi

    if [[ "$file" == "build.local.env" || "$file" == "release.local.env" || \
        "$file" == ".env" || "$file" == */.env || "$file" == */xcuserdata/* || \
        "$file" =~ $FORBIDDEN_EXTENSION ]]; then
        echo "Blocked sensitive file type: $file" >&2
        FAILED=true
        continue
    fi

    if scan_contents "$file" | /usr/bin/grep -aEn "$PATTERN" | \
        /usr/bin/grep -Fv -e 'TEAM_ID=ABCDEFGHIJ' -e 'readonly PATTERN=' >/dev/null; then
        echo "Possible secret or machine-specific identity in: $file" >&2
        FAILED=true
    fi
done < <("${FILE_LIST_COMMAND[@]}")

if [[ "$FAILED" == true ]]; then
    echo "Public-safety scan failed. Keep signing data and private infrastructure local." >&2
    exit 1
fi

echo "Public-safety scan passed ($MODE files)."
