# Platform Message Capture Policy

AWF-177 — Platform-specific privacy and capture policies for furniture-business marketplace messages.

This policy defines what Lex may capture, normalize, store, and surface from marketplace/customer conversations. It exists so new sources such as eBay can plug into the CRM without over-capturing private data or polluting analytics.

## Global rules

1. **Business-purpose only.** Capture message data only when it relates to furniture sourcing, listings, sale inquiries, pickup/delivery coordination, vendor/contractor coordination, partner operations, or support/admin workflow.
2. **Preserve provenance.** Every captured message should retain platform, source account, source message/thread id when available, timestamp, direction, raw sender/recipient text, and raw payload path when saved.
3. **Normalize minimally.** Store normalized thread/message fields needed for operations, analytics, matching, and reply drafting. Keep raw payloads for audit/debug only where allowed by the platform-specific policy.
4. **No blind identity merge.** Exact phone, email, or platform-id matches can support proposed contact matching. Name-only or fuzzy matches require manual review.
5. **Approval before external send.** Capturing, drafting, and previewing are allowed; external replies remain approval-gated. DNC/send guardrails must run before non-dry-run sends/logged outbound messages.
6. **Test/self traffic must be labeled.** Matt/Lex/Stephen test traffic should be marked `archived_test` / `not_a_lead` and excluded from active queue and lead analytics.
7. **Sensitive personal content is not a CRM asset.** Do not intentionally capture or surface unrelated health, financial, family, credential, or private-life content. If present incidentally inside a business thread, summarize only the business-relevant parts and avoid copying sensitive content into normalized fields.
8. **Deletion/minimization is allowed.** If a contact/thread is confirmed as test, duplicate, spam, hostile noise, or irrelevant, it may be archived, marked not-a-lead, and/or cleaned from contact tables with audit logging.

## Data placement

- `conversation_threads`: one row per platform thread/conversation, with purpose, stage, lead quality, disposition, contact/listing/inventory linkage, queue fields, and summary.
- `conversation_messages`: immutable-ish source messages and logged outbound messages, including source ids, sender/recipient raw text, body, preview, raw payload path, and attachments metadata.
- `contacts`: durable person/org identity and reachability: name, phone, email, marketplace handle, platform contact id, DNC fields.
- `contact_roles`: relationship between a contact and the business/item/workflow: buyer, seller, source, partner, vendor, marketplace_lead, etc.
- `pickups_deliveries`: movement-specific address, schedule, logistics, and contact references. Delivery/pickup addresses should land here when tied to a movement, not only in `contacts.notes`.
- `agent_action_log`: every non-trivial mutation from ingestion, enrichment, matching, cleanup, or send/log workflows should include before/after summaries and source references.

## Platform policies

### Craigslist email relay

- **Capture:** relay sender token/hash, subject, body, message timestamp, message URL/thread hints, listing URL/id when present, direction, attachments metadata if present.
- **Raw storage:** allowed for the business email payload because Gmail is the capture source; store raw path or Gmail ids when useful for audit/debug.
- **Normalize:** extract listing id/URL, buyer/seller intent, explicit contact info, pickup/delivery details, and reply-needed state.
- **Privacy notes:** relay addresses are not durable customer emails. Do not treat Craigslist relay addresses as real email identities unless an actual email is explicitly provided in message body/signature.
- **Matching:** exact listing URL/id can link listing/inventory. Contact matching should prefer explicit phone/email/platform identifiers; repeated relay hashes can link to the same provisional Craigslist contact.

### Craigslist on-site chat

- **Capture:** handle/display name, visible chat messages, message timestamps when available, related listing id/URL when available, direction, source account, and browser-capture metadata.
- **Raw storage:** save only the relevant captured chat payload/screenshot-derived text needed for business audit. Avoid storing unrelated page/session/private account content.
- **Normalize:** handle-only users become provisional marketplace contacts until enriched. Listing-specific chats can link to listing/inventory when strong evidence exists.
- **Privacy notes:** generic robot notification emails are not the actual buyer message and must remain capture-needed/review-only until browser chat capture provides content. Do not infer listing/contact from generic notification alone.
- **Test handling:** Matt/Lex test chats must be archived as test/not-a-lead and linked to canonical Matt contact or cleaned as directed.

### Facebook Marketplace / Messenger

