from pathlib import Path

from evals.contracts import EvalRecord, EvalThresholds
from evals.runner import (
    build_eval_report,
    compute_metric_rates,
    compute_operational_metrics,
    load_eval_records,
)


def test_compute_metric_rates_from_fixture() -> None:
    fixture_path = Path(__file__).resolve().parents[1] / 'fixtures' / 'eval_records_sample.jsonl'
    records = load_eval_records(fixture_path)
    metrics = compute_metric_rates(records)

    assert metrics['schema_valid_rate'] == 0.8
    assert metrics['patch_apply_success'] == 0.6
    assert metrics['edit_after_generate_rate'] == 0.4
    assert metrics['publish_conversion_proxy'] == 0.2
    assert metrics['safety_html_tailwind_compliance'] == 1.0


def test_eval_report_gate_passes_for_custom_thresholds() -> None:
    fixture_path = Path(__file__).resolve().parents[1] / 'fixtures' / 'eval_records_sample.jsonl'
    records = load_eval_records(fixture_path)
    thresholds = EvalThresholds(
        schema_valid_rate=0.8,
        patch_apply_success=0.6,
        edit_after_generate_rate=0.4,
        publish_conversion_proxy=0.2,
        safety_html_tailwind_compliance=1.0,
    )

    report = build_eval_report(records, thresholds=thresholds)
    assert report['overall_pass'] is True


def test_operational_metrics_and_threshold_gates() -> None:
    records = [
        EvalRecord(
            record_id='op-1',
            schema_valid=True,
            patch_apply_success=True,
            edited_after_generate=False,
            published_within_7d=False,
            safety_html_tailwind_compliant=True,
            fallback_used=False,
            latency_ms=1500,
            selected_provider='openai',
        ),
        EvalRecord(
            record_id='op-2',
            schema_valid=True,
            patch_apply_success=True,
            edited_after_generate=False,
            published_within_7d=False,
            safety_html_tailwind_compliant=True,
            fallback_used=True,
            latency_ms=2400,
            selected_provider='custom',
        ),
        EvalRecord(
            record_id='op-3',
            schema_valid=True,
            patch_apply_success=True,
            edited_after_generate=False,
            published_within_7d=False,
            safety_html_tailwind_compliant=True,
            fallback_used=False,
            latency_ms=3000,
            selected_provider='openai',
        ),
    ]

    operational_metrics = compute_operational_metrics(records)
    assert operational_metrics['fallback_rate'] == 0.3333
    assert operational_metrics['p95_latency_ms'] == 3000

    thresholds = EvalThresholds(
        schema_valid_rate=1.0,
        patch_apply_success=1.0,
        edit_after_generate_rate=0.0,
        publish_conversion_proxy=0.0,
        safety_html_tailwind_compliance=1.0,
        fallback_rate_max=0.34,
        p95_latency_ms_max=3500,
    )

    report = build_eval_report(records, thresholds=thresholds)
    assert report['gates']['fallback_rate_max'] is True
    assert report['gates']['p95_latency_ms_max'] is True
    assert report['overall_pass'] is True
