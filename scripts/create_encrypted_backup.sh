#!/usr/bin/env bash
# Create an encrypted Postgres backup package.
#
# This script is a public-safe reference implementation for the POC. It shows the
# structure used in production without embedding private database names, Drive
# folder IDs, passwords, or real data.
#
# Why this shape:
# - `pg_dump --format=custom` gives the fastest full restore path.
# - CSV exports make selective row/table repair easier after accidental deletes.
# - A manifest records row counts/checksums so restore drills can prove integrity.
# - OpenSSL encryption keeps offsite artifacts private if storage is compromised.
# - The passphrase must come from the environment or a secret manager, never git.

set -euo pipefail

: "${POSTGRES_DB:=furniture_ops_poc}"
: "${POSTGRES_USER:=furniture}"
: "${POSTGRES_HOST:=localhost}"
: "${POSTGRES_PORT:=55432}"
: "${BACKUP_OUT_DIR:=./backups}"
: "${BACKUP_RETENTION_DAYS:=30}"

if [[ -z "${FURNITURE_BACKUP_PASSPHRASE:-}" ]]; then
  echo "FURNITURE_BACKUP_PASSPHRASE is required and must not be committed" >&2
  exit 1
fi

mkdir -p "${BACKUP_OUT_DIR}"
chmod 700 "${BACKUP_OUT_DIR}" || true

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
name="furniture_db_backup_${stamp}"
work_dir="${BACKUP_OUT_DIR}/${name}"
tables_dir="${work_dir}/tables"
mkdir -p "${tables_dir}"

psql_cmd=(psql "postgresql://${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}" -v ON_ERROR_STOP=1 -At)
pg_dump_cmd=(pg_dump "postgresql://${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}" --format=custom --no-owner --no-privileges)

"${pg_dump_cmd[@]}" > "${work_dir}/full_dump.dump"

tables="$(${psql_cmd[@]} -c "SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY table_name;")"
{
  echo '{'
  echo "  \"backup_name\": \"${name}\","
  echo "  \"created_at_utc\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"database\": \"${POSTGRES_DB}\","
  echo '  "tables": {'
  first=1
  while IFS= read -r table; do
    [[ -z "${table}" ]] && continue
    csv="${tables_dir}/${table}.csv"
    psql "postgresql://${POSTGRES_USER}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}" \
      -v ON_ERROR_STOP=1 \
      -c "COPY public.\"${table//\"/\"\"}\" TO STDOUT WITH (FORMAT csv, HEADER true);" > "${csv}"
    count="$(${psql_cmd[@]} -c "SELECT count(*) FROM public.\"${table//\"/\"\"}\";")"
    sha="$(sha256sum "${csv}" | awk '{print $1}')"
    if [[ "${first}" -eq 0 ]]; then echo ','; fi
    first=0
    printf '    "%s": {"row_count": %s, "csv_path": "tables/%s.csv", "csv_sha256": "%s"}' "${table}" "${count}" "${table}" "${sha}"
  done <<< "${tables}"
  echo
  echo '  }'
  echo '}'
} > "${work_dir}/manifest.json"

cat > "${work_dir}/restore_instructions.md" <<'EOF'
# Restore instructions

1. Verify checksum for the encrypted package.
2. Decrypt with the separately stored passphrase.
3. Restore to a throwaway DB first.
4. Compare table counts against manifest.json.
5. Restore/replace live DB only after explicit confirmation.
EOF

zip_path="${BACKUP_OUT_DIR}/${name}.zip"
enc_path="${zip_path}.enc"
(
  cd "${work_dir}"
  zip -qr "${zip_path}" .
)

openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt \
  -in "${zip_path}" \
  -out "${enc_path}" \
  -pass env:FURNITURE_BACKUP_PASSPHRASE
sha256sum "${enc_path}" > "${enc_path}.sha256"
rm -f "${zip_path}"
rm -rf "${work_dir}"
find "${BACKUP_OUT_DIR}" -name 'furniture_db_backup_*' -mtime +"${BACKUP_RETENTION_DAYS}" -delete
chmod 600 "${enc_path}" "${enc_path}.sha256" || true

printf '{"backup":"%s","sha256":"%s"}\n' "${enc_path}" "$(sha256sum "${enc_path}" | awk '{print $1}')"
