# ADR 0001: Phase 2 Provider Routing and Eval Gates

- Date: 2026-02-15
- Status: Accepted

## Context

Phase 2 requires:

- provider-routing controls in DB (`ai_provider_configs`)
- run/sample-level evaluation persistence (`ai_eval_runs`, `ai_eval_samples`)
- release gates for both quality and operational risk
- safe single-db rollout behavior

The product currently supports providers `openai` and `custom`, with `custom` as low-traffic fallback.

## Decision

1. Provider routing config is persisted in `public.ai_provider_configs` with one default per environment.
2. Runtime generation telemetry is written to `public.ai_training_examples`:
   - `request_id`, `requested_provider`, `selected_provider`, `route_strategy`
   - `fallback_provider`, `fallback_used`, `latency_ms`, `prompt_template_version`
3. Eval runs are persisted with:
   - one row in `public.ai_eval_runs` per run
   - one row in `public.ai_eval_samples` per evaluated sample
4. Release gates include:
   - `schema_valid_rate >= 0.99`
   - `patch_apply_success >= 0.95`
   - `edit_after_generate_rate >= 0.30`
   - `publish_conversion_proxy >= 0.15`
   - `safety_html_tailwind_compliance >= 0.995`
   - `fallback_rate <= 0.25`
   - `p95_latency_ms <= 45000`
5. Single-DB setup uses only `environment='prod'` as active routing scope.

## Consequences

Positive:

- Routing decisions become auditable.
- Release decisions are tied to explicit measurable gates.
- Eval ingestion can be automated from JSONL records.

Tradeoffs:

- More write-time metadata fields increase schema complexity.
- Gate thresholds may require periodic recalibration as traffic changes.

## Rollback Policy

Primary rollback is configuration-only:

- set `openai` enabled/default/weight=100
- set all non-`openai` weights to 0 or disabled

Schema rollback is not required for incident mitigation.
