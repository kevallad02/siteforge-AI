# Phase 2 Canary + On-call Playbook

## Canary Guardrails

Monitor over rolling 30-minute windows:

- `schema_valid_rate >= 0.99`
- `safety_html_tailwind_compliance >= 0.995`
- `patch_apply_success >= 0.95`
- `fallback_rate <= 0.25`
- `p95_latency_ms <= 45000`

If any guardrail breaches for 2 consecutive windows, trigger rollback.

## Rollback Matrix

1. Safety regression (`safety_html_tailwind_compliance < 0.99`):
   - immediate rollback to `openai` only.
2. Schema regression (`schema_valid_rate < 0.98`):
   - immediate rollback to `openai` only.
3. Latency regression (`p95_latency_ms > 60000`):
   - disable `custom` provider or set weight to `0`.
4. Elevated fallback (`fallback_rate > 0.40`):
   - reduce `custom` weight; investigate provider errors.

## On-call Checklist

1. Confirm incident severity and metric deltas from baseline.
2. Run provider config inspection SQL:

```sql
select provider, environment, enabled, is_default, weight, timeout_ms, max_retries
from public.ai_provider_configs
order by environment, provider;
```

3. Run last-60m telemetry check:

```sql
select
  count(*) as total_rows,
  avg(case when fallback_used then 1.0 else 0.0 end) as fallback_rate,
  percentile_cont(0.95) within group (order by latency_ms) as p95_latency_ms,
  avg(case when coalesce((metadata->>'schemaValid')::boolean, true) then 1.0 else 0.0 end) as schema_valid_rate
from public.ai_training_examples
where created_at >= now() - interval '60 minutes'
  and source in ('generation', 'generation_cached');
```

4. If guardrails breached, execute rollback SQL (config-only):

```sql
begin;
update public.ai_provider_configs
set
  enabled = case when provider = 'openai' then true else false end,
  is_default = case when provider = 'openai' then true else false end,
  weight = case when provider = 'openai' then 100 else 0 end,
  updated_at = timezone('utc', now())
where environment = 'prod';
commit;
```

5. Validate post-rollback state:

```sql
select provider, environment, enabled, is_default, weight
from public.ai_provider_configs
where environment = 'prod'
order by provider;
```

6. Record incident timeline, root cause hypothesis, and follow-up actions.
