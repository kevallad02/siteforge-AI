-- 20260215205300_phase2_provider_config_single_db.sql
-- Purpose:
--   Single-database provider routing defaults (no separate staging/prod DBs).
-- Strategy:
--   Use environment='prod' as the only active routing scope.
-- Prerequisite:
--   20260215205000_phase2_provider_routing_and_eval.sql has been applied.

BEGIN;

INSERT INTO public.ai_provider_configs (
  provider,
  environment,
  enabled,
  is_default,
  weight,
  timeout_ms,
  max_retries,
  model,
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
    NULL,
    'v1',
    '{"release":"phase2","env":"single-db","role":"primary"}'::jsonb
  ),
  (
    'custom',
    'prod',
    true,
    false,
    5,
    60000,
    0,
    NULL,
    'v1',
    '{"release":"phase2","env":"single-db","role":"secondary_low_traffic"}'::jsonb
  )
ON CONFLICT (provider, environment)
DO UPDATE SET
  enabled = EXCLUDED.enabled,
  is_default = EXCLUDED.is_default,
  weight = EXCLUDED.weight,
  timeout_ms = EXCLUDED.timeout_ms,
  max_retries = EXCLUDED.max_retries,
  model = EXCLUDED.model,
  prompt_template_version = EXCLUDED.prompt_template_version,
  metadata = EXCLUDED.metadata,
  updated_at = timezone('utc', now());

-- Disable non-prod environment rows to avoid accidental routing ambiguity in single DB mode.
UPDATE public.ai_provider_configs
SET enabled = false,
    is_default = false,
    updated_at = timezone('utc', now())
WHERE environment <> 'prod'
  AND (enabled = true OR is_default = true);

-- Enforce one default provider in prod.
UPDATE public.ai_provider_configs
SET is_default = false,
    updated_at = timezone('utc', now())
WHERE environment = 'prod'
  AND provider <> 'openai'
  AND is_default = true;

COMMIT;
