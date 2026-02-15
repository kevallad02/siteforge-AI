-- 0004_phase3a_tenant_model_registry_template.sql
-- Purpose:
--   Phase 3A tenant-aware model registry and inference routing contracts.
-- Notes:
--   - Extends provider routing with tenant/model-version level routes.
--   - Adds telemetry link columns on generation events + training examples.
--   - Designed to be idempotent and safe on partially-migrated environments.

BEGIN;

-- 1) Tenant-aware model registry.
CREATE TABLE IF NOT EXISTS public.ai_models (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID,
  environment TEXT NOT NULL DEFAULT 'prod' CHECK (environment IN ('prod', 'staging', 'dev')),
  model_key TEXT NOT NULL,
  display_name TEXT NOT NULL,
  task TEXT NOT NULL DEFAULT 'site_generation' CHECK (task IN ('site_generation')),
  provider TEXT NOT NULL CHECK (provider IN ('openai', 'custom')),
  visibility TEXT NOT NULL DEFAULT 'private' CHECK (visibility IN ('private', 'org', 'public')),
  status TEXT NOT NULL DEFAULT 'ready' CHECK (status IN ('draft', 'ready', 'disabled', 'archived')),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  UNIQUE (environment, model_key)
);

ALTER TABLE public.ai_models
  ADD COLUMN IF NOT EXISTS tenant_id UUID,
  ADD COLUMN IF NOT EXISTS environment TEXT DEFAULT 'prod',
  ADD COLUMN IF NOT EXISTS model_key TEXT,
  ADD COLUMN IF NOT EXISTS display_name TEXT,
  ADD COLUMN IF NOT EXISTS task TEXT DEFAULT 'site_generation',
  ADD COLUMN IF NOT EXISTS provider TEXT,
  ADD COLUMN IF NOT EXISTS visibility TEXT DEFAULT 'private',
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'ready',
  ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT timezone('utc', now()),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT timezone('utc', now());

UPDATE public.ai_models
SET
  environment = COALESCE(environment, 'prod'),
  model_key = COALESCE(model_key, id::text),
  display_name = COALESCE(display_name, model_key, id::text),
  task = COALESCE(task, 'site_generation'),
  visibility = COALESCE(visibility, 'private'),
  status = COALESCE(status, 'ready'),
  metadata = COALESCE(metadata, '{}'::jsonb),
  created_at = COALESCE(created_at, timezone('utc', now())),
  updated_at = COALESCE(updated_at, timezone('utc', now()));

