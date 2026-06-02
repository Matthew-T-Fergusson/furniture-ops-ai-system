# Craigslist Email Reply Reference

## Related Jira

- internal-tracker: raw/normalized transcript storage.
- internal-tracker: Gmail/Craigslist backfill.
- internal-tracker: furniture conversation monitor triage.
- internal-tracker: this Craigslist email reply skill.
- internal-tracker: Craigslist on-site chat capture skill.
- internal-tracker: future policy for Lex-approved routine marketplace replies.

## Platform distinction

- `craigslist_email`: Craigslist email relay messages handled through Gmail.
- `craigslist_chat`: Craigslist on-site chat handled through managed browser.

Do not mix the reply mechanisms.

## Current Gmail CLI

Available send command:

```bash
gog gmail send --help
```

Important flags observed:

- `--account`
- `--to`
- `--cc`
- `--bcc`
- `--subject`
- `--body`
- `--body-file`
- `--reply-to-message-id`
- `--thread-id`
- `--reply-all`
- `--reply-to`
- `--attach`
- `--from`
- `--quote`
- `--dry-run`

Search command:

```bash
gog gmail messages search '<gmail query>' --account craigslist-account@example.invalid --max 10 --json --include-body
```

## Storage convention

Raw outbound send record:

```text
local_data/furniture_conversations/raw/craigslist_email/YYYY/MM/DD/
```

Normalized outbound message:

```text
local_data/furniture_conversations/normalized/craigslist_email/YYYY/MM/DD/
```

Never store credentials, OAuth tokens, session cookies, or one-time login links.

## DB write expectations after approved send

Insert/upsert `conversation_messages`:

- `platform='craigslist_email'`
- `direction='outbound'`
- `source_account='craigslist-account@example.invalid'` unless another account owns the thread
- `source_message_id`: Gmail sent message ID if available; otherwise deterministic provisional ID with later reconciliation
- `source_thread_id`: Gmail thread ID / source thread ID
- `message_at`: send timestamp
- `sender_raw`: Lex Gmail/sender alias
- `recipient_raw`: Craigslist relay recipient(s)
- `subject`, `body_text`, `body_preview`
- `message_url` if Gmail URL available
- `raw_message_path`
- `source_system='gog_gmail_send'`

Update `conversation_threads`:

- `last_outbound_at=send timestamp`
- `last_message_at=send timestamp`
- `needs_reply=false`
- usually `stage='waiting_on_other_party'`
- `next_action_note` set to follow-up note only if appropriate

Then run:

```bash
python3 scripts/link_conversation_records.py --apply --readback
python3 scripts/apply_conversation_workflow_rules.py --apply --readback
```

## Draft style

Good default for buyer inquiry:

```text
Hi — yes, it’s still available. Pickup is in <location/area>. I can confirm dimensions or coordinate a time if you’d like to come see it.
```

Good default for scheduling:

```text
Hi — that works. Can you confirm your target pickup time and whether you’ll have help/loading space? Once confirmed, I’ll hold it for that window.
```

Good default when details are unknown:

```text
Hi — thanks for reaching out. I’m checking that detail now and will follow up shortly.
```

Do not invent:

- exact location/address
- dimensions
- condition details
- delivery terms
- discount authority
- item availability if not known

## Approval gate

Always show preview first. a human operator must approve before send until internal-tracker changes policy.
