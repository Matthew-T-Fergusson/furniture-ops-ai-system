-- AWF-187: message templates and approval-gated template rendering.
--
-- Decisions encoded:
-- - Templates draft/preview only; they do not send external messages.
-- - conversation_messages.template_id records which sent/logged outbound message used a template.
-- - Merge fields use {{field_name}} syntax.
-- - Missing required fields produce a preview_status='needs_fields' row with missing_fields/preview_message.
-- - Base templates are reusable across channels; channel_overrides_json leaves room for special channel instructions.
-- - use_count counts logged/sent outbound usage, not previews.

BEGIN;

CREATE TABLE IF NOT EXISTS public.message_templates (
  template_id bigserial PRIMARY KEY,
  template_key text NOT NULL,
  title text NOT NULL,
  body text NOT NULL,
  merge_fields_json jsonb NOT NULL DEFAULT '{"required": [], "optional": []}'::jsonb,
  category text NOT NULL,
  channels text[] NOT NULL DEFAULT ARRAY['base']::text[],
  channel_overrides_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  active boolean NOT NULL DEFAULT true,
  version_no integer NOT NULL DEFAULT 1,
  supersedes_template_id bigint REFERENCES public.message_templates(template_id),
  use_count bigint NOT NULL DEFAULT 0,
  created_by text NOT NULL DEFAULT current_user,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT message_templates_key_chk CHECK (template_key ~ '^[a-z0-9][a-z0-9_]*$'),
  CONSTRAINT message_templates_version_chk CHECK (version_no > 0),
  CONSTRAINT message_templates_use_count_chk CHECK (use_count >= 0),
  CONSTRAINT message_templates_merge_fields_object_chk CHECK (jsonb_typeof(merge_fields_json) = 'object'),
  CONSTRAINT message_templates_channel_overrides_object_chk CHECK (jsonb_typeof(channel_overrides_json) = 'object'),
  CONSTRAINT message_templates_channels_nonempty_chk CHECK (array_length(channels, 1) IS NOT NULL)
);

COMMENT ON TABLE public.message_templates IS
  'AWF-187: Approval-gated reusable furniture CRM message templates. Templates speed drafting/previews only; external sends still require human approval and send guardrails.';
COMMENT ON COLUMN public.message_templates.template_key IS
  'Stable snake_case key used by agents/workflows, e.g. still_available or pickup_scheduling.';
COMMENT ON COLUMN public.message_templates.body IS
  'Base reusable template body using {{field_name}} merge-field syntax.';
COMMENT ON COLUMN public.message_templates.merge_fields_json IS
  'JSON object with required/optional merge fields and source hints. Required missing fields produce a needs_fields preview rather than a silent draft.';
COMMENT ON COLUMN public.message_templates.channels IS
  'Channels where the base template is valid. Include base for channel-neutral templates; future channels can be added without schema changes.';
COMMENT ON COLUMN public.message_templates.channel_overrides_json IS
  'Optional channel-specific instructions/overrides, keyed by channel, while preserving one base template.';
COMMENT ON COLUMN public.message_templates.use_count IS
  'Operational usage count. Increment only when a template is used in a logged/sent outbound message, not when merely previewed.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_message_templates_key_version
  ON public.message_templates(template_key, version_no);
CREATE UNIQUE INDEX IF NOT EXISTS uq_message_templates_active_key
  ON public.message_templates(template_key)
  WHERE active;
CREATE INDEX IF NOT EXISTS idx_message_templates_category_active
  ON public.message_templates(category, active);
CREATE INDEX IF NOT EXISTS idx_message_templates_channels_gin
  ON public.message_templates USING gin(channels);

ALTER TABLE public.conversation_messages
  ADD COLUMN IF NOT EXISTS template_id bigint REFERENCES public.message_templates(template_id);
COMMENT ON COLUMN public.conversation_messages.template_id IS
  'AWF-187: Optional template used to draft/log this outbound message. Null for inbound/manual/non-template messages.';
