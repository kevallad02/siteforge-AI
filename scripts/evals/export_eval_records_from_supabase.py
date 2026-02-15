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

from evals.supabase_export import (  # noqa: E402
    compute_since_iso,
    fetch_training_example_rows,
    row_to_eval_record_payload,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description='Export recent ai_training_examples rows from Supabase as eval JSONL records.'
    )
    parser.add_argument('--supabase-url', default=os.getenv('SUPABASE_URL'))
    parser.add_argument('--service-role-key', default=os.getenv('SUPABASE_SERVICE_ROLE_KEY'))
    parser.add_argument('--days', type=int, default=1)
    parser.add_argument('--limit', type=int, default=2000)
    parser.add_argument(
        '--source',
        action='append',
        dest='sources',
        default=[],
        help='Repeat to provide multiple source filters (default: generation,generation_cached).',
    )
    parser.add_argument(
        '--output',
        type=Path,
        default=REPO_ROOT / 'artifacts/evals/recent_eval_records.jsonl',
    )
    parser.add_argument(
        '--fail-on-empty',
        action='store_true',
        help='Exit with code 2 when no records are exported.',
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.supabase_url or not args.service_role_key:
        print('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.', file=sys.stderr)
        return 1

    sources = args.sources if args.sources else ['generation', 'generation_cached']
    since_iso = compute_since_iso(args.days)
    rows = fetch_training_example_rows(
        supabase_url=args.supabase_url,
        service_role_key=args.service_role_key,
        since_iso=since_iso,
        limit=args.limit,
        sources=sources,
    )

    payloads = [row_to_eval_record_payload(row) for row in rows]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open('w', encoding='utf-8') as handle:
        for payload in payloads:
            handle.write(json.dumps(payload, separators=(',', ':')))
            handle.write('\n')

    print(f'Exported {len(payloads)} eval records to: {args.output}')
    return 2 if args.fail_on_empty and not payloads else 0


if __name__ == '__main__':
    raise SystemExit(main())
