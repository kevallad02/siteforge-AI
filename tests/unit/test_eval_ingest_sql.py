from evals.contracts import EvalRecord, EvalThresholds
from evals.ingest_sql import EvalIngestContext, build_eval_ingest_sql


def test_build_eval_ingest_sql_generates_expected_statements() -> None:
    records = [
        EvalRecord(
            record_id='rec-1',
            schema_valid=True,
            patch_apply_success=True,
            edited_after_generate=True,
            published_within_7d=False,
            safety_html_tailwind_compliant=True,
            fallback_used=False,
            latency_ms=1200,
            requested_provider='openai',
            selected_provider='openai',
            route_strategy='single_provider',
            request_id='36f7ebca-5661-4c0f-b215-175f9627b99e',
        ),
        EvalRecord(
            record_id='rec-2',
            schema_valid=True,
            patch_apply_success=True,
            edited_after_generate=False,
            published_within_7d=False,
            safety_html_tailwind_compliant=True,
            fallback_used=True,
            latency_ms=1800,
            requested_provider='openai',
            selected_provider='custom',
            route_strategy='fallback',
            request_id='not-a-uuid',
        ),
    ]

    sql_text, run_id, status = build_eval_ingest_sql(
        records=records,
        thresholds=EvalThresholds(
            schema_valid_rate=0.9,
            patch_apply_success=0.9,
            edit_after_generate_rate=0.4,
            publish_conversion_proxy=0.0,
            safety_html_tailwind_compliance=1.0,
            fallback_rate_max=0.6,
            p95_latency_ms_max=3000,
        ),
        context=EvalIngestContext(
            run_type='offline',
            triggered_by='pytest',
            commit_sha='deadbeef',
            dataset_ref='tests/fixtures/custom.jsonl',
        ),
        run_id='2e315354-3b92-4c70-9c69-2c45f97f3363',
    )

    assert run_id == '2e315354-3b92-4c70-9c69-2c45f97f3363'
    assert status == 'passed'
    assert 'INSERT INTO public.ai_eval_runs' in sql_text
    assert 'id, run_type, status, dataset_ref' in sql_text
    assert 'INSERT INTO public.ai_eval_samples' in sql_text
    assert 'sample_key' in sql_text
    assert "'not-a-uuid'" not in sql_text
    assert 'invalidRequestId' in sql_text
