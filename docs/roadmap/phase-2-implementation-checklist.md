# Phase 2 Implementation Checklist

Scope: provider abstraction hardening + evaluation pipeline hardening.

Interpretation:
- This checklist marks work completed in the ML platform repo.
- Deployment/execution in product runtime and live Supabase still requires separate completion steps (see "Remaining Execution").

Status scale:
- `[ ]` not started
- `[~]` in progress
- `[x]` complete

## Assumptions

- Phase 1 contracts are already deployed in product DB.
- `public.ai_training_examples` is the canonical training table.
- Product app continues using `openai` and `custom` providers.
- This repo owns contract templates, eval tooling, and rollout playbooks.

## Workstream 1: Provider Routing Controls

- `[x]` Add provider routing config table contract (`ai_provider_configs`) with:
  - `provider`, `environment`, `enabled`, `is_default`, `weight`, `timeout_ms`, `max_retries`, `model`, `prompt_template_version`, `metadata`.
- `[x]` Add non-breaking telemetry columns to `ai_training_examples`:
  - `request_id`, `requested_provider`, `selected_provider`, `route_strategy`, `fallback_provider`, `fallback_used`, `latency_ms`, `prompt_template_version`.
- `[x]` Seed deterministic defaults:
  - `openai` enabled + default in `prod`.
  - `custom` enabled + non-default in `prod`.
- `[x]` Add indexes for provider routing analysis:
  - `(selected_provider, created_at desc)`, `(request_id)`, `(route_strategy, created_at desc)`.

Acceptance criteria:
- 100% of new generation records include `selected_provider`.
- 100% of fallback executions set `fallback_used = true`.
- P95 generation latency query executes in < 1s on 1M-row benchmark table.

## Workstream 2: Eval Run Contracts

- `[x]` Add `ai_eval_runs` table contract with run metadata:
  - run type, trigger info, thresholds snapshot, status, timestamps, metadata.
- `[x]` Add `ai_eval_samples` table contract with per-sample outcomes:
  - schema validity, patch apply success, edit-after-generate, publish proxy, safety compliance, fallback usage, latency.
- `[x]` Add `ai_eval_run_summary_v1` view for gate/ops dashboard:
  - `schema_valid_rate`, `patch_apply_success`, `edit_after_generate_rate`, `publish_conversion_proxy`, `safety_html_tailwind_compliance`, `fallback_rate`, `p95_latency_ms`.

Acceptance criteria:
- Each eval run has >= 1 sample and a terminal status (`passed`/`failed`/`aborted`).
- Summary view matches raw sample aggregates within ±0.001.
- Failed gates are queryable by run in a single SQL statement.

## Workstream 3: Eval Script + Release Gates

- `[x]` Extend `EvalRecord` schema with optional routing fields:
  - `fallback_used`, `latency_ms`, `requested_provider`, `selected_provider`, `route_strategy`.
- `[x]` Extend offline eval report with operational metrics:
  - `fallback_rate`, `p95_latency_ms`.
- `[x]` Add max-threshold gates:
  - `fallback_rate_max`, `p95_latency_ms_max`.
- `[x]` Keep existing quality gates unchanged:
  - schema-valid, patch apply, edit-after-generate, publish proxy, safety compliance.
- `[x]` Add/refresh unit tests for mixed quality + operational gate behavior.

Acceptance criteria:
- `scripts/evals/run_offline_eval.py` returns exit code `0` on gate pass and `2` on gate fail.
- Eval report always includes both quality and operational metrics keys.
- CI runs lint + tests green on `main` and PR branches.

## Workstream 4: Rollout and Runbook

- `[x]` Add ADR with rollout policy for provider routing flags.
- `[x]` Define canary guardrails:
  - max fallback rate, max latency, minimum schema-valid rate.
- `[x]` Define rollback trigger matrix:
  - immediate rollback on safety regression or schema-valid drop > 1%.
- `[x]` Define on-call checklist for eval failures.

Acceptance criteria:
- Rollout decision doc includes go/no-go thresholds and explicit rollback SQL/app flags.
- One dry-run canary simulation completed and documented.

## Remaining Execution (Outside This Repo)

- `[~]` Deploy edge-function runtime writes in product repo (`generate-site/index.ts`) for all Phase 2 telemetry fields. (Code ready, deployment pending)
- `[~]` Deploy frontend response metadata wiring in product repo (`aiGeneration.ts` + consumers). (Code ready, deployment pending)
- `[~]` Run generated eval-ingest SQL in Supabase from real eval data (not fixture-only). (Automation/scripts ready, first live run pending)
- `[~]` Wire production scheduler/automation to run eval gate and ingest daily. (Workflow added, secrets/live run pending)
- `[ ]` Complete first rollback drill in live environment and attach run evidence.
