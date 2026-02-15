-- 20260215205000_phase2_provider_routing_and_eval.sql
-- Purpose:
--   Phase 2 provider routing contracts + eval run/sample contracts.
-- Notes:
--   - Concrete Supabase migration generated from db template 0003.
--   - Keeps schema changes environment-neutral; environment-specific routing values
--     are applied from the rollout runbook.
--   - Idempotent + legacy-schema-safe (column backfills, dedupe, guarded constraints).

BEGIN;

-- 1) Provider routing configuration table.
CREATE TABLE IF NOT EXISTS public.ai_provider_configs (
  id BIGSERIAL PRIMARY KEY,
  provider TEXT NOT NULL CHECK (provider IN ('openai', 'custom')),
  environment TEXT NOT NULL DEFAULT 'prod' CHECK (environment IN ('prod', 'staging', 'dev')),
  enabled BOOLEAN NOT NULL DEFAULT true,
  is_default BOOLEAN NOT NULL DEFAULT false,
  weight INTEGER NOT NULL DEFAULT 100 CHECK (weight >= 0),
  timeout_ms INTEGER NOT NULL DEFAULT 45000 CHECK (timeout_ms BETWEEN 1000 AND 180000),
  max_retries INTEGER NOT NULL DEFAULT 1 CHECK (max_retries BETWEEN 0 AND 3),
  model TEXT,
  prompt_template_version TEXT NOT NULL DEFAULT 'v1',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  UNIQUE (provider, environment)
);

-- Backfill missing columns for environments where ai_provider_configs was created earlier
-- with a narrower schema.
ALTER TABLE public.ai_provider_configs
  ADD COLUMN IF NOT EXISTS environment TEXT DEFAULT 'prod',
  ADD COLUMN IF NOT EXISTS enabled BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_default BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS weight INTEGER DEFAULT 100,
  ADD COLUMN IF NOT EXISTS timeout_ms INTEGER DEFAULT 45000,
  ADD COLUMN IF NOT EXISTS max_retries INTEGER DEFAULT 1,
  ADD COLUMN IF NOT EXISTS model TEXT,
  ADD COLUMN IF NOT EXISTS prompt_template_version TEXT DEFAULT 'v1',
  ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT timezone('utc', now()),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT timezone('utc', now());

UPDATE public.ai_provider_configs
SET
  environment = COALESCE(environment, 'prod'),
  enabled = COALESCE(enabled, true),
  is_default = COALESCE(is_default, false),
  weight = COALESCE(weight, 100),
  timeout_ms = COALESCE(timeout_ms, 45000),
  max_retries = COALESCE(max_retries, 1),
  prompt_template_version = COALESCE(prompt_template_version, 'v1'),
  metadata = COALESCE(metadata, '{}'::jsonb),
  created_at = COALESCE(created_at, timezone('utc', now())),
  updated_at = COALESCE(updated_at, timezone('utc', now()));

ALTER TABLE public.ai_provider_configs
  ALTER COLUMN environment SET DEFAULT 'prod',
  ALTER COLUMN environment SET NOT NULL,
  ALTER COLUMN enabled SET DEFAULT true,
  ALTER COLUMN enabled SET NOT NULL,
  ALTER COLUMN is_default SET DEFAULT false,
  ALTER COLUMN is_default SET NOT NULL,
  ALTER COLUMN weight SET DEFAULT 100,
  ALTER COLUMN weight SET NOT NULL,
  ALTER COLUMN timeout_ms SET DEFAULT 45000,
  ALTER COLUMN timeout_ms SET NOT NULL,
  ALTER COLUMN max_retries SET DEFAULT 1,
  ALTER COLUMN max_retries SET NOT NULL,
  ALTER COLUMN prompt_template_version SET DEFAULT 'v1',
  ALTER COLUMN prompt_template_version SET NOT NULL,
  ALTER COLUMN metadata SET DEFAULT '{}'::jsonb,
  ALTER COLUMN metadata SET NOT NULL,
  ALTER COLUMN created_at SET DEFAULT timezone('utc', now()),
  ALTER COLUMN created_at SET NOT NULL,
  ALTER COLUMN updated_at SET DEFAULT timezone('utc', now()),
  ALTER COLUMN updated_at SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_provider_configs_provider_check'
      AND conrelid = 'public.ai_provider_configs'::regclass
  ) THEN
    ALTER TABLE public.ai_provider_configs
      ADD CONSTRAINT ai_provider_configs_provider_check
      CHECK (provider IN ('openai', 'custom'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_provider_configs_environment_check'
      AND conrelid = 'public.ai_provider_configs'::regclass
  ) THEN
    ALTER TABLE public.ai_provider_configs
      ADD CONSTRAINT ai_provider_configs_environment_check
      CHECK (environment IN ('prod', 'staging', 'dev'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_provider_configs_weight_check'
      AND conrelid = 'public.ai_provider_configs'::regclass
  ) THEN
    ALTER TABLE public.ai_provider_configs
      ADD CONSTRAINT ai_provider_configs_weight_check
      CHECK (weight >= 0);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_provider_configs_timeout_ms_check'
      AND conrelid = 'public.ai_provider_configs'::regclass
  ) THEN
    ALTER TABLE public.ai_provider_configs
      ADD CONSTRAINT ai_provider_configs_timeout_ms_check
      CHECK (timeout_ms BETWEEN 1000 AND 180000);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_provider_configs_max_retries_check'
      AND conrelid = 'public.ai_provider_configs'::regclass
  ) THEN
    ALTER TABLE public.ai_provider_configs
      ADD CONSTRAINT ai_provider_configs_max_retries_check
      CHECK (max_retries BETWEEN 0 AND 3);
  END IF;
