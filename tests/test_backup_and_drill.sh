#!/usr/bin/env bash
# Test pipeline executing mock backup run and DR drill
set -euo pipefail

TEST_DIR="$(mktemp -d /tmp/dr_test_suite_XXXXXX)"
cleanup() {
  rm -rf "${TEST_DIR}"
}
trap cleanup EXIT

echo "[*] Setting up sandbox test fixtures..."
mkdir -p "${TEST_DIR}/dbs" "${TEST_DIR}/backups" "${TEST_DIR}/secrets"

# Create mock test sqlite databases
sqlite3 "${TEST_DIR}/dbs/app.db" "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT); INSERT INTO users VALUES (1, 'Alice'), (2, 'Bob');"
sqlite3 "${TEST_DIR}/dbs/audit.db" "CREATE TABLE logs (id INTEGER PRIMARY KEY, message TEXT); INSERT INTO logs VALUES (1, 'System started');"

# Passphrase
echo "mock-test-passphrase-devops" > "${TEST_DIR}/secrets/passphrase.txt"

# Test configuration
cat <<EOF > "${TEST_DIR}/test-backup.conf"
BACKUP_DIR="${TEST_DIR}/backups"
RETENTION_DAYS=7
SQLITE_DB_PATHS="${TEST_DIR}/dbs/app.db ${TEST_DIR}/dbs/audit.db"
ENCRYPTION_MODE="symmetric"
GPG_PASSPHRASE_FILE="${TEST_DIR}/secrets/passphrase.txt"
S3_ENABLED="false"
TELEGRAM_ALERT_ENABLED="false"
EOF

echo "[*] Running backup execution..."
./bin/backup-run.sh "${TEST_DIR}/test-backup.conf"

echo "[*] Running automated DR restore drill..."
./bin/dr-drill.sh "${TEST_DIR}/test-backup.conf"

echo "[✓] Integration test suite passed successfully!"
