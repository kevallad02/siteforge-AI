from __future__ import annotations

import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from .contracts import EvalRecord, EvalThresholds


def load_eval_records(path: Path) -> list[EvalRecord]:
    if not path.exists():
        raise FileNotFoundError(f'Input file not found: {path}')

    records: list[EvalRecord] = []
    with path.open('r', encoding='utf-8') as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            line = raw_line.strip()
            if not line:
                continue
            try:
                payload = json.loads(line)
            except json.JSONDecodeError as error:
                raise ValueError(f'Invalid JSONL at line {line_number} in {path}') from error
            if not isinstance(payload, dict):
                raise ValueError(
                    f'Each JSONL line must be an object (line {line_number} in {path})'
                )
            records.append(EvalRecord.from_dict(payload))
    return records


def _rate(values: list[bool]) -> float:
    if not values:
        return 0.0
    return round(sum(1 for value in values if value) / len(values), 4)


def compute_metric_rates(records: list[EvalRecord]) -> dict[str, float]:
    return {
        'schema_valid_rate': _rate([record.schema_valid for record in records]),
        'patch_apply_success': _rate([record.patch_apply_success for record in records]),
        'edit_after_generate_rate': _rate([record.edited_after_generate for record in records]),
        'publish_conversion_proxy': _rate([record.published_within_7d for record in records]),
        'safety_html_tailwind_compliance': _rate(
            [record.safety_html_tailwind_compliant for record in records]
        ),
    }


def _gate_metrics(metrics: dict[str, float], thresholds: EvalThresholds) -> dict[str, bool]:
    threshold_map = thresholds.as_dict()
    return {name: metrics[name] >= limit for name, limit in threshold_map.items()}


def build_eval_report(
    records: list[EvalRecord], thresholds: EvalThresholds | None = None
) -> dict[str, Any]:
    effective_thresholds = thresholds or EvalThresholds()
    metrics = compute_metric_rates(records)
    gates = _gate_metrics(metrics, effective_thresholds)
    return {
        'generated_at': datetime.now(UTC).isoformat(),
        'record_count': len(records),
        'metrics': metrics,
        'thresholds': effective_thresholds.as_dict(),
        'gates': gates,
        'overall_pass': all(gates.values()),
    }
