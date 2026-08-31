-- FAWUsed.ru MVP database schema
-- PostgreSQL 16+ / PostGIS
-- Version 1.0

BEGIN;

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- ===== ENUMS =====

CREATE TYPE user_status AS ENUM ('active','suspended','blocked','deleted_soft');
CREATE TYPE organization_status AS ENUM ('active','suspended','blocked','deleted_soft');
CREATE TYPE organization_role AS ENUM ('owner','manager');
CREATE TYPE vehicle_type AS ENUM ('tractor','dump_truck','chassis','flatbed','van','refrigerated','special','other');
CREATE TYPE gearbox_type AS ENUM ('manual','robotized','automatic');
CREATE TYPE vat_status AS ENUM ('with_vat','without_vat');
CREATE TYPE listing_lifecycle_status AS ENUM ('draft','published','archived','sold','blocked','deleted_soft');
CREATE TYPE trust_type AS ENUM ('select','approved');
CREATE TYPE trust_record_status AS ENUM ('active','expired','revoked','pending');
CREATE TYPE photo_status AS ENUM ('uploaded','validated','processing','ready','failed');
CREATE TYPE complaint_status AS ENUM ('new','in_review','resolved','rejected');
CREATE TYPE complaint_reason AS ENUM ('duplicate','sold','wrong_data','fraud','stolen_content','prohibited','other');
CREATE TYPE api_credential_status AS ENUM ('active','grace','revoked');
CREATE TYPE webhook_status AS ENUM ('active','degraded','disabled');
CREATE TYPE webhook_delivery_status AS ENUM ('pending','delivered','failed','dead');
CREATE TYPE seller_kind AS ENUM ('private','organization');

-- ===== USERS / ORGANIZATIONS =====

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_e164 varchar(20) NOT NULL UNIQUE,
  name varchar(120),
  telegram varchar(120),
  status user_status NOT NULL DEFAULT 'active',
  last_login_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz
);

CREATE TABLE organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  legal_name varchar(255) NOT NULL,
  public_name varchar(255),
  inn varchar(12) NOT NULL UNIQUE,
  status organization_status NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  CONSTRAINT organizations_inn_chk CHECK (inn ~ '^[0-9]{10}([0-9]{2})?$')
);

CREATE TABLE organization_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  role organization_role NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id),
  UNIQUE (organization_id, user_id)
);

CREATE INDEX organization_members_org_idx ON organization_members(organization_id);

-- ===== REFERENCE DATA =====

CREATE TABLE manufacturers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name varchar(120) NOT NULL UNIQUE,
  slug varchar(120) NOT NULL UNIQUE,
  is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE models (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  manufacturer_id uuid NOT NULL REFERENCES manufacturers(id) ON DELETE RESTRICT,
  name varchar(120) NOT NULL,
  slug varchar(120) NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  UNIQUE (manufacturer_id, name),
  UNIQUE (manufacturer_id, slug)
);

CREATE INDEX models_manufacturer_idx ON models(manufacturer_id);

CREATE TABLE modifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id uuid NOT NULL REFERENCES models(id) ON DELETE RESTRICT,
  name varchar(160) NOT NULL,
  canonical_specs jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  UNIQUE (model_id, name)
);

CREATE TABLE cities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name varchar(160) NOT NULL,
  region_name varchar(160) NOT NULL,
  federal_subject varchar(160),
  center geography(Point,4326) NOT NULL,
  slug varchar(180) NOT NULL UNIQUE,
  is_active boolean NOT NULL DEFAULT true
);

CREATE INDEX cities_center_gist ON cities USING gist(center);
CREATE INDEX cities_name_idx ON cities(name);

-- ===== VEHICLE =====