CREATE INDEX IF NOT EXISTS idx_conversation_messages_template_id
  ON public.conversation_messages(template_id)
  WHERE template_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.render_message_template(
  p_template_key text,
  p_channel text,
  p_values jsonb DEFAULT '{}'::jsonb
) RETURNS TABLE (
  template_id bigint,
  template_key text,
  title text,
  rendered_body text,
  missing_fields text[],
  preview_status text,
  preview_message text
) LANGUAGE plpgsql STABLE AS $$
DECLARE
  tmpl public.message_templates%ROWTYPE;
  required_fields text[];
  optional_fields text[];
  all_fields text[];
  missing text[];
  field_name text;
  candidate_body text;
  channel_allowed boolean;
  suffix text;
BEGIN
  SELECT * INTO tmpl
  FROM public.message_templates mt
  WHERE mt.template_key = p_template_key
    AND mt.active
  ORDER BY mt.version_no DESC, mt.template_id DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT
      NULL::bigint,
      p_template_key,
      NULL::text,
      NULL::text,
      ARRAY[p_template_key]::text[],
      'blocked'::text,
      ('Template not found: ' || coalesce(p_template_key, '<null>'))::text;
    RETURN;
  END IF;

  required_fields := ARRAY(
    SELECT jsonb_array_elements_text(coalesce(tmpl.merge_fields_json->'required', '[]'::jsonb))
  );
  optional_fields := ARRAY(
    SELECT jsonb_array_elements_text(coalesce(tmpl.merge_fields_json->'optional', '[]'::jsonb))
  );
  all_fields := ARRAY(
    SELECT DISTINCT f
    FROM unnest(coalesce(required_fields, ARRAY[]::text[]) || coalesce(optional_fields, ARRAY[]::text[])) AS f
  );
  missing := ARRAY(
    SELECT f
    FROM unnest(coalesce(required_fields, ARRAY[]::text[])) AS f
    WHERE nullif(btrim(coalesce(p_values->>f, '')), '') IS NULL
    ORDER BY f
  );

  channel_allowed := 'base' = ANY(tmpl.channels) OR p_channel = ANY(tmpl.channels);
  candidate_body := tmpl.body;

  FOREACH field_name IN ARRAY coalesce(all_fields, ARRAY[]::text[]) LOOP
    IF p_values ? field_name THEN
      candidate_body := replace(candidate_body, '{{' || field_name || '}}', coalesce(p_values->>field_name, ''));
    ELSIF NOT (field_name = ANY(coalesce(required_fields, ARRAY[]::text[]))) THEN
      candidate_body := replace(candidate_body, '{{' || field_name || '}}', '');
    END IF;
  END LOOP;

  suffix := tmpl.channel_overrides_json #>> ARRAY[p_channel, 'body_suffix'];
  IF nullif(btrim(coalesce(suffix, '')), '') IS NOT NULL THEN
    candidate_body := candidate_body || E'\n\n' || suffix;
  END IF;

  RETURN QUERY SELECT
    tmpl.template_id,
    tmpl.template_key,
    tmpl.title,
    candidate_body,
    coalesce(missing, ARRAY[]::text[]),
    CASE
      WHEN NOT channel_allowed THEN 'blocked'
      WHEN array_length(missing, 1) IS NOT NULL THEN 'needs_fields'
      ELSE 'ready'
    END::text,
    CASE
      WHEN NOT channel_allowed THEN 'Template is not approved for channel ' || coalesce(p_channel, '<null>') || '; use a base/channel-approved template or manually override after review.'
      WHEN array_length(missing, 1) IS NOT NULL THEN 'Missing required merge fields: ' || array_to_string(missing, ', ') || '. Fill them in or edit the message before preview/send approval.'
      ELSE 'Preview ready. Human approval and send guardrails are still required before any external send.'
    END::text;
END;
$$;

COMMENT ON FUNCTION public.render_message_template(text, text, jsonb) IS
  'AWF-187: Render an active template preview and report missing required merge fields. Preview-only helper; does not send messages or increment use_count.';

