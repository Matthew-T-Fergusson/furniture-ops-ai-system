#!/usr/bin/env python3
"""Capture and normalize a Gmail message into furniture conversation storage.

public-tracker workflow note:
For v1, the operator or the operator can approve/send shared furniture-business replies without strict approval audit logging.
When a hired manager/non-owner operator starts approving or sending replies on behalf of the business,
add stricter approval/event logging before delegating that workflow (see public-tracker and CONVERSATION_WORKFLOW.md).

Writes:
- local_data/furniture_conversations/raw/{platform}/YYYY/MM/DD/gmail-message-{id}.json
- local_data/furniture_conversations/normalized/{platform}/YYYY/MM/DD/gmail-message-{id}.normalized.json

The normalized file is an ingest/debug bridge for conversation_threads/conversation_messages.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]  # repository root
WORKSPACE = ROOT.parent
CONV_ROOT = ROOT / "data" / "furniture_conversations"
PLATFORMS = {
    "craigslist_email",
    "craigslist_chat",
    "facebook_marketplace",
    "ebay",
    "telegram",
    "gmail",
    "sms",
    "manual",
    "other",
}

CRAIGSLIST_FOOTER_MARKERS = [
    "------------------------------------------------------------------------",
    "Original craigslist post:",
    "About craigslist mail:",
    "Please flag unwanted messages",
    "thanks for using craigslist",
    "try the app:",
]


def run_gog_get(message_id: str, account: str | None) -> dict:
    cmd = ["gog", "gmail", "get", message_id, "--json", "--no-input"]
    if account:
        cmd += ["--account", account]
    proc = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if proc.returncode != 0:
        raise SystemExit(f"gog gmail get failed ({proc.returncode}):\n{proc.stderr}")
    return json.loads(proc.stdout)


def parse_message_dt(headers: dict, fallback: datetime | None = None) -> datetime:
    raw = headers.get("date") or headers.get("Date")
    if raw:
        try:
            dt = parsedate_to_datetime(raw)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc)
        except Exception:
            pass
    return fallback or datetime.now(timezone.utc)


def normalize_body(body: str, platform: str) -> str:
    text = body or ""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    if platform in {"craigslist_email", "craigslist_chat"}:
        cut_positions = [text.find(marker) for marker in CRAIGSLIST_FOOTER_MARKERS if text.find(marker) >= 0]
        if cut_positions:
            text = text[: min(cut_positions)]
    # Keep paragraph breaks but normalize repeated whitespace inside lines.
    lines = [re.sub(r"[ \t]+", " ", line).strip() for line in text.split("\n")]
    while lines and not lines[0]:
        lines.pop(0)
    while lines and not lines[-1]:
        lines.pop()
    return "\n".join(lines).strip()


def source_urls(text: str) -> list[str]:
    urls = re.findall(r"https?://[^\s<>\"]+", text or "")
    out = []
    for url in urls:
        cleaned = url.rstrip(".,);]")
        if cleaned not in out:
            out.append(cleaned)
    return out


def craigslist_listing_urls(text: str) -> list[str]:
    out = []
    for cleaned in source_urls(text):
        if "craigslist.org" in cleaned and "/about/help/" not in cleaned and "/mailflag" not in cleaned and "/#chat=" not in cleaned:
            if cleaned not in out:
                out.append(cleaned)
    return out


def infer_direction(headers: dict, explicit: str | None) -> str:
    if explicit:
        return explicit
    sender = (headers.get("from") or "").lower()
    configured_source = os.environ.get("FURNITURE_CONVERSATION_SOURCE_ACCOUNT", "craigslist-account@example.invalid").lower()
    if configured_source in sender:
        return "outbound"
    return "inbound"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("message_id", help="Gmail message ID")
    ap.add_argument("--platform", default="craigslist_email", choices=sorted(PLATFORMS))
    ap.add_argument("--source-account", default=os.environ.get("FURNITURE_CONVERSATION_SOURCE_ACCOUNT", "craigslist-account@example.invalid"))
    ap.add_argument("--direction", choices=["inbound", "outbound", "system", "internal_note"])
    ap.add_argument("--account", help="gog OAuth account override")
    ap.add_argument("--print-paths", action="store_true")
    args = ap.parse_args(argv)

    payload = run_gog_get(args.message_id, args.account)
    headers = payload.get("headers") or {}
    message = payload.get("message") or {}
    dt = parse_message_dt(headers)
    yyyy, mm, dd = dt.strftime("%Y"), dt.strftime("%m"), dt.strftime("%d")

    raw_dir = CONV_ROOT / "raw" / args.platform / yyyy / mm / dd
    norm_dir = CONV_ROOT / "normalized" / args.platform / yyyy / mm / dd
    raw_dir.mkdir(parents=True, exist_ok=True)
    norm_dir.mkdir(parents=True, exist_ok=True)

    source_message_id = message.get("id") or args.message_id
    source_thread_id = message.get("threadId") or payload.get("threadId") or source_message_id
    raw_rel = Path("local_data") / "furniture_conversations" / "raw" / args.platform / yyyy / mm / dd / f"gmail-message-{source_message_id}.json"
    norm_rel = Path("local_data") / "furniture_conversations" / "normalized" / args.platform / yyyy / mm / dd / f"gmail-message-{source_message_id}.normalized.json"
    raw_path = WORKSPACE / raw_rel
    norm_path = WORKSPACE / norm_rel

    raw_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")

    body_text = normalize_body(payload.get("body") or "", args.platform)
    normalized = {
        "schema_version": "furniture_conversation_message_v1",
        "platform": args.platform,
        "source_account": args.source_account,
        "source_message_id": source_message_id,
        "source_thread_id": source_thread_id,
        "message_at": dt.isoformat(),
        "direction": infer_direction(headers, args.direction),
        "sender_raw": headers.get("from"),
        "recipient_raw": headers.get("to"),
        "subject": headers.get("subject"),
        "body_text": body_text,
        "body_preview": body_text[:500],
        "listing_urls": craigslist_listing_urls(payload.get("body") or ""),
        "source_urls": source_urls(payload.get("body") or ""),
        "message_url": None,
        "raw_message_path": str(raw_rel),
        "has_attachments": False,
        "attachments_json": [],
    }
    norm_path.write_text(json.dumps(normalized, indent=2, ensure_ascii=False) + "\n")

    if args.print_paths:
        print(str(raw_rel))
        print(str(norm_rel))
    else:
        print(json.dumps({"raw": str(raw_rel), "normalized": str(norm_rel)}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