CREATE TABLE vehicles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vin_normalized varchar(32) NOT NULL UNIQUE,
  manufacturer_id uuid NOT NULL REFERENCES manufacturers(id) ON DELETE RESTRICT,
  model_id uuid NOT NULL REFERENCES models(id) ON DELETE RESTRICT,
  modification_id uuid REFERENCES modifications(id) ON DELETE SET NULL,
  production_year integer NOT NULL,
  vehicle_type vehicle_type NOT NULL,
  power_hp integer NOT NULL,
  engine_volume_cc integer,
  fuel_type varchar(32) NOT NULL DEFAULT 'diesel',
  wheel_formula varchar(16) NOT NULL,
  gearbox gearbox_type NOT NULL,
  ecological_class varchar(32),
  gross_weight_kg integer,
  curb_weight_kg integer,
  payload_kg integer,
  wheelbase_mm integer,
  fuel_tank_l integer,
  body_type varchar(160),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT vehicles_year_chk CHECK (production_year BETWEEN 1980 AND 2100),
  CONSTRAINT vehicles_power_chk CHECK (power_hp > 0),
  CONSTRAINT vehicles_vin_chk CHECK (char_length(vin_normalized) BETWEEN 11 AND 32)
);

CREATE INDEX vehicles_model_year_idx ON vehicles(model_id, production_year);
CREATE INDEX vehicles_type_idx ON vehicles(vehicle_type);

-- ===== LISTINGS =====

CREATE TABLE listings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL REFERENCES vehicles(id) ON DELETE RESTRICT,

  seller_kind seller_kind NOT NULL,
  seller_user_id uuid REFERENCES users(id) ON DELETE RESTRICT,
  seller_organization_id uuid REFERENCES organizations(id) ON DELETE RESTRICT,
  seller_listing_id varchar(128),

  lifecycle_status listing_lifecycle_status NOT NULL DEFAULT 'draft',

  mileage_km integer NOT NULL,
  price_rub bigint NOT NULL,
  vat_status vat_status NOT NULL,
  leasing_available boolean NOT NULL,

  city_id uuid NOT NULL REFERENCES cities(id) ON DELETE RESTRICT,
  location_exact geography(Point,4326) NOT NULL,
  public_location geography(Point,4326),

  contact_phone_e164 varchar(20) NOT NULL,
  telegram varchar(120),
  description text,
  video_url text,

  published_at timestamptz,
  sold_at timestamptz,
  archived_at timestamptz,
  blocked_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,

  CONSTRAINT listings_mileage_chk CHECK (mileage_km >= 0),
  CONSTRAINT listings_price_chk CHECK (price_rub > 0),
  CONSTRAINT listings_seller_chk CHECK (
    (seller_kind = 'private' AND seller_user_id IS NOT NULL AND seller_organization_id IS NULL)
    OR
    (seller_kind = 'organization' AND seller_organization_id IS NOT NULL)
  )
);

-- One external seller listing id per organization
CREATE UNIQUE INDEX listings_org_external_id_uq
  ON listings(seller_organization_id, seller_listing_id)
  WHERE seller_organization_id IS NOT NULL AND seller_listing_id IS NOT NULL;

-- Critical rule: only one published listing per vehicle at a time
CREATE UNIQUE INDEX listings_one_active_vehicle_uq
  ON listings(vehicle_id)
  WHERE lifecycle_status = 'published';

CREATE INDEX listings_catalog_core_idx
  ON listings(lifecycle_status, city_id, price_rub, mileage_km, created_at DESC);

CREATE INDEX listings_vehicle_idx ON listings(vehicle_id);
CREATE INDEX listings_org_status_idx ON listings(seller_organization_id, lifecycle_status);
CREATE INDEX listings_user_status_idx ON listings(seller_user_id, lifecycle_status);
CREATE INDEX listings_location_gist ON listings USING gist(location_exact);

-- ===== MEDIA =====

CREATE TABLE listing_photos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  position smallint NOT NULL,
  status photo_status NOT NULL DEFAULT 'uploaded',
  original_object_key text NOT NULL,
  public_url text,
  public_avif_url text,
  public_webp_url text,
  sha256 char(64),
  perceptual_hash varchar(128),
  width integer,
  height integer,
  bytes bigint,
  plate_masked boolean NOT NULL DEFAULT false,
  watermark_applied boolean NOT NULL DEFAULT false,
  failure_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT listing_photos_position_chk CHECK (position BETWEEN 1 AND 25),
  CONSTRAINT listing_photos_bytes_chk CHECK (bytes IS NULL OR bytes <= 15728640),
  UNIQUE(listing_id, position)
);

