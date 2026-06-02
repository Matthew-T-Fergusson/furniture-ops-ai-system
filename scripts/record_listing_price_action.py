#!/usr/bin/env python3
"""Deterministic listing/price update writer with public-tracker action logging.

This is the first workflow integration for agent_action_log. It creates/updates a
row in listings, appends listing_price_history when price is provided, updates the
linked inventory status/listing identity, and records before/after guardrail
summaries in agent_action_log.

Default connection targets local Docker Postgres. Override via FURNITURE_DB_PSQL.

Listing-versioning decision (public-tracker/public-tracker): a marketplace repost is a new version in the
same listing_series_id, not a disconnected row. When recording a newly discovered live URL/ID for
an inventory item, reuse the current series when present, supersede the prior current listing, and
mark the new row current. This keeps conversation matching stable across Craigslist reposts.
"""
from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys
from decimal import Decimal, InvalidOperation

VALID_LISTING_STATUSES = {"draft", "active", "paused", "pending", "sold", "delisted", "cancelled"}


def quote(value: str | None) -> str:
    if value is None:
        return "NULL"
    return "'" + value.replace("'", "''") + "'"


def quote_num(value: str | None) -> str:
    if value is None or value == "":
        return "NULL"
    try:
        return str(Decimal(value))
    except InvalidOperation as exc:
        raise SystemExit(f"invalid decimal value: {value!r}") from exc


def psql_command() -> list[str]:
    explicit = os.environ.get("FURNITURE_DB_PSQL")
    if explicit:
        return shlex.split(explicit)
    container = os.environ.get("FURNITURE_DB_DOCKER_CONTAINER", "lex-postgres")
    user = os.environ.get("FURNITURE_DB_USER", "lex")
    db = os.environ.get("FURNITURE_DB_NAME", "inspiring_works_llc")
    return ["docker", "exec", "-i", container, "psql", "-U", user, "-d", db]