END $$;

-- Deduplicate any legacy rows so unique indexes can be created safely.
DELETE FROM public.ai_provider_configs target
USING (
  SELECT ctid
  FROM (
    SELECT
      ctid,
      row_number() OVER (
        PARTITION BY provider, environment
        ORDER BY updated_at DESC, created_at DESC, ctid DESC
      ) AS row_num
    FROM public.ai_provider_configs
  ) dedupe
  WHERE dedupe.row_num > 1
) duplicates
WHERE target.ctid = duplicates.ctid;

-- Keep only one default provider per environment.
WITH ranked_defaults AS (
  SELECT
    ctid,
    row_number() OVER (
      PARTITION BY environment
      ORDER BY updated_at DESC, created_at DESC, ctid DESC
    ) AS row_num
  FROM public.ai_provider_configs
  WHERE is_default = true
)
UPDATE public.ai_provider_configs target
SET is_default = false
FROM ranked_defaults defaults_to_disable
WHERE target.ctid = defaults_to_disable.ctid
  AND defaults_to_disable.row_num > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_provider_configs_provider_environment
  ON public.ai_provider_configs(provider, environment);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_provider_configs_default_per_env
  ON public.ai_provider_configs(environment)
  WHERE is_default = true;

CREATE INDEX IF NOT EXISTS idx_ai_provider_configs_enabled
  ON public.ai_provider_configs(environment, enabled, weight DESC);

INSERT INTO public.ai_provider_configs (
  provider,
  environment,
  enabled,
  is_default,
  weight,
  timeout_ms,
  max_retries,
  prompt_template_version,
  metadata
) VALUES
  (
    'openai',
    'prod',
    true,
    true,
    100,
    45000,
    1,
    'v1',
    '{"notes":"phase2 default provider"}'::jsonb
  ),
  (
    'custom',
    'prod',
    true,
    false,
    10,
    60000,
    0,
    'v1',
    '{"notes":"phase2 fallback candidate"}'::jsonb
  )
ON CONFLICT (provider, environment)
DO UPDATE SET
  enabled = EXCLUDED.enabled,
  is_default = EXCLUDED.is_default,
  weight = EXCLUDED.weight,
  timeout_ms = EXCLUDED.timeout_ms,
  max_retries = EXCLUDED.max_retries,
  prompt_template_version = EXCLUDED.prompt_template_version,
  metadata = EXCLUDED.metadata,
  updated_at = timezone('utc', now());

