# Phase 2 Supabase Rollout Runbook (Staging -> Prod)

## Scope

Roll out Phase 2 DB contracts for provider routing and evaluation safely across Supabase staging and production.

If you use a single Supabase database for both staging/prod traffic, use the **Single-DB Rollout** path below and skip the separate staging/prod sections.

## Assumptions

- `public.ai_training_examples` already exists from Phase 1.
- You are applying SQL in each Supabase project separately (staging project first, then prod).
- The following files are the rollout source of truth:
  - Base migration:
    - `supabase/migrations/20260215205000_phase2_provider_routing_and_eval.sql`
  - Environment overlays:
    - `db/migrations/releases/phase2/20260215205100_phase2_provider_config_staging.sql`
    - `db/migrations/releases/phase2/20260215205200_phase2_provider_config_prod.sql`
    - `db/migrations/releases/phase2/20260215205300_phase2_provider_config_single_db.sql`

## Release Gates

- Schema migration executes with no errors.
- `ai_provider_configs` has exactly one default provider per environment.
- `ai_eval_runs`, `ai_eval_samples`, and `ai_eval_run_summary_v1` exist.
- P0 rollback SQL tested in staging before prod rollout.

## 0) Single-DB Rollout (Your setup)

Use this when one database serves both non-prod and prod usage.

### 0.1 Apply base migration (SQL Editor)

Run full SQL from:
- `supabase/migrations/20260215205000_phase2_provider_routing_and_eval.sql`

### 0.2 Apply single-db provider overlay (SQL Editor)

Run full SQL from:
- `db/migrations/releases/phase2/20260215205300_phase2_provider_config_single_db.sql`

### 0.3 Verify single-db state

```sql
select provider, environment, enabled, is_default, weight, timeout_ms, max_retries
from public.ai_provider_configs
order by environment, provider;
```

```sql
select
  count(*) filter (where environment = 'prod' and is_default = true) as prod_default_count,
  count(*) filter (where environment <> 'prod' and enabled = true) as non_prod_enabled_count
from public.ai_provider_configs;
```

Expected:
- `prod_default_count = 1`
- `non_prod_enabled_count = 0`

```sql
select
  to_regclass('public.ai_eval_runs') as ai_eval_runs,
  to_regclass('public.ai_eval_samples') as ai_eval_samples,
  to_regclass('public.ai_eval_run_summary_v1') as ai_eval_run_summary_v1;
```

## 1) Staging Rollout

### 1.1 Preflight checks (SQL Editor, staging)

```sql
select
  table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in (
    'ai_training_examples',
    'ai_provider_configs',
    'ai_eval_runs',
    'ai_eval_samples'
  )
order by table_name;
```

```sql
select
  table_name,
  column_name,
  data_type
from information_schema.columns
where table_schema = 'public'
  and table_name in ('ai_training_examples', 'ai_provider_configs', 'ai_eval_samples')
order by table_name, ordinal_position;
```

### 1.2 Apply base migration (SQL Editor, staging)

Run full SQL from:
- `supabase/migrations/20260215205000_phase2_provider_routing_and_eval.sql`

### 1.3 Apply staging overlay (SQL Editor, staging)

Run full SQL from:
- `db/migrations/releases/phase2/20260215205100_phase2_provider_config_staging.sql`

### 1.4 Verify staging state (SQL Editor, staging)

```sql
select provider, environment, enabled, is_default, weight, timeout_ms, max_retries
from public.ai_provider_configs
where environment in ('staging', 'prod')
order by environment, provider;
```

```sql
select
  count(*) as default_count
from public.ai_provider_configs
where environment = 'staging'
  and is_default = true;
```

```sql
select
  to_regclass('public.ai_eval_runs') as ai_eval_runs,
  to_regclass('public.ai_eval_samples') as ai_eval_samples,
  to_regclass('public.ai_eval_run_summary_v1') as ai_eval_run_summary_v1;
```

```sql
select
  indexname
from pg_indexes
where schemaname = 'public'
  and tablename in ('ai_training_examples', 'ai_provider_configs', 'ai_eval_samples')
order by tablename, indexname;
```

### 1.5 Staging soak acceptance (24h)

- No SQL errors in write paths touching `ai_training_examples`.
- New generation records contain:
  - `selected_provider`
  - `route_strategy`
  - `prompt_template_version`
- No constraint violations from Phase 2 columns/checks.

## 2) Production Rollout

Run only after staging soak passes.

### 2.1 Preflight checks (SQL Editor, prod)

Run the same preflight queries from section `1.1`.

### 2.2 Apply base migration (SQL Editor, prod)

Run full SQL from:
- `supabase/migrations/20260215205000_phase2_provider_routing_and_eval.sql`

### 2.3 Apply prod overlay (SQL Editor, prod)

Run full SQL from:
- `db/migrations/releases/phase2/20260215205200_phase2_provider_config_prod.sql`

### 2.4 Verify prod state (SQL Editor, prod)

Run the same verification queries from section `1.4`, replacing `staging` checks with `prod` where applicable.

## 3) P0 Rollback (SQL-only)

Use this if schema-valid, safety, or publish proxy regresses unexpectedly.

```sql
begin;

update public.ai_provider_configs
set
  enabled = case when provider = 'openai' then true else false end,
  is_default = case when provider = 'openai' then true else false end,
  weight = case when provider = 'openai' then 100 else 0 end,
  updated_at = timezone('utc', now())
where environment in ('staging', 'prod');

commit;
```

Post-rollback verification:

```sql
select provider, environment, enabled, is_default, weight
from public.ai_provider_configs
where environment in ('staging', 'prod')
order by environment, provider;
```

## 4) Post-rollout Logging

Capture and commit:

- rollout timestamp
- operator
- staging start/end
- prod start/end
- verification query outputs
- rollback test result (staging)

Store notes in your release log/ADR so run history is auditable.

## 5) Daily Eval Ingestion (Single DB)

After runtime deploy, run this daily automation path:

1. Export recent real records from Supabase:

```bash
./.venv/bin/python scripts/evals/export_eval_records_from_supabase.py \
  --days 1 \
  --limit 5000 \
  --output artifacts/evals/recent_eval_records.jsonl
```

2. Generate eval report + SQL ingest script:

```bash
./.venv/bin/python scripts/evals/generate_eval_ingest_sql.py \
  --input artifacts/evals/recent_eval_records.jsonl \
  --sql-output artifacts/evals/eval_run_ingest.sql \
  --report-output artifacts/evals/eval_run_report.json \
  --run-type canary \
  --schema-variant sitecraft \
  --triggered-by manual
```

3. Execute generated SQL in Supabase SQL Editor:

- `artifacts/evals/eval_run_ingest.sql`

4. Verify run summary:

```sql
select *
from public.ai_eval_run_summary_v1
order by run_id desc
limit 5;
```

Nightly GitHub automation:

- `.github/workflows/nightly-eval.yml`
- Required repo secrets:
  - `SUPABASE_URL`
  - `SUPABASE_SERVICE_ROLE_KEY`
- Default gating behavior:
  - If nightly sample count is below `30`, workflow uploads artifacts but skips hard fail gating.
