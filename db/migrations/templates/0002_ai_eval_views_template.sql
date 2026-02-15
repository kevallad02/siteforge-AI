-- 0002_ai_eval_views_template.sql
-- Purpose:
--   Provide first-pass curated training view and daily eval metrics view.
-- Notes:
--   Assumes ai_training_examples table contains metadata keys documented in contracts.

BEGIN;

CREATE OR REPLACE VIEW public.ai_training_examples_curated_v1 AS
SELECT
  id,
  user_id,
  site_id,
  source,
  prompt_hash,
  prompt,
  provider,
  model,
  generation_params,
  input_site_json,
  output_site_json,
  patch_operations,
  metadata,
  created_at
FROM public.ai_training_examples
WHERE jsonb_typeof(output_site_json) = 'object'
  AND source IN ('generation', 'generation_cached', 'patch', 'save', 'publish')
  AND COALESCE(NULLIF(prompt, ''), 'ok') IS NOT NULL
  AND COALESCE((metadata->>'dropForTraining')::boolean, false) = false;

CREATE OR REPLACE VIEW public.ai_eval_daily_v1 AS
SELECT
  date_trunc('day', created_at) AS day,
  count(*) AS total_records,
  avg(CASE WHEN COALESCE((metadata->>'schemaValid')::boolean, true) THEN 1.0 ELSE 0.0 END) AS schema_valid_rate,
  avg(CASE WHEN COALESCE((metadata->>'patchApplySuccess')::boolean, true) THEN 1.0 ELSE 0.0 END) AS patch_apply_success,
  avg(CASE WHEN COALESCE((metadata->>'editedAfterGenerate')::boolean, false) THEN 1.0 ELSE 0.0 END) AS edit_after_generate_rate,
  avg(CASE WHEN COALESCE((metadata->>'publishedWithin7d')::boolean, false) THEN 1.0 ELSE 0.0 END) AS publish_conversion_proxy,
  avg(CASE WHEN COALESCE((metadata->>'safetyHtmlTailwindCompliant')::boolean, true) THEN 1.0 ELSE 0.0 END) AS safety_html_tailwind_compliance
FROM public.ai_training_examples
GROUP BY 1
ORDER BY 1 DESC;

COMMIT;
