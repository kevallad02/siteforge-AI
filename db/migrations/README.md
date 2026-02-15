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
