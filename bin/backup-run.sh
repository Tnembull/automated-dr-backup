#!/usr/bin/env bash
# ==============================================================================
# Automated Production Database Snapshot, GPG Encryption & Cloud Sync
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-${SCRIPT_DIR}/../config/backup.conf}"

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "[-] Configuration file not found at: ${CONFIG_FILE}" >&2
  exit 1
fi

# Source configuration
# shellcheck source=/dev/null
source "${CONFIG_FILE}"

TIMESTAMP="$(date -u +"%Y%m%d_%H%M%SZ")"
TEMP_DIR="$(mktemp -d /tmp/backup_work_XXXXXX)"
ARCHIVE_NAME="backup_${TIMESTAMP}.tar.gz"
ENCRYPTED_ARCHIVE="${ARCHIVE_NAME}.gpg"

cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

send_telegram_notification() {
  local status="$1"
  local message="$2"
  if [[ "${TELEGRAM_ALERT_ENABLED}" == "true" && -n "${TELEGRAM_BOT_TOKEN}" && "${TELEGRAM_BOT_TOKEN}" != "YOUR_TELEGRAM_BOT_TOKEN" ]]; then
    local payload
    payload=$(printf '{"chat_id": "%s", "text": "<b>[Backup %s]</b>\n%s", "parse_mode": "HTML"}' \
      "${TELEGRAM_CHAT_ID}" "${status}" "${message}")
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
      -H "Content-Type: application/json" \
      -d "${payload}" >/dev/null || true
  fi
}

echo "[+] Starting automated backup run: ${TIMESTAMP}"

# 1. Capture atomic SQLite / Database dumps
mkdir -p "${TEMP_DIR}/databases"
for db in ${SQLITE_DB_PATHS}; do
  if [[ -f "${db}" ]]; then
    db_base="$(basename "${db}")"
    echo "[*] Creating atomic snapshot of SQLite DB: ${db}"
    sqlite3 "${db}" ".backup '${TEMP_DIR}/databases/${db_base}.${TIMESTAMP}.bak'"
  fi
done

# 2. Package database snapshots and metadata
echo "[*] Compressing archives..."
tar -czf "${TEMP_DIR}/${ARCHIVE_NAME}" -C "${TEMP_DIR}/databases" .

# Generate SHA256 checksum before encryption
sha256sum "${TEMP_DIR}/${ARCHIVE_NAME}" > "${TEMP_DIR}/${ARCHIVE_NAME}.sha256"

# 3. GPG Military-Grade Encryption (AES-256)
echo "[*] Encrypting archive with GPG..."
if [[ "${ENCRYPTION_MODE}" == "symmetric" ]]; then
  if [[ -f "${GPG_PASSPHRASE_FILE}" ]]; then
    gpg --batch --yes --passphrase-file "${GPG_PASSPHRASE_FILE}" \
      --symmetric --cipher-algo AES256 \
      -o "${TEMP_DIR}/${ENCRYPTED_ARCHIVE}" "${TEMP_DIR}/${ARCHIVE_NAME}"
  else
    echo "[-] GPG passphrase file missing: ${GPG_PASSPHRASE_FILE}" >&2
    exit 1
  fi
else
  gpg --batch --yes --trust-model always --encrypt -r "${GPG_RECIPIENT}" \
    -o "${TEMP_DIR}/${ENCRYPTED_ARCHIVE}" "${TEMP_DIR}/${ARCHIVE_NAME}"
fi

# 4. Move to local backup storage with retention policy
mkdir -p "${BACKUP_DIR}"
cp "${TEMP_DIR}/${ENCRYPTED_ARCHIVE}" "${BACKUP_DIR}/"
cp "${TEMP_DIR}/${ARCHIVE_NAME}.sha256" "${BACKUP_DIR}/"

# Prune old backups past retention threshold
echo "[*] Cleaning local backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "backup_*.tar.gz.gpg" -mtime +"${RETENTION_DAYS}" -delete
find "${BACKUP_DIR}" -name "backup_*.tar.gz.sha256" -mtime +"${RETENTION_DAYS}" -delete

# 5. Offsite Cloud Storage Upload (Optional AWS S3 / Cloudflare R2)
if [[ "${S3_ENABLED}" == "true" && -n "${S3_BUCKET_NAME}" && "${S3_BUCKET_NAME}" != "production-encrypted-backups" ]]; then
  echo "[*] Uploading encrypted archive to cloud object storage..."
  aws s3 cp "${BACKUP_DIR}/${ENCRYPTED_ARCHIVE}" \
    "s3://${S3_BUCKET_NAME}/${S3_PREFIX}/${ENCRYPTED_ARCHIVE}" \
    --endpoint-url "${S3_ENDPOINT_URL}"
fi

SUCCESS_MSG="Successfully encrypted & stored backup: ${ENCRYPTED_ARCHIVE}"
echo "[✓] ${SUCCESS_MSG}"
send_telegram_notification "SUCCESS" "${SUCCESS_MSG}"