- **Capture:** marketplace thread id, visible participant name/profile handle/id where available, item/listing reference, message text, timestamps, direction, attachments metadata relevant to the item.
- **Raw storage:** minimize. Store CRM-relevant message payloads and source ids; avoid broad profile scraping or unrelated Messenger history.
- **Normalize:** create provisional contact from Facebook profile/id/handle. Extract phone/email/address only when explicitly offered in the business conversation.
- **Privacy notes:** do not capture unrelated social profile data, friends, posts, personal photos, or off-topic Messenger content. Treat profile URLs/ids as platform identifiers, not general-purpose identity proof.
- **Matching:** exact Facebook profile/id or phone/email can match contacts. Name-only Facebook matches require review.

### eBay messages

- **Capture:** eBay member/user id or masked handle, item id/listing id, order id if applicable, message id/thread id, subject/body, timestamp, direction, attachments metadata, and eBay case/offer context when relevant.
- **Raw storage:** allowed for eBay API/message payloads needed for audit, dispute, shipping, and customer-service context. Store only business-message payloads, not broader account data.
- **Normalize:** link by eBay item/listing/order ids first. Create or match contacts by eBay user id/handle; enrich with real name/address only when provided through transaction/order context or explicit message content.
- **Privacy notes:** buyer shipping addresses from orders should be treated as logistics/order data; do not use them for marketing or unrelated outreach. Respect eBay messaging and off-platform-contact rules.
- **Matching:** item/order ids are strong linkage; user id/handle is platform-scoped identity; real name/address should not trigger cross-platform merge without phone/email or manual review.

### SMS / direct phone messages

- **Capture:** phone number, message text, timestamps, direction, source account/device, attachments metadata when business-relevant.
- **Raw storage:** allowed for business SMS threads with provenance. Avoid importing unrelated personal SMS conversations.
- **Normalize:** phone number is a strong contact identifier. Extract pickup/delivery logistics and attach to movement records where applicable.
- **Privacy notes:** SMS is higher-sensitivity because it may mix personal and business content. Capture only furniture-business threads or messages explicitly routed into the furniture workflow.
- **DNC:** phone/SMS DNC must block automated/non-approved external sending on that channel.

### Gmail / general email

- **Capture:** only labels/accounts/folders configured for furniture-business ingestion or messages explicitly selected for furniture work.
- **Raw storage:** store Gmail ids/raw paths for audit when useful.
- **Normalize:** extract sender/recipient, subject/body, thread id, message id, attachments metadata, and business-relevant contact facts.
- **Privacy notes:** do not sweep personal inbox content broadly. Label-driven ingestion is preferred.

## Contact enrichment policy

When a message contains new contact facts:

1. Create an enrichment proposal, not an automatic overwrite.
2. Include source: `conversation_thread_id`, `conversation_message_id`, platform, source ids, timestamp, and text excerpt.
3. Classify field and confidence:
   - High: explicit statement such as "My number is...", "My address is...", signature block.
   - Medium: repeated contextual mention or profile/order metadata.
   - Low: inferred/fuzzy/name-only.
4. Apply only after approval or deterministic high-confidence workflow rules.
5. Never overwrite existing phone/email/address/contact preference without review unless the existing value is blank and the new value is high confidence.
6. For pickup/delivery address or schedule, update/propose `pickups_deliveries` rather than treating the address as a durable contact address by default.
7. Write `agent_action_log` for applied changes.

## Lead quality and disposition defaults

- `actionable`: real buyer/seller/source conversation with clear business relevance.
- `needs_human_review`: ambiguous identity, fuzzy match, potential duplicate, sensitive content, or unclear intent.
- `not_a_lead`: test/self traffic, spam, hostile noise, generic notifications, or support/admin messages.
- `archived_test`: confirmed test/self workflow traffic.
- `hostile_noise`: abusive/non-actionable inquiry. Preserve only enough context for audit/analytics; do not create useful buyer pipeline value.

## Pre-source checklist for adding a new marketplace

Before adding a source such as eBay:

- Document the platform identifiers available for thread, message, user/contact, listing/item, order/transaction, and attachments.
- Decide raw payload retention path and minimization limits.
- Define contact matching keys and fields that require manual review.
- Define which message types enter active queue vs archive/review-only.
- Verify DNC/send guardrails understand the platform channel value.
- Add regression/smoke coverage for at least one actionable lead, one ambiguous/review-only message, and one test/not-a-lead message.
