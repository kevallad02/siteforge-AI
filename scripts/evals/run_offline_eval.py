#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SRC_PATH = REPO_ROOT / 'src'
if str(SRC_PATH) not in sys.path:
    sys.path.insert(0, str(SRC_PATH))

from evals.contracts import EvalRecord, EvalThresholds  # noqa: E402
from evals.runner import build_eval_report, load_eval_records  # noqa: E402


def _fallback_records() -> list[EvalRecord]:
    return [
        EvalRecord(
            record_id='sample-1',
            schema_valid=True,
            patch_apply_success=True,
            edited_after_generate=True,
            published_within_7d=False,
            safety_html_tailwind_compliant=True,
        ),
        EvalRecord(
            record_id='sample-2',
            schema_valid=True,
            patch_apply_success=True,
            edited_after_generate=False,
            published_within_7d=False,
            safety_html_tailwind_compliant=True,
        ),
    ]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description='Run offline evaluation metrics over JSONL records.')
    parser.add_argument(
        '--input',
        type=Path,
        default=REPO_ROOT / 'tests/fixtures/eval_records_sample.jsonl',
        help='Path to JSONL eval records.',
    )
    parser.add_argument(
        '--output',
        type=Path,
        default=REPO_ROOT / 'artifacts/evals/offline_eval_report.json',
        help='Path to write report JSON.',
    )
    parser.add_argument('--schema-valid-rate', type=float, default=0.99)
    parser.add_argument('--patch-apply-success', type=float, default=0.95)
    parser.add_argument('--edit-after-generate-rate', type=float, default=0.30)
    parser.add_argument('--publish-conversion-proxy', type=float, default=0.15)
    parser.add_argument('--safety-html-tailwind-compliance', type=float, default=0.995)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    thresholds = EvalThresholds(
        schema_valid_rate=args.schema_valid_rate,
        patch_apply_success=args.patch_apply_success,
        edit_after_generate_rate=args.edit_after_generate_rate,
        publish_conversion_proxy=args.publish_conversion_proxy,
        safety_html_tailwind_compliance=args.safety_html_tailwind_compliance,
    )

    records = _fallback_records()
    if args.input.exists():
        records = load_eval_records(args.input)

    report = build_eval_report(records, thresholds=thresholds)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('w', encoding='utf-8') as handle:
        json.dump(report, handle, indent=2)
        handle.write('\n')

    print(f'Wrote offline eval report to: {args.output}')
    print(json.dumps(report, indent=2))
    return 0 if report['overall_pass'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
