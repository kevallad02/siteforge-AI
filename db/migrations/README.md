# Migration Templates

This directory stores SQL templates for data-contract migrations used by the SiteCraft ML platform.

## Usage

1. Copy a template into your target execution environment (Supabase project or PostgreSQL repo).
2. Replace template comments/placeholders as needed.
3. Run in staging first.
4. Capture rollout notes in `docs/adr`.

## Included templates

- `templates/0001_ai_training_examples_contract_template.sql`
  - Base contract constraints for generation + patch + outcomes.
- `templates/0002_ai_eval_views_template.sql`
  - Curated dataset and daily metrics views for offline/online monitoring.
- `templates/0003_phase2_provider_routing_and_eval_contract_template.sql`
  - Provider routing config, eval run/sample contracts, and eval summary view.
- `templates/0004_phase3a_tenant_model_registry_template.sql`
  - Tenant-aware model registry, model version routing, and telemetry lineage columns.
- `releases/phase2/20260215205100_phase2_provider_config_staging.sql`
  - Staging-specific provider routing defaults.
- `releases/phase2/20260215205200_phase2_provider_config_prod.sql`
  - Prod-specific provider routing defaults.
- `releases/phase2/20260215205300_phase2_provider_config_single_db.sql`
  - Single-database routing defaults (use when staging/prod share one DB).
- Use with runbook:
  - `docs/roadmap/phase-2-supabase-rollout-runbook.md`
