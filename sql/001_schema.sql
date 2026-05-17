-- Furniture Ops AI POC schema

CREATE TABLE IF NOT EXISTS inventory_groups (
  inventory_group_id text PRIMARY KEY,
  group_type text NOT NULL DEFAULT 'standalone',
  acquisition_date date,
  acquisition_source text,
  total_acquisition_cost numeric(12,2),
  cost_allocation_method text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT inventory_groups_group_type_chk CHECK (group_type IN ('standalone','bundle','split_listing','set','lot','unknown')),
  CONSTRAINT inventory_groups_cost_alloc_chk CHECK (cost_allocation_method IS NULL OR cost_allocation_method IN ('manual','equal','by_estimated_value','zero_child','parent_absorbed','split_child_zero_cogs','bundle_child_zero_cogs','not_allocated','unknown_needs_review'))
);

CREATE TABLE IF NOT EXISTS inventory (
  inventory_pk bigserial PRIMARY KEY,
  inventory_uid text NOT NULL UNIQUE,
  inventory_id text,
  inventory_group_id text REFERENCES inventory_groups(inventory_group_id),
  parent_inventory_uid text REFERENCES inventory(inventory_uid),
  item_id text,
  item_title text,
  category text,
  furniture_type text,
  furniture_subtype text,
  brand text,
  date_acquired date,
  list_price_target numeric(12,2),
  storage_location text,
  cl_url text,
  cost numeric(12,2),
  labor numeric(12,2),
  acquisition_cost numeric(12,2),
  sold boolean NOT NULL DEFAULT false,
  status text,
  status_updated_at timestamptz,
  cost_basis_source text,
  cost_allocation_method text,
  allocated_cost numeric(12,2),
  expected_sale_price numeric(12,2),
  listed_at timestamptz,
  pending_at timestamptz,
  reserved_until timestamptz,
  sold_at timestamptz,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT inventory_status_chk CHECK (status IS NULL OR status IN ('sourced','acquired_unlisted','refurb_needed','ready_to_list','listed_active','pending_sale','sold_delivered','disposed','hold'))
);

COMMENT ON COLUMN inventory.sold IS 'Y/N boolean supplement to inventory.status. True only when status=sold_delivered; false for all other statuses.';
COMMENT ON COLUMN inventory.furniture_type IS 'Strict high-level furniture type for analytics. Taxonomy should be controlled by the application/guardrail layer.';
COMMENT ON COLUMN inventory.furniture_subtype IS 'Flexible secondary subtype for merchandising/search nuance.';

CREATE TABLE IF NOT EXISTS inventory_status_history (
  status_history_id bigserial PRIMARY KEY,
  inventory_uid text NOT NULL REFERENCES inventory(inventory_uid),
  inventory_group_id text REFERENCES inventory_groups(inventory_group_id),
  from_status text,
  to_status text NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by text NOT NULL DEFAULT 'agent',
  reason text,
  notes text,
  source_system text NOT NULL DEFAULT 'manual',
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT inventory_status_history_chk CHECK (
    (from_status IS NULL OR from_status IN ('sourced','acquired_unlisted','refurb_needed','ready_to_list','listed_active','pending_sale','sold_delivered','disposed','hold'))
    AND to_status IN ('sourced','acquired_unlisted','refurb_needed','ready_to_list','listed_active','pending_sale','sold_delivered','disposed','hold')
  )
);

CREATE TABLE IF NOT EXISTS contacts (
  contact_id bigserial PRIMARY KEY,
  display_name text NOT NULL,
  contact_type text,
  phone text,
  email text,
  marketplace_handle text,
  default_payment_method text,
  notes text,
  source_system text NOT NULL DEFAULT 'manual',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT contacts_type_chk CHECK (contact_type IS NULL OR contact_type IN ('buyer','seller','contractor','partner','vendor','lead','other'))
);

CREATE TABLE IF NOT EXISTS contact_roles (
  contact_role_id bigserial PRIMARY KEY,
  contact_id bigint NOT NULL REFERENCES contacts(contact_id),
  role text NOT NULL,
  inventory_uid text REFERENCES inventory(inventory_uid),
  inventory_group_id text REFERENCES inventory_groups(inventory_group_id),
  starts_at timestamptz,
  ends_at timestamptz,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT contact_roles_role_chk CHECK (role IN ('buyer','seller','source','contractor','delivery_helper','partner','payer','payee','marketplace_lead','vendor','other'))
);

CREATE TABLE IF NOT EXISTS cash_flows (
  cf_record_id text PRIMARY KEY,
  inventory_uid text REFERENCES inventory(inventory_uid),
  inventory_group_id text REFERENCES inventory_groups(inventory_group_id),
  contact_id bigint REFERENCES contacts(contact_id),
  storage_unit_id text,
  txn_type text NOT NULL DEFAULT 'Expense',
  txn_date date,
  txn_date_raw text,
  vendor_or_description text,
  amount numeric(12,2),
  amount_raw text,
  currency text DEFAULT 'USD',
  category text,
  purpose text,
  file_path text,
  file_link text,
  notes text,
  paid_by text,
  paid_to text,
  cash_paid_by text,
  cash_paid_to text,
  payment_method text,
  payment_stage text,
  partner_balance_effect text,
  source_system text NOT NULL DEFAULT 'manual',
  imported_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cash_flows_payment_stage_chk CHECK (payment_stage IS NULL OR payment_stage IN ('deposit','partial_payment','final_payment','final_or_full_payment','refund','reimbursement','inventory_purchase','labor','storage','other'))
);