CREATE INDEX listing_photos_listing_status_idx ON listing_photos(listing_id, status);
CREATE INDEX listing_photos_sha_idx ON listing_photos(sha256);

CREATE TABLE listing_videos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  provider varchar(64),
  url text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ===== TRUST / SELECT / APPROVED =====

CREATE TABLE verification_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL REFERENCES vehicles(id) ON DELETE RESTRICT,
  type trust_type NOT NULL,
  status trust_record_status NOT NULL DEFAULT 'pending',
  source varchar(64) NOT NULL,
  issued_at timestamptz,
  expires_at timestamptz,
  issued_by_actor_type varchar(32),
  issued_by_actor_id uuid,
  reason text,
  report_id uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX verification_vehicle_type_idx ON verification_records(vehicle_id, type, status);
CREATE UNIQUE INDEX verification_one_active_per_type_uq
  ON verification_records(vehicle_id, type)
  WHERE status = 'active';

-- ===== FAVORITES =====

CREATE TABLE favorites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  listing_id uuid NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, listing_id)
);

CREATE INDEX favorites_user_idx ON favorites(user_id, created_at DESC);

-- ===== COMPLAINTS =====

CREATE TABLE complaints (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id uuid NOT NULL REFERENCES listings(id) ON DELETE RESTRICT,
  reporter_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  reporter_session_id varchar(128),
  reason complaint_reason NOT NULL,
  comment text,
  status complaint_status NOT NULL DEFAULT 'new',
  listing_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  resolution varchar(64),
  moderator_id uuid REFERENCES users(id) ON DELETE SET NULL,
  moderator_reason text,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX complaints_status_created_idx ON complaints(status, created_at);
CREATE INDEX complaints_listing_idx ON complaints(listing_id);

-- ===== ANALYTICS =====

CREATE TABLE analytics_events (
  id bigserial PRIMARY KEY,
  event_name varchar(64) NOT NULL,
  listing_id uuid REFERENCES listings(id) ON DELETE SET NULL,
  user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  organization_id uuid REFERENCES organizations(id) ON DELETE SET NULL,
  session_id varchar(128),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX analytics_listing_event_idx ON analytics_events(listing_id, event_name, occurred_at DESC);
CREATE INDEX analytics_org_event_idx ON analytics_events(organization_id, event_name, occurred_at DESC);

-- ===== API CREDENTIALS =====

CREATE TABLE api_credentials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name varchar(120) NOT NULL,
  key_id varchar(64) NOT NULL UNIQUE,
  secret_hash text NOT NULL,
  scopes text[] NOT NULL,
  status api_credential_status NOT NULL DEFAULT 'active',
  grace_expires_at timestamptz,
  last_used_at timestamptz,
  created_by_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz
);

CREATE INDEX api_credentials_org_status_idx ON api_credentials(organization_id, status);

-- ===== WEBHOOKS =====

CREATE TABLE webhooks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  url text NOT NULL,
  secret_hash text NOT NULL,
  events text[] NOT NULL,
  status webhook_status NOT NULL DEFAULT 'active',
  failure_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX webhooks_org_status_idx ON webhooks(organization_id, status);

CREATE TABLE webhook_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  webhook_id uuid NOT NULL REFERENCES webhooks(id) ON DELETE CASCADE,
  event_id uuid NOT NULL,
  event_name varchar(64) NOT NULL,
  payload jsonb NOT NULL,
  status webhook_delivery_status NOT NULL DEFAULT 'pending',
  attempt_count integer NOT NULL DEFAULT 0,
  next_attempt_at timestamptz,
  last_response_code integer,
  last_response_body text,
  created_at timestamptz NOT NULL DEFAULT now(),
  delivered_at timestamptz
);

CREATE INDEX webhook_deliveries_retry_idx
  ON webhook_deliveries(status, next_attempt_at);

-- ===== IDEMPOTENCY =====

CREATE TABLE idempotency_keys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_type varchar(32) NOT NULL,
  actor_id uuid,
  key varchar(128) NOT NULL,
  request_hash char(64) NOT NULL,
  response_status integer,
  response_body jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  UNIQUE(actor_type, actor_id, key)
);