ALTER TABLE public.ai_models
  ALTER COLUMN environment SET DEFAULT 'prod',
  ALTER COLUMN environment SET NOT NULL,
  ALTER COLUMN model_key SET NOT NULL,
  ALTER COLUMN display_name SET NOT NULL,
  ALTER COLUMN task SET DEFAULT 'site_generation',
  ALTER COLUMN task SET NOT NULL,
  ALTER COLUMN provider SET NOT NULL,
  ALTER COLUMN visibility SET DEFAULT 'private',
  ALTER COLUMN visibility SET NOT NULL,
  ALTER COLUMN status SET DEFAULT 'ready',
  ALTER COLUMN status SET NOT NULL,
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
    WHERE conname = 'ai_models_environment_check'
      AND conrelid = 'public.ai_models'::regclass
  ) THEN
    ALTER TABLE public.ai_models
      ADD CONSTRAINT ai_models_environment_check
      CHECK (environment IN ('prod', 'staging', 'dev'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_models_provider_check'
      AND conrelid = 'public.ai_models'::regclass
  ) THEN
    ALTER TABLE public.ai_models
      ADD CONSTRAINT ai_models_provider_check
      CHECK (provider IN ('openai', 'custom'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_models_task_check'
      AND conrelid = 'public.ai_models'::regclass
  ) THEN
    ALTER TABLE public.ai_models
      ADD CONSTRAINT ai_models_task_check
      CHECK (task IN ('site_generation'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_models_visibility_check'
      AND conrelid = 'public.ai_models'::regclass
  ) THEN
    ALTER TABLE public.ai_models
      ADD CONSTRAINT ai_models_visibility_check
      CHECK (visibility IN ('private', 'org', 'public'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_models_status_check'
      AND conrelid = 'public.ai_models'::regclass
  ) THEN
    ALTER TABLE public.ai_models
      ADD CONSTRAINT ai_models_status_check
      CHECK (status IN ('draft', 'ready', 'disabled', 'archived'));
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_models_environment_model_key
  ON public.ai_models(environment, model_key);

CREATE INDEX IF NOT EXISTS idx_ai_models_env_tenant_task
  ON public.ai_models(environment, tenant_id, task, status);

-- 2) Model versions for routing + serving details.
CREATE TABLE IF NOT EXISTS public.ai_model_versions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model_id UUID NOT NULL REFERENCES public.ai_models(id) ON DELETE CASCADE,
  version_label TEXT NOT NULL,
  provider TEXT NOT NULL CHECK (provider IN ('openai', 'custom')),
  model_ref TEXT NOT NULL,
  timeout_ms INTEGER NOT NULL DEFAULT 18000 CHECK (timeout_ms BETWEEN 1000 AND 180000),
  can_use_fallback BOOLEAN NOT NULL DEFAULT true,
  is_default BOOLEAN NOT NULL DEFAULT false,
  prompt_template_version TEXT NOT NULL DEFAULT 'site-json.v2',
  status TEXT NOT NULL DEFAULT 'ready' CHECK (status IN ('draft', 'ready', 'disabled', 'failed')),
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  UNIQUE (model_id, version_label)
);

ALTER TABLE public.ai_model_versions
  ADD COLUMN IF NOT EXISTS model_id UUID,
  ADD COLUMN IF NOT EXISTS version_label TEXT,
  ADD COLUMN IF NOT EXISTS provider TEXT,
  ADD COLUMN IF NOT EXISTS model_ref TEXT,
  ADD COLUMN IF NOT EXISTS timeout_ms INTEGER DEFAULT 18000,
  ADD COLUMN IF NOT EXISTS can_use_fallback BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS is_default BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS prompt_template_version TEXT DEFAULT 'site-json.v2',
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'ready',
  ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT timezone('utc', now()),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT timezone('utc', now());

UPDATE public.ai_model_versions
SET
  timeout_ms = COALESCE(timeout_ms, 18000),
  can_use_fallback = COALESCE(can_use_fallback, true),
  is_default = COALESCE(is_default, false),
  prompt_template_version = COALESCE(prompt_template_version, 'site-json.v2'),
  status = COALESCE(status, 'ready'),
  metadata = COALESCE(metadata, '{}'::jsonb),
  created_at = COALESCE(created_at, timezone('utc', now())),
  updated_at = COALESCE(updated_at, timezone('utc', now()));

ALTER TABLE public.ai_model_versions
  ALTER COLUMN model_id SET NOT NULL,
  ALTER COLUMN version_label SET NOT NULL,
  ALTER COLUMN provider SET NOT NULL,
  ALTER COLUMN model_ref SET NOT NULL,
  ALTER COLUMN timeout_ms SET DEFAULT 18000,
  ALTER COLUMN timeout_ms SET NOT NULL,
  ALTER COLUMN can_use_fallback SET DEFAULT true,
  ALTER COLUMN can_use_fallback SET NOT NULL,
  ALTER COLUMN is_default SET DEFAULT false,
  ALTER COLUMN is_default SET NOT NULL,
  ALTER COLUMN prompt_template_version SET DEFAULT 'site-json.v2',
  ALTER COLUMN prompt_template_version SET NOT NULL,
  ALTER COLUMN status SET DEFAULT 'ready',
  ALTER COLUMN status SET NOT NULL,
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
    WHERE conname = 'ai_model_versions_provider_check'
      AND conrelid = 'public.ai_model_versions'::regclass
  ) THEN
    ALTER TABLE public.ai_model_versions
      ADD CONSTRAINT ai_model_versions_provider_check
      CHECK (provider IN ('openai', 'custom'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_model_versions_status_check'
      AND conrelid = 'public.ai_model_versions'::regclass
  ) THEN
    ALTER TABLE public.ai_model_versions
      ADD CONSTRAINT ai_model_versions_status_check
      CHECK (status IN ('draft', 'ready', 'disabled', 'failed'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_model_versions_timeout_ms_check'
      AND conrelid = 'public.ai_model_versions'::regclass
  ) THEN
    ALTER TABLE public.ai_model_versions
      ADD CONSTRAINT ai_model_versions_timeout_ms_check
      CHECK (timeout_ms BETWEEN 1000 AND 180000);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_model_versions_model_version
  ON public.ai_model_versions(model_id, version_label);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_model_versions_default_per_model
  ON public.ai_model_versions(model_id)
  WHERE is_default = true;

CREATE INDEX IF NOT EXISTS idx_ai_model_versions_ready_lookup
  ON public.ai_model_versions(model_id, status, updated_at DESC);

-- 3) Tenant route table that maps tenant/task/provider => model versions.
CREATE TABLE IF NOT EXISTS public.ai_tenant_routes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID,
  environment TEXT NOT NULL DEFAULT 'prod' CHECK (environment IN ('prod', 'staging', 'dev')),
  task TEXT NOT NULL DEFAULT 'site_generation' CHECK (task IN ('site_generation')),
  requested_provider TEXT CHECK (requested_provider IN ('openai', 'custom')),
  primary_model_version_id UUID NOT NULL REFERENCES public.ai_model_versions(id) ON DELETE RESTRICT,
  fallback_model_version_id UUID REFERENCES public.ai_model_versions(id) ON DELETE RESTRICT,
  is_active BOOLEAN NOT NULL DEFAULT true,
  priority INTEGER NOT NULL DEFAULT 100 CHECK (priority BETWEEN 1 AND 1000),
  route_strategy TEXT NOT NULL DEFAULT 'single_provider' CHECK (route_strategy IN ('single_provider', 'weighted', 'fallback')),
  prompt_template_version TEXT NOT NULL DEFAULT 'site-json.v2',
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now()),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc', now())
);