COMMENT ON COLUMN cash_flows.file_path IS 'Saved source receipt/image/document path for audit trail.';
COMMENT ON COLUMN cash_flows.file_link IS 'Link/reference to saved source receipt/image/document.';
COMMENT ON COLUMN cash_flows.notes IS 'OCR/extracted receipt or transaction details when available.';
COMMENT ON COLUMN cash_flows.partner_balance_effect IS 'Partner accounting effect classification, e.g. expense_paid, sale_proceeds_credit, labor_payment, no_cash_movement, zero_sale_or_disposition, other.';

CREATE TABLE IF NOT EXISTS listings (
  listing_id bigserial PRIMARY KEY,
  inventory_uid text NOT NULL REFERENCES inventory(inventory_uid),
  inventory_group_id text REFERENCES inventory_groups(inventory_group_id),
  platform text NOT NULL DEFAULT 'marketplace',
  external_listing_id text,
  listing_url text,
  title text,
  status text NOT NULL DEFAULT 'active',
  listed_at timestamptz,
  delisted_at timestamptz,
  current_asking_price numeric(12,2),
  notes text,
  source_system text NOT NULL DEFAULT 'manual',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT listings_status_chk CHECK (status IN ('draft','active','paused','pending','sold','delisted','cancelled','expired','relist_needed'))
);

CREATE TABLE IF NOT EXISTS listing_price_history (
  price_history_id bigserial PRIMARY KEY,
  listing_id bigint NOT NULL REFERENCES listings(listing_id),
  price numeric(12,2) NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT now(),
  changed_by text NOT NULL DEFAULT 'agent',
  reason text,
  source_system text NOT NULL DEFAULT 'manual',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS pickups_deliveries (
  movement_id bigserial PRIMARY KEY,
  movement_type text NOT NULL,
  inventory_uid text REFERENCES inventory(inventory_uid),
  inventory_group_id text REFERENCES inventory_groups(inventory_group_id),
  contact_id bigint REFERENCES contacts(contact_id),
  counterparty_name text,
  counterparty_contact text,
  location_address text,
  scheduled_start timestamptz,
  scheduled_end timestamptz,
  movement_status text NOT NULL DEFAULT 'planned',
  calendar_event_id text,
  assigned_to text,
  deposit_required numeric(12,2),
  deposit_received numeric(12,2),
  item_price numeric(12,2),
  delivery_fee numeric(12,2),
  balance_owed numeric(12,2),
  notes text,
  source_system text NOT NULL DEFAULT 'manual',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pickups_deliveries_type_chk CHECK (movement_type IN ('acquisition_pickup','buyer_pickup','seller_delivery','storage_transfer','contractor_delivery','return_pickup','other')),
  CONSTRAINT pickups_deliveries_status_chk CHECK (movement_status IN ('planned','confirmed','completed','cancelled','rescheduled'))
);

CREATE TABLE IF NOT EXISTS contractor_ratings (
  contractor_rating_id bigserial PRIMARY KEY,
  contact_id bigint NOT NULL REFERENCES contacts(contact_id),
  movement_id bigint REFERENCES pickups_deliveries(movement_id),
  rating_overall integer CHECK (rating_overall BETWEEN 1 AND 5),
  punctuality_rating integer CHECK (punctuality_rating BETWEEN 1 AND 5),
  care_quality_rating integer CHECK (care_quality_rating BETWEEN 1 AND 5),
  value_rating integer CHECK (value_rating BETWEEN 1 AND 5),
  would_use_again boolean,
  interaction_at timestamptz NOT NULL DEFAULT now(),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_inventory_status ON inventory(status);
CREATE INDEX IF NOT EXISTS idx_inventory_sold ON inventory(sold);
CREATE INDEX IF NOT EXISTS idx_inventory_group_id ON inventory(inventory_group_id);
CREATE INDEX IF NOT EXISTS idx_inventory_furniture_type ON inventory(furniture_type);
CREATE INDEX IF NOT EXISTS idx_cash_flows_inventory_uid ON cash_flows(inventory_uid);
CREATE INDEX IF NOT EXISTS idx_cash_flows_txn_date ON cash_flows(txn_date);
CREATE INDEX IF NOT EXISTS idx_cash_flows_paid_by ON cash_flows(paid_by);
CREATE INDEX IF NOT EXISTS idx_cash_flows_payment_method ON cash_flows(payment_method);
CREATE INDEX IF NOT EXISTS idx_cash_flows_payment_stage ON cash_flows(payment_stage);
CREATE INDEX IF NOT EXISTS idx_listings_inventory_uid ON listings(inventory_uid);
CREATE INDEX IF NOT EXISTS idx_pickups_deliveries_schedule ON pickups_deliveries(scheduled_start, scheduled_end);