-- 2) Add provider-routing/eval telemetry columns to training examples.
ALTER TABLE public.ai_training_examples
  ADD COLUMN IF NOT EXISTS request_id UUID,
  ADD COLUMN IF NOT EXISTS requested_provider TEXT,
  ADD COLUMN IF NOT EXISTS selected_provider TEXT,
  ADD COLUMN IF NOT EXISTS route_strategy TEXT NOT NULL DEFAULT 'single_provider',
  ADD COLUMN IF NOT EXISTS fallback_provider TEXT,
  ADD COLUMN IF NOT EXISTS fallback_used BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS latency_ms INTEGER,
  ADD COLUMN IF NOT EXISTS prompt_template_version TEXT NOT NULL DEFAULT 'v1';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_training_examples_requested_provider_check'
      AND conrelid = 'public.ai_training_examples'::regclass
  ) THEN
    ALTER TABLE public.ai_training_examples
      ADD CONSTRAINT ai_training_examples_requested_provider_check
      CHECK (
        requested_provider IS NULL
        OR requested_provider IN ('openai', 'custom')
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_training_examples_selected_provider_check'
      AND conrelid = 'public.ai_training_examples'::regclass
  ) THEN
    ALTER TABLE public.ai_training_examples
      ADD CONSTRAINT ai_training_examples_selected_provider_check
      CHECK (
        selected_provider IS NULL
        OR selected_provider IN ('openai', 'custom')
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_training_examples_fallback_provider_check'
      AND conrelid = 'public.ai_training_examples'::regclass
  ) THEN
    ALTER TABLE public.ai_training_examples
      ADD CONSTRAINT ai_training_examples_fallback_provider_check
      CHECK (
        fallback_provider IS NULL
        OR fallback_provider IN ('openai', 'custom')
      );
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_training_examples_route_strategy_check'
      AND conrelid = 'public.ai_training_examples'::regclass
  ) THEN
    ALTER TABLE public.ai_training_examples
      ADD CONSTRAINT ai_training_examples_route_strategy_check
      CHECK (route_strategy IN ('single_provider', 'weighted', 'fallback'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_training_examples_latency_ms_check'
      AND conrelid = 'public.ai_training_examples'::regclass
  ) THEN
    ALTER TABLE public.ai_training_examples
      ADD CONSTRAINT ai_training_examples_latency_ms_check
      CHECK (latency_ms IS NULL OR latency_ms BETWEEN 0 AND 300000);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_ai_training_examples_provider_created
  ON public.ai_training_examples(selected_provider, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_training_examples_route_created
  ON public.ai_training_examples(route_strategy, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_training_examples_request_id
  ON public.ai_training_examples(request_id)
  WHERE request_id IS NOT NULL;

-- 3) Eval run + eval sample contracts.
CREATE TABLE IF NOT EXISTS public.ai_eval_runs (
  run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  run_type TEXT NOT NULL CHECK (run_type IN ('offline', 'shadow', 'canary')),
  triggered_by TEXT,
  commit_sha TEXT,
  dataset_ref TEXT,
  thresholds JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'passed', 'failed', 'aborted')),
  started_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  finished_at TIMESTAMPTZ,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_ai_eval_runs_status_started
  ON public.ai_eval_runs(status, started_at DESC);

CREATE TABLE IF NOT EXISTS public.ai_eval_samples (
  id BIGSERIAL PRIMARY KEY,
  run_id UUID NOT NULL REFERENCES public.ai_eval_runs(run_id) ON DELETE CASCADE,
  request_id UUID,
  requested_provider TEXT,
  selected_provider TEXT,
  route_strategy TEXT,
  fallback_used BOOLEAN NOT NULL DEFAULT false,
  latency_ms INTEGER,
  schema_valid BOOLEAN NOT NULL,
  patch_apply_success BOOLEAN NOT NULL,
  edited_after_generate BOOLEAN NOT NULL,
  published_within_7d BOOLEAN NOT NULL,
  safety_html_tailwind_compliant BOOLEAN NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

-- Backfill missing columns for environments where ai_eval_samples was created earlier
-- with a narrower schema.
ALTER TABLE public.ai_eval_samples
  ADD COLUMN IF NOT EXISTS request_id UUID,
  ADD COLUMN IF NOT EXISTS requested_provider TEXT,
  ADD COLUMN IF NOT EXISTS selected_provider TEXT,
  ADD COLUMN IF NOT EXISTS route_strategy TEXT,
  ADD COLUMN IF NOT EXISTS fallback_used BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS latency_ms INTEGER,
  ADD COLUMN IF NOT EXISTS schema_valid BOOLEAN,
  ADD COLUMN IF NOT EXISTS patch_apply_success BOOLEAN,
  ADD COLUMN IF NOT EXISTS edited_after_generate BOOLEAN,
  ADD COLUMN IF NOT EXISTS published_within_7d BOOLEAN,
  ADD COLUMN IF NOT EXISTS safety_html_tailwind_compliant BOOLEAN,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT timezone('utc', now()),
  ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb;

UPDATE public.ai_eval_samples
SET
  fallback_used = COALESCE(fallback_used, false),
  created_at = COALESCE(created_at, timezone('utc', now())),
  metadata = COALESCE(metadata, '{}'::jsonb);

ALTER TABLE public.ai_eval_samples
  ALTER COLUMN fallback_used SET DEFAULT false,
  ALTER COLUMN fallback_used SET NOT NULL,
  ALTER COLUMN created_at SET DEFAULT timezone('utc', now()),
  ALTER COLUMN created_at SET NOT NULL,
  ALTER COLUMN metadata SET DEFAULT '{}'::jsonb,
  ALTER COLUMN metadata SET NOT NULL;

DO $$
DECLARE
  target_id_type TEXT;
  existing_id_type TEXT;
BEGIN
  SELECT a.atttypid::regtype::text
  INTO target_id_type
  FROM pg_attribute a
  WHERE a.attrelid = 'public.ai_training_examples'::regclass
    AND a.attname = 'id'
    AND a.attnum > 0
    AND NOT a.attisdropped;

  IF target_id_type IS NULL THEN
    RAISE EXCEPTION 'public.ai_training_examples.id not found';
  END IF;

  IF target_id_type NOT IN ('uuid', 'bigint', 'integer') THEN
    RAISE EXCEPTION
      'Unsupported ai_training_examples.id type for FK mapping: %',
      target_id_type;
  END IF;

  SELECT a.atttypid::regtype::text
  INTO existing_id_type
  FROM pg_attribute a
  WHERE a.attrelid = 'public.ai_eval_samples'::regclass
    AND a.attname = 'training_example_id'
    AND a.attnum > 0
    AND NOT a.attisdropped;

  IF existing_id_type IS NULL THEN
    EXECUTE format(
      'ALTER TABLE public.ai_eval_samples ADD COLUMN training_example_id %s',
      target_id_type
    );
  ELSIF existing_id_type <> target_id_type THEN
    RAISE EXCEPTION
      'ai_eval_samples.training_example_id type % does not match ai_training_examples.id type %',
      existing_id_type,
      target_id_type;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_eval_samples_training_example_id_fkey'
      AND conrelid = 'public.ai_eval_samples'::regclass
  ) THEN
    ALTER TABLE public.ai_eval_samples
      ADD CONSTRAINT ai_eval_samples_training_example_id_fkey
      FOREIGN KEY (training_example_id)
      REFERENCES public.ai_training_examples(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_ai_eval_samples_run_id
  ON public.ai_eval_samples(run_id);

CREATE INDEX IF NOT EXISTS idx_ai_eval_samples_run_provider
  ON public.ai_eval_samples(run_id, selected_provider);

-- 4) Eval summary view for release gating and ops dashboards.
DROP VIEW IF EXISTS public.ai_eval_run_summary_v1;

CREATE VIEW public.ai_eval_run_summary_v1 AS
SELECT
  s.run_id,
  count(*) AS total_records,
  avg(CASE WHEN s.schema_valid THEN 1.0 ELSE 0.0 END) AS schema_valid_rate,
  avg(CASE WHEN s.patch_apply_success THEN 1.0 ELSE 0.0 END) AS patch_apply_success,
  avg(CASE WHEN s.edited_after_generate THEN 1.0 ELSE 0.0 END) AS edit_after_generate_rate,
  avg(CASE WHEN s.published_within_7d THEN 1.0 ELSE 0.0 END) AS publish_conversion_proxy,
  avg(
    CASE WHEN s.safety_html_tailwind_compliant THEN 1.0 ELSE 0.0 END
  ) AS safety_html_tailwind_compliance,
  avg(CASE WHEN s.fallback_used THEN 1.0 ELSE 0.0 END) AS fallback_rate,
  percentile_cont(0.95) WITHIN GROUP (
    ORDER BY s.latency_ms
  ) FILTER (WHERE s.latency_ms IS NOT NULL) AS p95_latency_ms,
  min(s.created_at) AS first_sample_at,
  max(s.created_at) AS last_sample_at
FROM public.ai_eval_samples s
GROUP BY s.run_id;

COMMIT;