ALTER TABLE public.ai_tenant_routes
  ADD COLUMN IF NOT EXISTS tenant_id UUID,
  ADD COLUMN IF NOT EXISTS environment TEXT DEFAULT 'prod',
  ADD COLUMN IF NOT EXISTS task TEXT DEFAULT 'site_generation',
  ADD COLUMN IF NOT EXISTS requested_provider TEXT,
  ADD COLUMN IF NOT EXISTS primary_model_version_id UUID,
  ADD COLUMN IF NOT EXISTS fallback_model_version_id UUID,
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS priority INTEGER DEFAULT 100,
  ADD COLUMN IF NOT EXISTS route_strategy TEXT DEFAULT 'single_provider',
  ADD COLUMN IF NOT EXISTS prompt_template_version TEXT DEFAULT 'site-json.v2',
  ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT timezone('utc', now()),
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT timezone('utc', now());

UPDATE public.ai_tenant_routes
SET
  environment = COALESCE(environment, 'prod'),
  task = COALESCE(task, 'site_generation'),
  is_active = COALESCE(is_active, true),
  priority = COALESCE(priority, 100),
  route_strategy = COALESCE(route_strategy, 'single_provider'),
  prompt_template_version = COALESCE(prompt_template_version, 'site-json.v2'),
  metadata = COALESCE(metadata, '{}'::jsonb),
  created_at = COALESCE(created_at, timezone('utc', now())),
  updated_at = COALESCE(updated_at, timezone('utc', now()));

