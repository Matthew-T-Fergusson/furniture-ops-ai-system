#!/usr/bin/env bash
# Upload encrypted backup artifacts to Google Drive with gog.
#
# Public-safe reference script. Configure account/folder through environment
# variables; do not hard-code private Drive folder IDs in a public repo.
#
# Required:
# - GOG_ACCOUNT: Google account configured in gog
# - DRIVE_FOLDER_ID: destination folder ID
# Optional:
# - BACKUP_DIR: directory containing *.zip.enc files

set -euo pipefail

: "${BACKUP_DIR:=./backups}"
: "${GOG_ACCOUNT:?GOG_ACCOUNT is required}"
: "${DRIVE_FOLDER_ID:?DRIVE_FOLDER_ID is required}"

latest="$(ls -t "${BACKUP_DIR}"/furniture_db_backup_*.zip.enc 2>/dev/null | head -1 || true)"
if [[ -z "${latest}" ]]; then
  echo "No encrypted backup found under ${BACKUP_DIR}" >&2
  exit 1
fi
checksum="${latest}.sha256"
if [[ ! -f "${checksum}" ]]; then
  echo "Missing checksum file: ${checksum}" >&2
  exit 1
fi

# Only upload encrypted package + checksum. Never upload decrypted .zip, dumps,
# CSV exports, or passphrase files.
gog drive upload "${latest}" --account "${GOG_ACCOUNT}" --parent "${DRIVE_FOLDER_ID}" --json --no-input
gog drive upload "${checksum}" --account "${GOG_ACCOUNT}" --parent "${DRIVE_FOLDER_ID}" --json --no-input
