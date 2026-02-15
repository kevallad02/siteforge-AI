from pathlib import Path

from evals.contracts import EvalThresholds
from evals.runner import build_eval_report, compute_metric_rates, load_eval_records


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
