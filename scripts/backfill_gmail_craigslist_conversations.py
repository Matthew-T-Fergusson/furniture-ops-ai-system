#!/usr/bin/env python3
"""public-tracker: Backfill Gmail/Craigslist conversations into the conversation layer.

Scope v1:
- Gmail Craigslist relay messages (`*@reply.craigslist.org`) as craigslist_email.
- Gmail Craigslist chat notifications (`robot@craigslist.org`, subject `new craigslist chat message`) as craigslist_chat system messages.
- Skips non-conversation Craigslist account/posting system notices.

Operational decision (2026-06-02): these generic chat-notification emails are the gate for
browser chat capture. They intentionally do not try to infer listing/contact/message content from
Gmail alone because Craigslist does not include those details in the notification body. A later
browser capture workflow should run only when a new notification appears, then map actual chat text.

Pipeline:
1. Search Gmail messages.
2. Capture raw + normalized payloads via normalize_gmail_conversation_message.py.
3. Upsert conversation_threads/conversation_messages.
4. Run matching and workflow helpers unless disabled.
"""
from __future__ import annotations

import argparse
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]  # repository root
WORKSPACE = ROOT.parent
NORMALIZER = ROOT / "scripts" / "normalize_gmail_conversation_message.py"
LINKER = ROOT / "scripts" / "link_conversation_records.py"
WORKFLOW = ROOT / "scripts" / "apply_conversation_workflow_rules.py"

DEFAULT_QUERY = "newer_than:30d (from:reply.craigslist.org OR from:robot@craigslist.org OR to:reply.craigslist.org OR to:sale.craigslist.org)"


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


def psql_command() -> list[str]:
    explicit = os.environ.get("FURNITURE_DB_PSQL")
    if explicit:
        return shlex.split(explicit)
    return ["docker", "exec", "-i", os.environ.get("FURNITURE_DB_DOCKER_CONTAINER", "lex-postgres"), "psql", "-U", os.environ.get("FURNITURE_DB_USER", "lex"), "-d", os.environ.get("FURNITURE_DB_NAME", "inspiring_works_llc")]


def q(value: object) -> str:
    if value is None:
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def search_messages(query: str, max_results: int, account: str | None) -> list[dict]:
    cmd = ["gog", "gmail", "messages", "search", query, "--max", str(max_results), "--json", "--no-input"]
    if account:
        cmd += ["--account", account]
    data = json.loads(require_ok(run(cmd), "gog gmail messages search"))
    return data.get("messages", [])


def classify(row: dict) -> tuple[str, str] | None:
    subject = (row.get("subject") or "").lower()
    sender = (row.get("from") or "").lower()
    labels = set(row.get("labels") or [])
    if "new craigslist chat message" in subject and "robot@craigslist.org" in sender:
        return "craigslist_chat", "system"
    if "reply.craigslist.org" in sender:
        return "craigslist_email", "inbound"
    # Sent outbound replies are found via to:reply.craigslist.org but search row sender is usually Lex.
    if "SENT" in labels or subject.startswith("re:"):
        return "craigslist_email", "outbound"
    # Posting/account notices are useful for listing ops but are not conversation leads for public-tracker.
    return None


def normalize_message(message_id: str, platform: str, direction: str, account: str | None) -> Path:
    cmd = [sys.executable, str(NORMALIZER), message_id, "--platform", platform, "--direction", direction]
    if account:
        cmd += ["--account", account]
    out = json.loads(require_ok(run(cmd), f"normalize {message_id}"))
    return WORKSPACE / out["normalized"]


