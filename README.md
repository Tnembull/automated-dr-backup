# Disaster Recovery & Encrypted Backup Automation

Production-grade disaster recovery solution providing zero-downtime database snapshots, AES-256 GPG encryption, lifecycle retention pruning, Cloud Object Storage replication (S3/Cloudflare R2), and **automated integrity recovery drills**.

---

## 🎯 The Core Philosophy
> *"An untested backup is merely an assumption, not a backup."*

Standard backup scripts merely dump and upload files without ever verifying if the archives are corrupt or if data can actually be restored during an emergency. 

This repository implements a two-stage disaster recovery lifecycle:
1. **Automated Backup Engine (`backup-run.sh`)**:
   - Zero-lock atomic database snapshots (`sqlite3 .backup`).
   - SHA256 checksum generation for immutable audit verification.
   - GPG AES-256 symmetric/asymmetric encryption before data leaves local storage.
   - Cloud Object Storage sync (AWS S3 / Cloudflare R2 / MinIO).
   - Automated Telegram incident notifications.
2. **Continuous Disaster Recovery Drill (`dr-drill.sh`)**:
   - Decrypts the latest production archive in an isolated sandbox.
   - Decompresses and executes database level structural integrity checks (`PRAGMA integrity_check`).
   - Fails loudly with non-zero exit codes if corruption or missing tables are detected.

---

## 📁 Repository Structure

```text
├── bin/
│   ├── backup-run.sh                 # Backup, snapshot, encryption, and sync engine
│   └── dr-drill.sh                   # Sandbox decrypt & integrity verification drill
├── config/
│   └── backup.conf.example           # Sanitized configuration template
├── tests/
│   └── test_backup_and_drill.sh      # Automated end-to-end integration test suite
└── .github/workflows/
    └── ci.yml                        # ShellCheck static analysis & E2E runner
```

---

## 🚀 Quickstart & Usage

### 1. Configuration
Copy the configuration template:
```bash
cp config/backup.conf.example config/backup.conf
```
Configure your database paths, encryption passphrase/key, and cloud bucket parameters.

### 2. Run Scheduled Backup
```bash
./bin/backup-run.sh config/backup.conf
```

### 3. Run Automated Disaster Recovery Drill
Verify that your latest backup can actually be restored:
```bash
./bin/dr-drill.sh config/backup.conf
```

### 4. Automated Testing
Run the sandbox test suite locally:
```bash
./tests/test_backup_and_drill.sh
```

---

## 🛡️ Security & Zero Leak Posture
- Secrets (GPG keys, passphrases, cloud tokens) are never stored in version control.
- All live configurations (`*.conf`, `*.key`, `*.txt`) are excluded in `.gitignore`.
- Backups are encrypted at rest using AES-256 before transit.

---
**Author**: Muhammad Nur Ashiddiqi  
**Portfolio**: [muhammadnurashiddiqi.my.id](https://muhammadnurashiddiqi.my.id)
