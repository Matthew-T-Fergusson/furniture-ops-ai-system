# Backup + Recovery Model

This public portfolio version documents the disaster-recovery pattern without publishing private backup files, secrets, Drive folder IDs, account IDs, or real operational data.

## Design goal

A full restore after a VPS or disk loss requires three separate pieces:

1. **Code and runbooks** in GitHub — schema, scripts, docs, tests, and restore procedure.
2. **Encrypted database backup** stored offsite — never committed to git.
3. **Decryption passphrase** stored separately — password manager / owner-held copy, not in the repo and not in the offsite backup folder.

Keeping these separate limits blast radius:

- GitHub leak alone does not expose business data.
- Offsite backup leak alone does not expose business data without the passphrase.
- VPS loss does not destroy the offsite backup.

## Recommended backup package

A production deployment should create an encrypted package containing:

- `full_dump.dump` — Postgres custom-format dump for full restore.
- `tables/*.csv` — table-level exports for inspection/selective repair.
- `manifest.json` — table row counts, checksums, environment metadata.
- `restore_instructions.md` — concise restore guide bundled with the backup.

Only encrypted artifacts should leave the host:

```text
furniture_db_backup_<timestamp>.zip.enc
furniture_db_backup_<timestamp>.zip.enc.sha256
```

## Local schedule

1. Create encrypted backup daily.
2. Keep local encrypted packages for a short retention window, e.g. 30 days.
3. Upload the latest encrypted package and checksum to offsite storage after local backup succeeds.
4. Run periodic restore drills from the offsite copy, not only local disk.

## Total VPS-loss restore path

1. Provision a replacement host.
2. Install Docker/Postgres/client tooling and runtime dependencies.
3. Clone the GitHub repo.
4. Retrieve the newest encrypted backup and matching checksum from offsite storage.
5. Verify checksum:

```bash
sha256sum -c furniture_db_backup_<timestamp>.zip.enc.sha256
```

6. Recover the passphrase from the separate secret store.
7. Run a restore drill into a throwaway DB first.
8. Restore into the replacement live DB only after the drill succeeds.
9. Run schema validation, guardrails, analytics refresh, and smoke checks.
10. Reinstall backup/offsite-upload cron jobs.

## Privacy rules

Do not commit:

- backup packages
- decrypted zips/dumps/CSVs
- `.env` files
- passphrases
- OAuth tokens
- Drive folder IDs for private deployments
- real customer/partner names, addresses, phone numbers, receipt images, storage-unit access codes, or legal documents

This repo’s `.gitignore` blocks common secret and backup paths, but do not rely on `.gitignore` alone. Review diffs before every push.
