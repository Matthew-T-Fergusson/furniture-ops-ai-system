#!/usr/bin/env python3
"""Run furniture conversation monitoring with low-noise actionable output.

This wraps public-tracker backfill + active_conversation_queue readback for scheduled or ad hoc use.
It prints a concise alert only when queue items are new/changed since the last run, unless --force-report is used.

Operational decision (2026-06-02): Craigslist browser chat capture should be notification-gated.
The scheduled monitor checks Gmail first; a generic Craigslist "new chat message" email is the trigger
for a separate browser capture workflow. If no new notification email appears, do not run routine
browser chat scans just to look for messages.

Lead-quality decision (2026-06-02): lead_quality_* fields are human-reviewed only for now.
the operator/the operator should label early examples and outcomes before any AI/content classifier is added.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shlex
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKSPACE = ROOT.parent
BACKFILL = ROOT / "scripts" / "backfill_gmail_craigslist_conversations.py"
STATE_PATH = ROOT / "data" / "furniture_conversations" / "monitor_state.json"

QUEUE_SQL = r"""
SELECT coalesce(jsonb_agg(row_to_json(q) ORDER BY queue_sort_bucket, queue_sort_at NULLS LAST, conversation_thread_id), '[]'::jsonb)::text
FROM (
  SELECT
    conversation_thread_id,
    platform,
    purpose,
    stage,
    needs_reply,
    queue_reason,
    queue_urgency,
    lead_quality_tag,
    lead_quality_reviewed_by,
    lead_quality_reviewed_at,
    lead_quality_notes,
    assigned_to,
    contact_name,
    contact_username,
    listing_title,
    listing_url,
    source_conversation_url,
    latest_subject,
    latest_body_preview,
    last_message_at,
    last_inbound_at,
    last_outbound_at,
    next_action_at,
    next_action_note,
    queue_sort_bucket,
    queue_sort_at
  FROM public.active_conversation_queue
) q;
"""


def psql_command() -> list[str]:
    explicit = os.environ.get("FURNITURE_DB_PSQL")
    if explicit:
        return shlex.split(explicit)
    return ["docker", "exec", "-i", os.environ.get("FURNITURE_DB_DOCKER_CONTAINER", "lex-postgres"), "psql", "-U", os.environ.get("FURNITURE_DB_USER", "lex"), "-d", os.environ.get("FURNITURE_DB_NAME", "inspiring_works_llc")]


def run(cmd: list[str], *, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, input=input_text, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)


def require_ok(proc: subprocess.CompletedProcess[str], label: str) -> str:
    if proc.returncode != 0:
        sys.stderr.write(f"{label} failed with exit {proc.returncode}\n")
        if proc.stdout:
            sys.stderr.write(proc.stdout)
        if proc.stderr:
            sys.stderr.write(proc.stderr)
        raise SystemExit(proc.returncode)
    return proc.stdout or ""


def load_state() -> dict:
    if STATE_PATH.exists():
        return json.loads(STATE_PATH.read_text())
    return {"notified": {}}


def save_state(state: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    state["updated_at"] = datetime.now(timezone.utc).isoformat()
    STATE_PATH.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")


def fetch_queue() -> list[dict]:
    out = require_ok(run(psql_command() + ["-v", "ON_ERROR_STOP=1", "-X", "-q", "-At"], input_text=QUEUE_SQL), "fetch active_conversation_queue")
    return json.loads(out.strip() or "[]")


def fingerprint(item: dict) -> str:
    relevant = {
        "thread": item.get("conversation_thread_id"),
        "platform": item.get("platform"),
        "stage": item.get("stage"),
        "needs_reply": item.get("needs_reply"),
        "queue_reason": item.get("queue_reason"),
        "queue_urgency": item.get("queue_urgency"),
        "latest_subject": item.get("latest_subject"),
        "latest_body_preview": item.get("latest_body_preview"),
        "last_message_at": item.get("last_message_at"),
        "next_action_at": item.get("next_action_at"),
        "next_action_note": item.get("next_action_note"),
        "lead_quality_tag": item.get("lead_quality_tag"),
    }
    return hashlib.sha256(json.dumps(relevant, sort_keys=True, default=str).encode()).hexdigest()


def summarize(items: list[dict]) -> str:
    if not items:
        return ""
    lines = ["Furniture conversation queue has actionable items:"]
    for item in items[:8]:
        title = item.get("listing_title") or item.get("latest_subject") or item.get("thread_summary") or "Conversation"
        preview = (item.get("latest_body_preview") or "").replace("\r", " ").replace("\n", " ").strip()
        if len(preview) > 180:
            preview = preview[:177] + "..."
        url = item.get("source_conversation_url") or item.get("listing_url") or ""
        lines.append(
            f"- [{item.get('queue_urgency')}] {item.get('platform')} / {item.get('queue_reason')}: {title}"
        )
        if item.get("assigned_to"):
            lines.append(f"  Owner: {item.get('assigned_to')}")
        if item.get("lead_quality_tag"):
            lines.append(f"  Lead quality: {item.get('lead_quality_tag')}")
        if preview:
            lines.append(f"  Preview: {preview}")
        if url:
            lines.append(f"  Link: {url}")
    if len(items) > 8:
        lines.append(f"…and {len(items)-8} more.")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--max", type=int, default=50)
    ap.add_argument("--force-report", action="store_true", help="Print queue even if unchanged")
    ap.add_argument("--no-backfill", action="store_true", help="Only read/report the queue")
    args = ap.parse_args()

    if not args.no_backfill:
        require_ok(run([sys.executable, str(BACKFILL), "--max", str(args.max)]), "conversation backfill")

    queue = fetch_queue()
    state = load_state()
    notified = state.setdefault("notified", {})
    changed = []
    for item in queue:
        key = str(item.get("conversation_thread_id"))
        fp = fingerprint(item)
        if args.force_report or notified.get(key) != fp:
            changed.append(item)
            notified[key] = fp

    # Drop notification fingerprints for items no longer in queue.
    active_keys = {str(i.get("conversation_thread_id")) for i in queue}
    for key in list(notified.keys()):
        if key not in active_keys:
            notified.pop(key, None)

    save_state(state)

    if changed:
        print(summarize(changed))
    else:
        print("NO_ACTIONABLE_CHANGES")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
