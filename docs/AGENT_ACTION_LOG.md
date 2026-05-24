# Agent Action Log

`agent_action_log` is the public-safe audit pattern for AI-assisted operations.

## Why it exists

The system is not just a database. It is designed for an AI agent to help turn messy business inputs into structured operational records. That creates a governance requirement: a reviewer should be able to answer what the agent did, why it did it, which workflow produced it, what guardrails saw before/after, and whether a human corrected the behavior later.

The table is intentionally lightweight but structured enough to replicate or review an action.

## What gets recorded

Core fields:

- `skill_name` — workflow/skill responsible for the action
- `agent_identifier` — agent/session label, sanitized for the public repo
- `prompt_version` — workflow or prompt version when known
- `chat_input_excerpt` — capped sanitized input excerpt, max 500 chars
- `operation_summary` — human-readable action summary
- `sql_emitted` — optional sanitized SQL or operation sketch
- `guardrails_before` / `guardrails_after` — summarized guardrail state as JSON
- `entity_type` / `entity_id` — record or business object affected
- `status` — `preview_only`, `success`, `failed`, `blocked_by_guardrail`, or `needs_human_review`
- `error_message` — failure detail when appropriate
- `human_feedback` — reviewer/user feedback or correction guidance
- `correction_action_id` — optional link to the action being corrected or superseded

## Privacy boundary

The public repository must never contain:

- real private chat text
- customer names, phone numbers, addresses, or marketplace threads
- real receipt images or OCR text
- credentials, tokens, Drive IDs, or private file paths
- raw production SQL payloads with private values
- private financial details

Use synthetic excerpts, summaries, and placeholders. The goal is to show the governance pattern, not expose operational records.

## Guardrail snapshots

Guardrail fields should be summarized JSON, not unbounded dumps. A good public-safe shape is:

```json
{
  "error": 0,
  "warning": 1,
  "anomalies": ["pending_sale_missing_reserved_until"]
}
```

## Feedback and corrections

When Matt, a reviewer, or a collaborator corrects an agent action, capture that feedback in `human_feedback` and, where useful, add a new action row linked through `correction_action_id`. Future agents should treat that feedback as durable operating guidance instead of relying on memory.

Examples:

- “Do not infer completed sale from ambiguous notes; require payment/date evidence.”
- “Preview external listing changes before writing or publishing.”
- “Keep public repo examples synthetic; do not include real chat text.”

## Reference workflows

The first public seed rows demonstrate:

1. successful synthetic receipt/cash-flow capture
2. preview-only listing price sync
3. blocked sale/status update due to guardrail failures

This gives reviewers evidence that AI-assisted operations are designed to be auditable, reviewable, and bounded by process controls.