ALTER TABLE public.ai_tenant_routes
  ALTER COLUMN environment SET DEFAULT 'prod',
  ALTER COLUMN environment SET NOT NULL,
  ALTER COLUMN task SET DEFAULT 'site_generation',
  ALTER COLUMN task SET NOT NULL,
  ALTER COLUMN primary_model_version_id SET NOT NULL,
  ALTER COLUMN is_active SET DEFAULT true,
  ALTER COLUMN is_active SET NOT NULL,
  ALTER COLUMN priority SET DEFAULT 100,
  ALTER COLUMN priority SET NOT NULL,
  ALTER COLUMN route_strategy SET DEFAULT 'single_provider',
  ALTER COLUMN route_strategy SET NOT NULL,
  ALTER COLUMN prompt_template_version SET DEFAULT 'site-json.v2',
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
    WHERE conname = 'ai_tenant_routes_environment_check'
      AND conrelid = 'public.ai_tenant_routes'::regclass
  ) THEN
    ALTER TABLE public.ai_tenant_routes
      ADD CONSTRAINT ai_tenant_routes_environment_check
      CHECK (environment IN ('prod', 'staging', 'dev'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_tenant_routes_task_check'
      AND conrelid = 'public.ai_tenant_routes'::regclass
  ) THEN
    ALTER TABLE public.ai_tenant_routes
      ADD CONSTRAINT ai_tenant_routes_task_check
      CHECK (task IN ('site_generation'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_tenant_routes_requested_provider_check'
      AND conrelid = 'public.ai_tenant_routes'::regclass
  ) THEN
    ALTER TABLE public.ai_tenant_routes
      ADD CONSTRAINT ai_tenant_routes_requested_provider_check
      CHECK (requested_provider IS NULL OR requested_provider IN ('openai', 'custom'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_tenant_routes_priority_check'
      AND conrelid = 'public.ai_tenant_routes'::regclass
  ) THEN
    ALTER TABLE public.ai_tenant_routes
      ADD CONSTRAINT ai_tenant_routes_priority_check
      CHECK (priority BETWEEN 1 AND 1000);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_tenant_routes_route_strategy_check'
      AND conrelid = 'public.ai_tenant_routes'::regclass
  ) THEN
    ALTER TABLE public.ai_tenant_routes
      ADD CONSTRAINT ai_tenant_routes_route_strategy_check
      CHECK (route_strategy IN ('single_provider', 'weighted', 'fallback'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_ai_tenant_routes_lookup
  ON public.ai_tenant_routes(environment, tenant_id, task, requested_provider, is_active, priority);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_tenant_routes_unique_tenant_provider
  ON public.ai_tenant_routes(
    COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
    environment,
    task,
    requested_provider
  )
  WHERE requested_provider IS NOT NULL AND is_active = true;

CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_tenant_routes_unique_tenant_default
  ON public.ai_tenant_routes(
    COALESCE(tenant_id, '00000000-0000-0000-0000-000000000000'::uuid),
    environment,
    task
  )
  WHERE requested_provider IS NULL AND is_active = true;

-- 4) Telemetry linking columns for tenant/model route lineage.
ALTER TABLE public.ai_generation_events
  ADD COLUMN IF NOT EXISTS tenant_id UUID,
  ADD COLUMN IF NOT EXISTS route_id UUID,
  ADD COLUMN IF NOT EXISTS model_id UUID,
  ADD COLUMN IF NOT EXISTS model_version_id UUID;

ALTER TABLE public.ai_training_examples
  ADD COLUMN IF NOT EXISTS tenant_id UUID,
  ADD COLUMN IF NOT EXISTS route_id UUID,
  ADD COLUMN IF NOT EXISTS model_id UUID,
  ADD COLUMN IF NOT EXISTS model_version_id UUID;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_generation_events_route_id_fkey'
      AND conrelid = 'public.ai_generation_events'::regclass
  ) THEN
    ALTER TABLE public.ai_generation_events
      ADD CONSTRAINT ai_generation_events_route_id_fkey
      FOREIGN KEY (route_id)
      REFERENCES public.ai_tenant_routes(id)
      ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_generation_events_model_id_fkey'
      AND conrelid = 'public.ai_generation_events'::regclass
  ) THEN
    ALTER TABLE public.ai_generation_events
      ADD CONSTRAINT ai_generation_events_model_id_fkey
      FOREIGN KEY (model_id)
      REFERENCES public.ai_models(id)
      ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_generation_events_model_version_id_fkey'
      AND conrelid = 'public.ai_generation_events'::regclass
  ) THEN
    ALTER TABLE public.ai_generation_events
      ADD CONSTRAINT ai_generation_events_model_version_id_fkey
      FOREIGN KEY (model_version_id)
      REFERENCES public.ai_model_versions(id)
      ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_training_examples_route_id_fkey'
      AND conrelid = 'public.ai_training_examples'::regclass
  ) THEN
    ALTER TABLE public.ai_training_examples
      ADD CONSTRAINT ai_training_examples_route_id_fkey
      FOREIGN KEY (route_id)
      REFERENCES public.ai_tenant_routes(id)
      ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_training_examples_model_id_fkey'
      AND conrelid = 'public.ai_training_examples'::regclass
  ) THEN
    ALTER TABLE public.ai_training_examples
      ADD CONSTRAINT ai_training_examples_model_id_fkey
      FOREIGN KEY (model_id)
      REFERENCES public.ai_models(id)
      ON DELETE SET NULL;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_training_examples_model_version_id_fkey'
      AND conrelid = 'public.ai_training_examples'::regclass
  ) THEN
    ALTER TABLE public.ai_training_examples
      ADD CONSTRAINT ai_training_examples_model_version_id_fkey
      FOREIGN KEY (model_version_id)
      REFERENCES public.ai_model_versions(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_ai_generation_events_tenant_created
  ON public.ai_generation_events(tenant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_generation_events_model_version_created
  ON public.ai_generation_events(model_version_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_training_examples_tenant_created
  ON public.ai_training_examples(tenant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_training_examples_model_version_created
  ON public.ai_training_examples(model_version_id, created_at DESC);

-- 5) Seed platform default models/versions/routes for prod.
INSERT INTO public.ai_models (
  tenant_id,
  environment,
  model_key,
  display_name,
  task,
  provider,
  visibility,
  status,
  metadata
)
VALUES
  (
    NULL,
    'prod',
    'platform-openai-default',
    'Platform OpenAI Default',
    'site_generation',
    'openai',
    'public',
    'ready',
    '{"managedBy":"platform","phase":"3A"}'::jsonb
  ),
  (
    NULL,
    'prod',
    'platform-custom-default',
    'Platform Custom Default',
    'site_generation',
    'custom',
    'public',
    'ready',
    '{"managedBy":"platform","phase":"3A"}'::jsonb
  )
ON CONFLICT (environment, model_key)
DO UPDATE SET
  display_name = EXCLUDED.display_name,
  task = EXCLUDED.task,
  provider = EXCLUDED.provider,
  visibility = EXCLUDED.visibility,
  status = EXCLUDED.status,
  metadata = EXCLUDED.metadata,
  updated_at = timezone('utc', now());

WITH openai_model AS (
  SELECT id
  FROM public.ai_models
  WHERE environment = 'prod' AND model_key = 'platform-openai-default'
),
custom_model AS (
  SELECT id
  FROM public.ai_models
  WHERE environment = 'prod' AND model_key = 'platform-custom-default'
)
INSERT INTO public.ai_model_versions (
  model_id,
  version_label,
  provider,
  model_ref,
  timeout_ms,
  can_use_fallback,
  is_default,
  prompt_template_version,
  status,
  metadata
)
SELECT
  openai_model.id,
  'v1',
  'openai',
  'gpt-4.1-mini',
  18000,
  true,
  true,
  'site-json.v2',
  'ready',
  '{"seeded":true}'::jsonb
FROM openai_model
UNION ALL
SELECT
  custom_model.id,
  'v1',
  'custom',
  'custom-template-v1',
  8000,
  false,
  true,
  'site-json.v2',
  'ready',
  '{"seeded":true}'::jsonb
FROM custom_model
ON CONFLICT (model_id, version_label)
DO UPDATE SET
  provider = EXCLUDED.provider,
  model_ref = EXCLUDED.model_ref,
  timeout_ms = EXCLUDED.timeout_ms,
  can_use_fallback = EXCLUDED.can_use_fallback,
  is_default = EXCLUDED.is_default,
  prompt_template_version = EXCLUDED.prompt_template_version,
  status = EXCLUDED.status,
  metadata = EXCLUDED.metadata,
  updated_at = timezone('utc', now());

WITH openai_version AS (
  SELECT v.id
  FROM public.ai_model_versions v
  JOIN public.ai_models m ON m.id = v.model_id
  WHERE m.environment = 'prod'
    AND m.model_key = 'platform-openai-default'
    AND v.version_label = 'v1'
),
custom_version AS (
  SELECT v.id
  FROM public.ai_model_versions v
  JOIN public.ai_models m ON m.id = v.model_id
  WHERE m.environment = 'prod'
    AND m.model_key = 'platform-custom-default'
    AND v.version_label = 'v1'
)
INSERT INTO public.ai_tenant_routes (
  tenant_id,
  environment,
  task,
  requested_provider,
  primary_model_version_id,
  fallback_model_version_id,
  is_active,
  priority,
  route_strategy,
  prompt_template_version,
  metadata
)
SELECT
  NULL,
  'prod',
  'site_generation',
  route_input.requested_provider,
  route_input.primary_model_version_id,
  route_input.fallback_model_version_id,
  true,
  route_input.priority,
  route_input.route_strategy,
  'site-json.v2',
  route_input.metadata
FROM (
  SELECT
    'openai'::TEXT AS requested_provider,
    openai_version.id AS primary_model_version_id,
    custom_version.id AS fallback_model_version_id,
    50 AS priority,
    'fallback'::TEXT AS route_strategy,
    '{"scope":"platform","seeded":true}'::jsonb AS metadata
  FROM openai_version, custom_version
  UNION ALL
  SELECT
    'custom'::TEXT AS requested_provider,
    custom_version.id,
    NULL::UUID,
    60,
    'single_provider'::TEXT,
    '{"scope":"platform","seeded":true}'::jsonb
  FROM custom_version
  UNION ALL
  SELECT
    NULL::TEXT AS requested_provider,
    openai_version.id,
    custom_version.id,
    100,
    'fallback'::TEXT,
    '{"scope":"platform","seeded":true,"defaultRoute":true}'::jsonb
  FROM openai_version, custom_version
) AS route_input
WHERE NOT EXISTS (
  SELECT 1
  FROM public.ai_tenant_routes existing
  WHERE existing.tenant_id IS NULL
    AND existing.environment = 'prod'
    AND existing.task = 'site_generation'
    AND existing.requested_provider IS NOT DISTINCT FROM route_input.requested_provider
    AND existing.is_active = true
);

COMMIT;
