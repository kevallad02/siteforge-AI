#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SRC_PATH = REPO_ROOT / 'src'
if str(SRC_PATH) not in sys.path:
    sys.path.insert(0, str(SRC_PATH))

from evals.contracts import EvalThresholds  # noqa: E402
from evals.ingest_sql import EvalIngestContext, build_eval_ingest_sql  # noqa: E402
from evals.runner import build_eval_report, load_eval_records  # noqa: E402


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Generate SQL to ingest an eval run into ai_eval_runs/ai_eval_samples.'
    )
    parser.add_argument(
        '--input',
        type=Path,
        default=REPO_ROOT / 'tests/fixtures/eval_records_sample.jsonl',
        help='Path to JSONL eval records.',
    )
    parser.add_argument(
        '--sql-output',
        type=Path,
        default=REPO_ROOT / 'artifacts/evals/eval_run_ingest.sql',
        help='Path to write SQL ingestion script.',
    )
    parser.add_argument(
        '--report-output',
        type=Path,
        default=REPO_ROOT / 'artifacts/evals/eval_run_report.json',
        help='Path to write eval report JSON.',
    )
    parser.add_argument('--run-type', choices=['offline', 'shadow', 'canary'], default='offline')
    parser.add_argument('--triggered-by', default='local-cli')
    parser.add_argument('--commit-sha', default=os.getenv('GITHUB_SHA'))
    parser.add_argument('--dataset-ref', default=None)
    parser.add_argument('--schema-valid-rate', type=float, default=0.99)
    parser.add_argument('--patch-apply-success', type=float, default=0.95)
    parser.add_argument('--edit-after-generate-rate', type=float, default=0.30)
    parser.add_argument('--publish-conversion-proxy', type=float, default=0.15)
    parser.add_argument('--safety-html-tailwind-compliance', type=float, default=0.995)
    parser.add_argument('--fallback-rate-max', type=float, default=0.25)
    parser.add_argument('--p95-latency-ms-max', type=int, default=45000)
    parser.add_argument(
        '--strict-exit',
        action='store_true',
        help='Exit with code 2 when gates fail.',
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    thresholds = EvalThresholds(
        schema_valid_rate=args.schema_valid_rate,
        patch_apply_success=args.patch_apply_success,
        edit_after_generate_rate=args.edit_after_generate_rate,
        publish_conversion_proxy=args.publish_conversion_proxy,
        safety_html_tailwind_compliance=args.safety_html_tailwind_compliance,
        fallback_rate_max=args.fallback_rate_max,
        p95_latency_ms_max=args.p95_latency_ms_max,
    )

    records = load_eval_records(args.input)
    report = build_eval_report(records, thresholds=thresholds)
    context = EvalIngestContext(
        run_type=args.run_type,
        triggered_by=args.triggered_by,
        commit_sha=args.commit_sha,
        dataset_ref=args.dataset_ref or str(args.input),
    )
    sql_text, run_id, status = build_eval_ingest_sql(
        records=records,
        thresholds=thresholds,
        context=context,
        report=report,
    )

    args.sql_output.parent.mkdir(parents=True, exist_ok=True)
    args.sql_output.write_text(sql_text, encoding='utf-8')

    args.report_output.parent.mkdir(parents=True, exist_ok=True)
    with args.report_output.open('w', encoding='utf-8') as handle:
        json.dump(report, handle, indent=2)
        handle.write('\n')

    print(f'Generated eval ingest SQL: {args.sql_output}')
    print(f'Generated eval report JSON: {args.report_output}')
    print(f'run_id={run_id}')
    print(f'status={status}')
    return 2 if args.strict_exit and not report['overall_pass'] else 0


if __name__ == '__main__':
    raise SystemExit(main())