def run_sql(sql: str, *, dry_run: bool) -> int:
    if dry_run:
        print(sql)
        return 0
    cmd = psql_command() + ["-v", "ON_ERROR_STOP=1", "-X", "-q"]
    proc = subprocess.run(cmd, input=sql, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.stdout:
        print(proc.stdout, end="")
    if proc.stderr:
        print(proc.stderr, end="", file=sys.stderr)
    return proc.returncode


def clipped(text: str | None, n: int = 500) -> str | None:
    if text is None:
        return None
    return text[:n]


def build_sql(args: argparse.Namespace) -> str:
    inventory_status = "listed_active" if args.listing_status == "active" else None
    mutation_summary = (
        f"Upsert {args.platform} listing for inventory_uid={args.inventory_uid}; "
        f"status={args.listing_status}; price={args.price or 'unchanged'}; url={args.listing_url or 'n/a'}"
    )

    return f"""
BEGIN;

WITH before_guardrails AS (
  SELECT coalesce(jsonb_agg(row_to_json(x)::jsonb ORDER BY x.severity, x.anomaly_type), '[]'::jsonb) AS summary
  FROM (
    SELECT severity, anomaly_type, count(*) AS count
    FROM furniture_db_guardrail_anomalies
    GROUP BY severity, anomaly_type
  ) x
), duplicate_real_listing AS (
  SELECT count(*) AS duplicate_count
  FROM listings
  WHERE platform = {quote(args.platform)}
    AND inventory_uid IS DISTINCT FROM {quote(args.inventory_uid)}
    AND (
      (
        external_listing_id = {quote(args.external_listing_id)}
        AND {quote(args.external_listing_id)} IS NOT NULL
        AND lower({quote(args.external_listing_id)}) NOT IN ('n/a','na','tbd','unknown')
      )
      OR (
        listing_url = {quote(args.listing_url)}
        AND {quote(args.listing_url)} IS NOT NULL
        AND lower({quote(args.listing_url)}) NOT IN ('n/a','na','tbd','unknown')
      )
    )
), existing_match AS (
  SELECT l.*
  FROM listings l
  WHERE l.inventory_uid = {quote(args.inventory_uid)}
    AND l.platform = {quote(args.platform)}
    AND (
      ({quote(args.external_listing_id)} IS NOT NULL AND l.external_listing_id = {quote(args.external_listing_id)})
      OR ({quote(args.listing_url)} IS NOT NULL AND l.listing_url = {quote(args.listing_url)})
    )
  ORDER BY l.listing_id DESC
  LIMIT 1
), current_series_listing AS (
  SELECT l.*
  FROM listings l
  WHERE l.inventory_uid = {quote(args.inventory_uid)}
    AND l.platform = {quote(args.platform)}
  ORDER BY l.is_current_version DESC, l.listing_id DESC
  LIMIT 1
), listing_series AS (
  -- Keep reposts/replacements in one logical listing series. Existing exact matches are idempotent;
  -- otherwise, use the item's current platform listing as the previous version and supersede it.
  SELECT
    coalesce(
      (SELECT listing_series_id FROM existing_match),
      (SELECT listing_series_id FROM current_series_listing),
      gen_random_uuid()
    ) AS listing_series_id,
    coalesce(
      (SELECT listing_id FROM existing_match),
      (SELECT listing_id FROM current_series_listing)
    ) AS supersedes_listing_id,
    CASE
      WHEN EXISTS (SELECT 1 FROM existing_match) THEN (SELECT listing_version_no FROM existing_match)
      ELSE coalesce((
        SELECT max(listing_version_no)
        FROM listings l
        WHERE l.listing_series_id = coalesce(
          (SELECT listing_series_id FROM current_series_listing),
          (SELECT listing_series_id FROM existing_match)
        )
      ), 0) + 1
    END AS listing_version_no
), supersede_prior_current AS (
  -- Only a genuinely new listing version supersedes the previous current version. Updating an
  -- existing exact URL/external ID should remain idempotent and must not close itself out.
  UPDATE listings l
  SET is_current_version = false,
      valid_to = now(),
      updated_at = now()
  FROM current_series_listing c, listing_series s
  WHERE l.listing_id = c.listing_id
    AND NOT EXISTS (SELECT 1 FROM existing_match)
    AND (SELECT duplicate_count FROM duplicate_real_listing) = 0
  RETURNING l.listing_id
), upsert_listing AS (
  INSERT INTO listings (
    inventory_uid,
    platform,
    external_listing_id,
    listing_url,
    title,
    status,
    listed_at,
    current_asking_price,
    notes,
    source_system,
    listing_series_id,
    listing_version_no,
    supersedes_listing_id,
    valid_from,
    is_current_version,
    updated_at
  )
  SELECT
    {quote(args.inventory_uid)},
    {quote(args.platform)},
    {quote(args.external_listing_id)},
    {quote(args.listing_url)},
    {quote(args.title)},
    {quote(args.listing_status)},
    coalesce({quote(args.listed_at)}::timestamptz, now()),
    {quote_num(args.price)},
    {quote(args.notes)},
    'record_listing_price_action.py',
    (SELECT listing_series_id FROM listing_series),
    (SELECT listing_version_no FROM listing_series),
    CASE WHEN EXISTS (SELECT 1 FROM existing_match) THEN NULL ELSE (SELECT supersedes_listing_id FROM listing_series) END,
    now(),
    true,
    now()
  WHERE (SELECT duplicate_count FROM duplicate_real_listing) = 0
    AND NOT EXISTS (SELECT 1 FROM existing_match)
  ON CONFLICT DO NOTHING
  RETURNING listing_id
), chosen_listing AS (
  SELECT listing_id FROM upsert_listing
  UNION ALL
  SELECT listing_id
  FROM listings
  WHERE inventory_uid = {quote(args.inventory_uid)}
    AND platform = {quote(args.platform)}
    AND (
      ({quote(args.external_listing_id)} IS NOT NULL AND external_listing_id = {quote(args.external_listing_id)})
      OR ({quote(args.listing_url)} IS NOT NULL AND listing_url = {quote(args.listing_url)})
    )
  ORDER BY listing_id DESC
  LIMIT 1
), update_listing AS (
  UPDATE listings l
  SET listing_url = coalesce({quote(args.listing_url)}, l.listing_url),
      title = coalesce({quote(args.title)}, l.title),
      status = {quote(args.listing_status)},
      current_asking_price = coalesce({quote_num(args.price)}, l.current_asking_price),
      notes = coalesce({quote(args.notes)}, l.notes),
      updated_at = now()
  FROM chosen_listing c
  WHERE l.listing_id = c.listing_id
  RETURNING l.listing_id
), price_history AS (
  INSERT INTO listing_price_history (listing_id, price, changed_at, changed_by, reason, source_system)
  SELECT listing_id, {quote_num(args.price)}, now(), {quote(args.changed_by)}, {quote(args.reason)}, 'record_listing_price_action.py'
  FROM chosen_listing
  WHERE {quote_num(args.price)} IS NOT NULL
  RETURNING price_history_id
), inventory_update AS (
  UPDATE inventory i
  SET item_id = coalesce({quote(args.external_listing_id)}, i.item_id),
      cl_url = CASE WHEN {quote(args.platform)} = 'craigslist' THEN coalesce({quote(args.listing_url)}, i.cl_url) ELSE i.cl_url END,
      status = coalesce({quote(inventory_status)}, i.status),
      updated_at = now()
  WHERE i.inventory_uid = {quote(args.inventory_uid)}
  RETURNING i.inventory_uid
), after_guardrails AS (
  SELECT coalesce(jsonb_agg(row_to_json(x)::jsonb ORDER BY x.severity, x.anomaly_type), '[]'::jsonb) AS summary
  FROM (
    SELECT severity, anomaly_type, count(*) AS count
    FROM furniture_db_guardrail_anomalies
    GROUP BY severity, anomaly_type
  ) x
), action_log AS (
  INSERT INTO agent_action_log (
    skill_name,
    agent_identifier,
    prompt_version,
    chat_input_excerpt,
    mutation_summary,
    guardrails_before,
    guardrails_after,
    entity_type,
    entity_id,
    status,
    error_message
  )
  SELECT
    'furniture-listing-price-sync',
    {quote(args.agent_identifier)},
    {quote(args.prompt_version)},
    {quote(clipped(args.chat_input_excerpt))},
    {quote(mutation_summary)},
    (SELECT summary FROM before_guardrails),
    (SELECT summary FROM after_guardrails),
    'inventory',
    {quote(args.inventory_uid)},
    CASE
      WHEN (SELECT duplicate_count FROM duplicate_real_listing) > 0 THEN 'needs_review'
      WHEN NOT EXISTS (SELECT 1 FROM chosen_listing) THEN 'failed'
      ELSE 'applied'
    END,
    CASE
      WHEN (SELECT duplicate_count FROM duplicate_real_listing) > 0 THEN 'Duplicate real external listing ID/URL detected; mutation skipped.'
      WHEN NOT EXISTS (SELECT 1 FROM chosen_listing) THEN 'No listing row selected after insert/update attempt.'
      ELSE NULL
    END
  RETURNING action_id, status, error_message
)
SELECT action_id || '|' || status || '|' || coalesce(error_message,'') AS action_result
FROM action_log;

COMMIT;
"""


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Record listing/price workflow mutation with agent_action_log audit row")
    parser.add_argument("--inventory-uid", required=True)
    parser.add_argument("--platform", required=True, help="craigslist, facebook, etc.")
    parser.add_argument("--external-listing-id")
    parser.add_argument("--listing-url")
    parser.add_argument("--title")
    parser.add_argument("--price")
    parser.add_argument("--listing-status", default="active", choices=sorted(VALID_LISTING_STATUSES))
    parser.add_argument("--listed-at", help="ISO timestamp; defaults to now()")
    parser.add_argument("--notes")
    parser.add_argument("--reason", default="agent listing/price sync")
    parser.add_argument("--changed-by", default="Lex")
    parser.add_argument("--agent-identifier", default="Lex")
    parser.add_argument("--prompt-version", default="public-tracker-v1")
    parser.add_argument("--chat-input-excerpt")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="Print SQL without executing")
    mode.add_argument("--apply", action="store_true", help="Execute the mutation")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if not args.external_listing_id and not args.listing_url:
        raise SystemExit("provide at least one of --external-listing-id or --listing-url")
    if args.platform == "craigslist" and not args.listing_url:
        raise SystemExit("craigslist listing updates require --listing-url")
    if not args.apply and not args.dry_run:
        raise SystemExit("choose --dry-run to preview or --apply to execute")
    return run_sql(build_sql(args), dry_run=args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
