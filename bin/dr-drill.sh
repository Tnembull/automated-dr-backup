#!/usr/bin/env bash
# ==============================================================================
# Automated Disaster Recovery Drill & Integrity Verification
# "An untested backup is not a backup"
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-${SCRIPT_DIR}/../config/backup.conf}"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "[-] Config missing: ${CONFIG_FILE}" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${CONFIG_FILE}"

# Find the newest local encrypted backup archive
LATEST_BACKUP="$(find "${BACKUP_DIR}" -name "backup_*.tar.gz.gpg" | sort | tail -n 1 || true)"

if [[ -z "${LATEST_BACKUP}" ]]; then
  echo "[-] No encrypted backup archives found in ${BACKUP_DIR}" >&2
  exit 1
fi

echo "[+] Starting Disaster Recovery integrity drill on: ${LATEST_BACKUP}"
DRILL_TEMP="$(mktemp -d /tmp/dr_drill_XXXXXX)"

cleanup() {
  rm -rf "${DRILL_TEMP}"
}
trap cleanup EXIT

# 1. Decrypt archive into sandbox directory
echo "[*] Decrypting archive..."
DECRYPTED_TAR="${DRILL_TEMP}/restored.tar.gz"

if [[ "${ENCRYPTION_MODE}" == "symmetric" ]]; then
  gpg --batch --yes --passphrase-file "${GPG_PASSPHRASE_FILE}" \
    -d -o "${DECRYPTED_TAR}" "${LATEST_BACKUP}"
else
  gpg --batch --yes -d -o "${DECRYPTED_TAR}" "${LATEST_BACKUP}"
fi

# 2. Extract contents
echo "[*] Unpacking archive contents..."
mkdir -p "${DRILL_TEMP}/extracted"
tar -xzf "${DECRYPTED_TAR}" -C "${DRILL_TEMP}/extracted"

# 3. SQLite Integrity Check on restored databases
echo "[*] Running database integrity verification..."
RESTORED_DBS=$(find "${DRILL_TEMP}/extracted" -name "*.bak")

INTEGRITY_FAILURES=0
for db in ${RESTORED_DBS}; do
  echo "    Checking database: $(basename "${db}")"
  CHECK_RESULT=$(sqlite3 "${db}" "PRAGMA integrity_check;")
  if [[ "${CHECK_RESULT}" != "ok" ]]; then
    echo "    [-] Integrity check FAILED for: ${db} (${CHECK_RESULT})" >&2
    INTEGRITY_FAILURES=$((INTEGRITY_FAILURES + 1))
  else
    echo "    [✓] Database structure OK"
  fi
done

if [[ ${INTEGRITY_FAILURES} -gt 0 ]]; then
  echo "[-] Disaster Recovery Drill FAILED with ${INTEGRITY_FAILURES} errors." >&2
  exit 2
fi

echo "================================================================="
echo "[✓] DISASTER RECOVERY DRILL PASSED: All databases healthy & clean"
echo "================================================================="
exit 0