def upsert_normalized(norm_path: Path) -> None:
    m = json.loads(norm_path.read_text())
    source_urls = m.get("source_urls") or []
    chat_url = next((u for u in source_urls if "craigslist.org" in u and "#chat=" in u), None)
    source_conversation_url = chat_url or m.get("message_url")

    if m["platform"] == "craigslist_chat" and m["direction"] == "system":
        # Craigslist chat notification emails are deliberately stored as system/capture-needed
        # rows. They are not buyer messages and usually lack listing/contact context; the actual
        # thread text must be captured from the logged-in Craigslist chat UI before matching.
        purpose = "unknown"
        stage = "needs_reply"
        needs_reply = "true"
        summary = "Craigslist on-site chat notification from robot@craigslist.org. Actual chat content may require Craigslist login/session capture."
    elif m["direction"] == "outbound":
        purpose = "sale_inquiry"
        stage = "waiting_on_other_party"
        needs_reply = "false"
        summary = "Craigslist email relay conversation backfilled from Gmail."
    else:
        purpose = "sale_inquiry"
        stage = "needs_reply"
        needs_reply = "true"
        summary = "Craigslist email relay conversation backfilled from Gmail."

    # Thread upsert is intentionally conservative: only sets current state when inserting, or updates timestamps/summary/raw paths idempotently.
    sql = f"""
BEGIN;
INSERT INTO public.conversation_threads (
  platform, source_account, source_thread_id, source_conversation_url, purpose, stage, priority,
  last_message_at, last_inbound_at, last_outbound_at, needs_reply, thread_summary, raw_thread_path, source_system
)
VALUES (
  {q(m['platform'])}, {q(m['source_account'])}, {q(m['source_thread_id'])}, {q(source_conversation_url)},
  {q(purpose)}, {q(stage)}, 'normal', {q(m['message_at'])}::timestamptz,
  CASE WHEN {q(m['direction'])} IN ('inbound','system') THEN {q(m['message_at'])}::timestamptz ELSE NULL END,
  CASE WHEN {q(m['direction'])} = 'outbound' THEN {q(m['message_at'])}::timestamptz ELSE NULL END,
  {needs_reply}, {q(summary)}, {q(m['raw_message_path'])}, 'backfill_gmail_craigslist_conversations.py'
)
ON CONFLICT (platform, source_account, source_thread_id) WHERE source_thread_id IS NOT NULL
DO UPDATE SET
  source_conversation_url = coalesce(public.conversation_threads.source_conversation_url, EXCLUDED.source_conversation_url),
  last_message_at = greatest(coalesce(public.conversation_threads.last_message_at, EXCLUDED.last_message_at), EXCLUDED.last_message_at),
  last_inbound_at = greatest(coalesce(public.conversation_threads.last_inbound_at, EXCLUDED.last_inbound_at), coalesce(EXCLUDED.last_inbound_at, public.conversation_threads.last_inbound_at)),
  last_outbound_at = greatest(coalesce(public.conversation_threads.last_outbound_at, EXCLUDED.last_outbound_at), coalesce(EXCLUDED.last_outbound_at, public.conversation_threads.last_outbound_at)),
  thread_summary = coalesce(public.conversation_threads.thread_summary, EXCLUDED.thread_summary),
  raw_thread_path = coalesce(public.conversation_threads.raw_thread_path, EXCLUDED.raw_thread_path),
  updated_at = now();

INSERT INTO public.conversation_messages (
  conversation_thread_id, platform, source_account, source_message_id, source_thread_id, message_at,
  direction, sender_raw, recipient_raw, subject, body_text, body_preview, message_url, raw_message_path,
  has_attachments, attachments_json, ingest_status, source_system
)
SELECT
  t.conversation_thread_id, {q(m['platform'])}, {q(m['source_account'])}, {q(m['source_message_id'])}, {q(m['source_thread_id'])}, {q(m['message_at'])}::timestamptz,
  {q(m['direction'])}, {q(m.get('sender_raw'))}, {q(m.get('recipient_raw'))}, {q(m.get('subject'))}, {q(m.get('body_text'))}, {q(m.get('body_preview'))}, {q(source_conversation_url)}, {q(m.get('raw_message_path'))},
  {str(bool(m.get('has_attachments'))).lower()}, {q(json.dumps(m.get('attachments_json') or []))}::jsonb, 'parsed', 'backfill_gmail_craigslist_conversations.py'
FROM public.conversation_threads t
WHERE t.platform = {q(m['platform'])}
  AND t.source_account = {q(m['source_account'])}
  AND t.source_thread_id = {q(m['source_thread_id'])}
ON CONFLICT (platform, source_account, source_message_id) WHERE source_message_id IS NOT NULL
DO UPDATE SET
  conversation_thread_id = EXCLUDED.conversation_thread_id,
  message_at = EXCLUDED.message_at,
  direction = EXCLUDED.direction,
  sender_raw = EXCLUDED.sender_raw,
  recipient_raw = EXCLUDED.recipient_raw,
  subject = EXCLUDED.subject,
  body_text = EXCLUDED.body_text,
  body_preview = EXCLUDED.body_preview,
  message_url = EXCLUDED.message_url,
  raw_message_path = EXCLUDED.raw_message_path,
  ingest_status = EXCLUDED.ingest_status;
COMMIT;
"""
    require_ok(run(psql_command() + ["-v", "ON_ERROR_STOP=1", "-X", "-q"], input_text=sql), f"upsert {m['source_message_id']}")


def readback() -> str:
    sql = r"""
SELECT 'threads=' || count(*) FROM public.conversation_threads;
SELECT 'messages=' || count(*) FROM public.conversation_messages;
SELECT conversation_thread_id || '|' || platform || '|' || stage || '|' || needs_reply || '|' || coalesce(queue_reason,'') || '|' || coalesce(queue_urgency,'') || '|' || coalesce(left(latest_body_preview,120),'')
FROM public.active_conversation_queue
ORDER BY queue_sort_bucket, queue_sort_at NULLS LAST, conversation_thread_id;
"""
    return require_ok(run(psql_command() + ["-v", "ON_ERROR_STOP=1", "-X", "-q", "-At"], input_text=sql), "readback")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--query", default=DEFAULT_QUERY)
    ap.add_argument("--max", type=int, default=50)
    ap.add_argument("--account")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--skip-helpers", action="store_true")
    args = ap.parse_args()

    rows = search_messages(args.query, args.max, args.account)
    processed, skipped = [], []
    for row in rows:
        cls = classify(row)
        if not cls:
            skipped.append({"id": row.get("id"), "subject": row.get("subject"), "reason": "non_conversation_notice"})
            continue
        platform, direction = cls
        item = {"id": row["id"], "subject": row.get("subject"), "platform": platform, "direction": direction}
        if not args.dry_run:
            norm = normalize_message(row["id"], platform, direction, args.account)
            upsert_normalized(norm)
            item["normalized"] = str(norm.relative_to(WORKSPACE))
        processed.append(item)

    if not args.dry_run and not args.skip_helpers:
        require_ok(run([sys.executable, str(LINKER), "--apply"]), "link helper")
        require_ok(run([sys.executable, str(WORKFLOW), "--apply"]), "workflow helper")

    print(json.dumps({"processed": processed, "skipped": skipped, "readback": None if args.dry_run else readback().strip().splitlines()}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
