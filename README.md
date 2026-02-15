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
```

## Why This Install Flow

- Uses a repo-local `.venv` to avoid global/site-package permission issues.
- Uses `--no-build-isolation` so editable installs work reliably when network access is limited.

## Database templates

- `db/migrations/templates/0001_ai_training_examples_contract_template.sql`
- `db/migrations/templates/0002_ai_eval_views_template.sql`