INSERT INTO public.message_templates (
  template_key,
  title,
  body,
  merge_fields_json,
  category,
  channels,
  channel_overrides_json,
  created_by
)
SELECT *
FROM (
  VALUES
  (
    'still_available',
    'Still available reply',
    'Hi — yes, the {{listing_title}} is still available. If you would like it, pickup is in {{pickup_area}}. {{availability_window}}',
    '{"required": ["listing_title", "pickup_area"], "optional": ["availability_window"], "sources": {"listing_title": ["listings.title", "inventory.item_title"], "pickup_area": ["pickups_deliveries", "manual"], "availability_window": ["pickups_deliveries", "manual"]}}'::jsonb,
    'availability',
    ARRAY['base','craigslist_email','craigslist_chat','facebook_marketplace','manual','other']::text[],
    '{"craigslist_email": {"instruction": "Keep relay-safe and do not include direct contact info unless approved."}, "facebook_marketplace": {"instruction": "Keep concise; buyer sees listing context."}}'::jsonb,
    'AWF-187 synthetic seed'
  ),
  (
    'pickup_scheduling',
    'Pickup scheduling reply',
    'That can work. The item is located around {{pickup_area}}. The best pickup window is {{pickup_window}}. If that works, I can mark it pending once we confirm timing.',
    '{"required": ["pickup_area", "pickup_window"], "optional": ["listing_title"], "sources": {"pickup_area": ["pickups_deliveries", "manual"], "pickup_window": ["pickups_deliveries", "manual"], "listing_title": ["listings.title", "inventory.item_title"]}}'::jsonb,
    'scheduling',
    ARRAY['base','craigslist_email','craigslist_chat','facebook_marketplace','manual','other']::text[],
    '{}'::jsonb,
    'AWF-187 synthetic seed'
  ),
  (
    'dimensions_reply',
    'Dimensions reply',
    'The {{listing_title}} measures approximately {{dimensions}}. {{condition_note}}',
    '{"required": ["listing_title", "dimensions"], "optional": ["condition_note"], "sources": {"listing_title": ["listings.title", "inventory.item_title"], "dimensions": ["inventory", "manual"], "condition_note": ["inventory.note", "manual"]}}'::jsonb,
    'details',
    ARRAY['base','craigslist_email','craigslist_chat','facebook_marketplace','manual','other']::text[],
    '{}'::jsonb,
    'AWF-187 synthetic seed'
  ),
  (
    'delivery_terms',
    'Delivery terms reply',
    'Pickup is preferred for {{listing_title}}. Delivery may be possible depending on distance and schedule; if you send your general area, we can confirm whether delivery is practical and whether there would be a delivery fee.',
    '{"required": ["listing_title"], "optional": ["buyer_area"], "sources": {"listing_title": ["listings.title", "inventory.item_title"], "buyer_area": ["contacts", "conversation_threads", "manual"]}}'::jsonb,
    'delivery',
    ARRAY['base','craigslist_email','craigslist_chat','facebook_marketplace','manual','other']::text[],
    '{}'::jsonb,
    'AWF-187 synthetic seed'
  ),
  (
    'counteroffer_hold_price',
    'Counteroffer / hold price reply',
    'Thanks for the offer. We are holding at {{asking_price}} for now on the {{listing_title}}, but I can let you know if that changes.',
    '{"required": ["listing_title", "asking_price"], "optional": [], "sources": {"listing_title": ["listings.title", "inventory.item_title"], "asking_price": ["listings.current_asking_price", "inventory.list_price_target", "manual"]}, "policy": "Do not invite negotiation by default; holding price is the current business model."}'::jsonb,
    'pricing',
    ARRAY['base','craigslist_email','craigslist_chat','facebook_marketplace','manual','other']::text[],
    '{}'::jsonb,
    'AWF-187 synthetic seed'
  )
) AS seed(template_key, title, body, merge_fields_json, category, channels, channel_overrides_json, created_by)
WHERE NOT EXISTS (
  SELECT 1 FROM public.message_templates mt
  WHERE mt.template_key = seed.template_key
    AND mt.active
);

COMMIT;
