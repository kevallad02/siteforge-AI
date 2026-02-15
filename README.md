# SiteCraft ML Platform

Separate repository for SiteCraft AI/ML systems work. This repo is intentionally isolated from the product app repo to keep model/data infrastructure, evaluation, and serving changes independent.

## Scope

- Training data contracts and curation
- Offline and online evaluation
- Custom inference service
- From-scratch model program artifacts

## Day 1 bootstrap status

- [x] Separate repository initialized
- [x] Base folder structure created
- [x] Initial architecture and roadmap docs added
- [x] Tooling bootstrap (`pyproject`, lint/test, CI skeleton)
- [x] First DB contract migration templates
- [x] Eval runner scaffold
- [ ] Data pipeline scaffold

## Repository structure

- `docs/adr`: architecture decision records
- `docs/roadmap`: execution plans and schedules
- `docs/contracts`: data contracts and validation rules
- `src/data_contracts`: contract code and validators
- `src/evals`: evaluation pipeline code
- `src/training`: training pipeline code
- `src/inference`: serving/inference adapters
- `scripts`: operational scripts
- `infra`: deployment infrastructure
- `tests`: automated tests

## Quickstart

```bash
./scripts/bootstrap_python_env.sh
./.venv/bin/python -m ruff check .
./.venv/bin/python -m ruff format --check .
./.venv/bin/python -m pytest
./.venv/bin/python scripts/evals/run_offline_eval.py
./.venv/bin/python scripts/evals/export_eval_records_from_supabase.py --help
./.venv/bin/python scripts/evals/generate_eval_ingest_sql.py
```

## Why This Install Flow

- Uses a repo-local `.venv` to avoid global/site-package permission issues.
- Uses `--no-build-isolation` so editable installs work reliably when network access is limited.

## Database templates

- `db/migrations/templates/0001_ai_training_examples_contract_template.sql`
- `db/migrations/templates/0002_ai_eval_views_template.sql`
- `db/migrations/templates/0003_phase2_provider_routing_and_eval_contract_template.sql`

## Supabase Phase 2 rollout artifacts

- Base migration:
  - `supabase/migrations/20260215205000_phase2_provider_routing_and_eval.sql`
- Environment overlays:
  - `db/migrations/releases/phase2/20260215205100_phase2_provider_config_staging.sql`
  - `db/migrations/releases/phase2/20260215205200_phase2_provider_config_prod.sql`
  - `db/migrations/releases/phase2/20260215205300_phase2_provider_config_single_db.sql`
- Rollout runbook:
  - `docs/roadmap/phase-2-supabase-rollout-runbook.md`

## Phase 2 kickoff assets

- `docs/roadmap/phase-2-implementation-checklist.md`
  - Workstream checklist + measurable acceptance criteria for provider abstraction and eval hardening.
- `docs/roadmap/phase-2-runtime-integration-spec.md`
  - Product repo wiring spec for runtime generation telemetry writes.
- `docs/roadmap/phase-2-canary-and-oncall.md`
  - Canary guardrails, rollback matrix, and on-call checklist.
- `docs/adr/0001-phase2-provider-routing-and-eval-gates.md`
  - Architecture decision record for routing/eval-gate policy.

## Eval ingestion pipeline

- Export real eval records from Supabase:
  - `scripts/evals/export_eval_records_from_supabase.py`
- Generate run report + SQL ingestion script:
  - `scripts/evals/generate_eval_ingest_sql.py`
- Default outputs:
  - `artifacts/evals/eval_run_report.json`
  - `artifacts/evals/eval_run_ingest.sql`
- Execute generated SQL in Supabase SQL Editor to persist into:
  - `public.ai_eval_runs`
  - `public.ai_eval_samples`

## Scheduled eval automation

- Daily workflow:
  - `.github/workflows/nightly-eval.yml`
- Required GitHub repo secrets:
  - `SUPABASE_URL`
  - `SUPABASE_SERVICE_ROLE_KEY`
