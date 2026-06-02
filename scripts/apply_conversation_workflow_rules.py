#!/usr/bin/env python3
"""Apply public-tracker v1 conversation workflow rules.

Rules implemented:
- terminal stages (completed/dead/spam/archived) => needs_reply=false
- new => needs_reply=true
- latest inbound/system/internal_note on active thread => needs_reply=true
- waiting_on_other_party with last outbound >=24h ago and no later inbound => needs_reply=true + follow-up note

This is intentionally light-weight. It reinforces DB state after ingestion without trying to become a full workflow engine.
Lead queue/reporting belongs to public-tracker.
"""
from __future__ import annotations

import argparse
import os
import shlex
import subprocess
import sys

SQL_APPLY = r"""
BEGIN;

WITH latest_message AS (
  SELECT DISTINCT ON (conversation_thread_id)
    conversation_thread_id,
    direction,
    message_at
  FROM public.conversation_messages
  ORDER BY conversation_thread_id, message_at DESC, conversation_message_id DESC
), rule_eval AS (
  SELECT
    t.conversation_thread_id,
    t.stage AS old_stage,
    t.needs_reply AS old_needs_reply,
    t.next_action_note AS old_next_action_note,
    lm.direction AS latest_direction,
    lm.message_at AS latest_message_at,
    CASE
      WHEN t.stage IN ('completed','dead','spam','archived') THEN false
      WHEN t.stage = 'new' THEN true
      WHEN lm.direction IN ('inbound','system','internal_note') THEN true
      WHEN t.stage = 'waiting_on_other_party'
        AND t.last_outbound_at IS NOT NULL
        AND t.last_outbound_at <= now() - interval '24 hours'
        AND (t.last_inbound_at IS NULL OR t.last_inbound_at < t.last_outbound_at)
        THEN true
      WHEN t.next_action_at IS NOT NULL AND t.next_action_at <= now() THEN true
      ELSE t.needs_reply
    END AS new_needs_reply,
    CASE
      WHEN t.stage = 'waiting_on_other_party'
        AND t.last_outbound_at IS NOT NULL
        AND t.last_outbound_at <= now() - interval '24 hours'
        AND (t.last_inbound_at IS NULL OR t.last_inbound_at < t.last_outbound_at)
        AND t.stage NOT IN ('completed','dead','spam','archived')
        THEN '24h follow-up due'
      ELSE t.next_action_note
    END AS new_next_action_note
  FROM public.conversation_threads t
  LEFT JOIN latest_message lm USING (conversation_thread_id)
), updated AS (
  UPDATE public.conversation_threads t
  SET needs_reply = r.new_needs_reply,
      next_action_note = r.new_next_action_note,
      updated_at = now()
  FROM rule_eval r
  WHERE t.conversation_thread_id = r.conversation_thread_id
    AND (
      t.needs_reply IS DISTINCT FROM r.new_needs_reply
      OR t.next_action_note IS DISTINCT FROM r.new_next_action_note
    )
  RETURNING
    t.conversation_thread_id,
    r.old_stage,
    r.old_needs_reply,
    t.needs_reply AS new_needs_reply,
    r.old_next_action_note,
    t.next_action_note AS new_next_action_note,
    r.latest_direction,
    r.latest_message_at
)
SELECT coalesce(jsonb_pretty(jsonb_agg(to_jsonb(updated) ORDER BY conversation_thread_id)), '[]'::text::jsonb::text)
FROM updated;

COMMIT;
"""

SQL_PREVIEW = SQL_APPLY.replace("BEGIN;", "BEGIN;").replace("COMMIT;", "ROLLBACK;")

SQL_READBACK = r"""
SELECT
  conversation_thread_id || E'\t' ||
  platform || E'\t' ||
  stage || E'\t' ||
  needs_reply::text || E'\t' ||
  coalesce(next_action_note,'') || E'\t' ||
  coalesce(thread_summary,'')
FROM public.conversation_threads
ORDER BY conversation_thread_id;
"""


def psql_command() -> list[str]:
    explicit = os.environ.get("FURNITURE_DB_PSQL")
    if explicit:
        return shlex.split(explicit)
    container = os.environ.get("FURNITURE_DB_DOCKER_CONTAINER", "lex-postgres")
    user = os.environ.get("FURNITURE_DB_USER", "lex")
    db = os.environ.get("FURNITURE_DB_NAME", "inspiring_works_llc")
    return ["docker", "exec", "-i", container, "psql", "-U", user, "-d", db]


def run_sql(sql: str, *, tuples_only: bool = True) -> subprocess.CompletedProcess[str]:
    cmd = psql_command() + ["-v", "ON_ERROR_STOP=1", "-X", "-q"]
    if tuples_only:
        cmd.append("-At")
    return subprocess.run(cmd, input=sql, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)


def require_ok(proc: subprocess.CompletedProcess[str], label: str) -> str:
    if proc.returncode != 0:
        sys.stderr.write(f"{label} failed with exit {proc.returncode}\n")
        if proc.stdout:
            sys.stderr.write(proc.stdout)
        if proc.stderr:
            sys.stderr.write(proc.stderr)
        raise SystemExit(proc.returncode)
    return proc.stdout or ""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--apply", action="store_true", help="Apply changes. Without this, preview and roll back.")
    ap.add_argument("--readback", action="store_true", help="Print thread state after preview/apply.")
    args = ap.parse_args()

    sql = SQL_APPLY if args.apply else SQL_PREVIEW
    out = require_ok(run_sql(sql), "apply conversation workflow rules" if args.apply else "preview conversation workflow rules")
    print(out.strip() or "[]")
    if args.readback:
        rb = require_ok(run_sql(SQL_READBACK), "readback conversation threads")
        print("\nconversation_thread_id\tplatform\tstage\tneeds_reply\tnext_action_note\tthread_summary")
        print(rb.strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
