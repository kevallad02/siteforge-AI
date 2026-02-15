# Phase 2 Runtime Integration Spec (Product Repo)

This document defines the remaining runtime integration required in the product app repo.

Target product files (outside this repo):

- `/Users/kevallad/Desktop/Personal/sitecraft/supabase/functions/generate-site/index.ts`
- `/Users/kevallad/Desktop/Personal/sitecraft/src/lib/aiGeneration.ts`

## Required Runtime Writes

For each generation attempt, write these fields to `public.ai_training_examples`:

- `request_id` (UUID, per request)
- `requested_provider` (`openai` or `custom`, nullable if no user preference)
- `selected_provider` (`openai` or `custom`, required)
- `route_strategy` (`single_provider` | `weighted` | `fallback`)
- `fallback_provider` (`openai` or `custom`, nullable)
- `fallback_used` (boolean, required)
- `latency_ms` (integer, nullable if unavailable)
- `prompt_template_version` (text, required)

## Runtime Contract Rules

1. `selected_provider` must always be present on successful generation writes.
2. If `fallback_used=true`, `fallback_provider` must be non-null.
3. `latency_ms` must be `>= 0`.
4. `prompt_template_version` must be non-empty.

## Frontend API Contract

The generation response payload should include:

- `requestId`
- `routeStrategy`
- `promptTemplateVersion`
- `selectedProvider`
- `fallbackUsed`
- `latencyMs`

These should be persisted to site generation metadata in UI state for traceability.

## Verification SQL (after runtime deploy)

```sql
select
  count(*) as total_generations,
  count(*) filter (where selected_provider is not null) as selected_provider_set,
  count(*) filter (where fallback_used = true and fallback_provider is not null) as valid_fallback_rows,
  round(avg(latency_ms) filter (where latency_ms is not null), 2) as avg_latency_ms
from public.ai_training_examples
where source in ('generation', 'generation_cached')
  and created_at >= now() - interval '24 hours';
```

Expected:

- `selected_provider_set = total_generations`
- fallback rows should be internally consistent (`fallback_used -> fallback_provider`)

## Rollout Order

1. DB migration complete.
2. Edge function deploy with runtime writes.
3. Frontend deploy with response metadata wiring.
4. 24h verification query review.