CREATE INDEX idempotency_expiry_idx ON idempotency_keys(expires_at);

-- ===== OUTBOX =====

CREATE TABLE outbox_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  aggregate_type varchar(64) NOT NULL,
  aggregate_id uuid NOT NULL,
  event_name varchar(64) NOT NULL,
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  attempt_count integer NOT NULL DEFAULT 0
);

CREATE INDEX outbox_unprocessed_idx ON outbox_events(created_at)
  WHERE processed_at IS NULL;

-- ===== AUDIT =====

CREATE TABLE audit_log (
  id bigserial PRIMARY KEY,
  actor_type varchar(32) NOT NULL,
  actor_id uuid,
  action varchar(120) NOT NULL,
  entity_type varchar(64) NOT NULL,
  entity_id uuid,
  reason text,
  before_data jsonb,
  after_data jsonb,
  ip inet,
  user_agent text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX audit_entity_idx ON audit_log(entity_type, entity_id, created_at DESC);
CREATE INDEX audit_actor_idx ON audit_log(actor_type, actor_id, created_at DESC);

-- ===== OTP AUDIT =====

CREATE TABLE sms_otp_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  phone_hash char(64) NOT NULL,
  ip inet,
  device_id_hash char(64),
  sent_at timestamptz NOT NULL DEFAULT now(),
  verified_at timestamptz,
  failed_attempts smallint NOT NULL DEFAULT 0,
  provider_message_id varchar(128)
);

CREATE INDEX sms_otp_phone_sent_idx ON sms_otp_requests(phone_hash, sent_at DESC);

-- ===== HELPER VIEW: CURRENT TRUST STATUS =====

CREATE VIEW vehicle_current_trust AS
SELECT
  v.id AS vehicle_id,
  CASE
    WHEN EXISTS (
      SELECT 1 FROM verification_records vr
      WHERE vr.vehicle_id = v.id
        AND vr.type = 'approved'
        AND vr.status = 'active'
        AND (vr.expires_at IS NULL OR vr.expires_at > now())
    ) THEN 'approved'
    WHEN EXISTS (
      SELECT 1 FROM verification_records vr
      WHERE vr.vehicle_id = v.id
        AND vr.type = 'select'
        AND vr.status = 'active'
        AND (vr.expires_at IS NULL OR vr.expires_at > now())
    ) THEN 'select'
    ELSE 'used'
  END AS trust_status
FROM vehicles v;

-- ===== PUBLISH VALIDATION FUNCTION =====
-- The application service should still validate in code; this helper can be used
-- transactionally before changing lifecycle_status to 'published'.

CREATE OR REPLACE FUNCTION validate_listing_publish(p_listing_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  l listings%ROWTYPE;
  ready_photos integer;
  duplicate_count integer;
BEGIN
  SELECT * INTO l
  FROM listings
  WHERE id = p_listing_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'LISTING_NOT_FOUND';
  END IF;

  SELECT count(*) INTO ready_photos
  FROM listing_photos
  WHERE listing_id = p_listing_id
    AND status = 'ready';

  IF ready_photos < 6 THEN
    RAISE EXCEPTION 'PUBLISH_REQUIREMENTS_NOT_MET: photos';
  END IF;

  SELECT count(*) INTO duplicate_count
  FROM listings
  WHERE vehicle_id = l.vehicle_id
    AND lifecycle_status = 'published'
    AND id <> p_listing_id;

  IF duplicate_count > 0 THEN
    RAISE EXCEPTION 'VIN_ACTIVE_CONFLICT';
  END IF;

  IF l.price_rub <= 0 OR l.mileage_km < 0 THEN
    RAISE EXCEPTION 'PUBLISH_REQUIREMENTS_NOT_MET: commercial_fields';
  END IF;

  IF l.city_id IS NULL OR l.location_exact IS NULL THEN
    RAISE EXCEPTION 'PUBLISH_REQUIREMENTS_NOT_MET: location';
  END IF;
END;
$$;

-- ===== SAMPLE SEED =====

INSERT INTO manufacturers(name, slug)
VALUES ('FAW', 'faw')
ON CONFLICT DO NOTHING;

COMMIT;
