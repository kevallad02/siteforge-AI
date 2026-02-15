from __future__ import annotations

import json
import math
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


def _p95(values: list[int]) -> int | None:
    if not values:
        return None
    ordered = sorted(values)
    rank = math.ceil(0.95 * len(ordered)) - 1
    rank = max(0, min(rank, len(ordered) - 1))
    return ordered[rank]


def compute_operational_metrics(records: list[EvalRecord]) -> dict[str, float | int | None]:
    latency_samples = [record.latency_ms for record in records if record.latency_ms is not None]
    return {
        'fallback_rate': _rate([record.fallback_used for record in records]),
        'p95_latency_ms': _p95([value for value in latency_samples if value >= 0]),
    }


def _gate_quality_metrics(metrics: dict[str, float], thresholds: EvalThresholds) -> dict[str, bool]:
    return {
        'schema_valid_rate': metrics['schema_valid_rate'] >= thresholds.schema_valid_rate,
        'patch_apply_success': metrics['patch_apply_success'] >= thresholds.patch_apply_success,
        'edit_after_generate_rate': (
            metrics['edit_after_generate_rate'] >= thresholds.edit_after_generate_rate
        ),
        'publish_conversion_proxy': (
            metrics['publish_conversion_proxy'] >= thresholds.publish_conversion_proxy
        ),
        'safety_html_tailwind_compliance': (
            metrics['safety_html_tailwind_compliance'] >= thresholds.safety_html_tailwind_compliance
        ),
    }


def _gate_operational_metrics(
    metrics: dict[str, float | int | None], thresholds: EvalThresholds
) -> dict[str, bool]:
    p95_latency_ms = metrics['p95_latency_ms']
    latency_gate = (
        True if p95_latency_ms is None else int(p95_latency_ms) <= thresholds.p95_latency_ms_max
    )
    return {
        'fallback_rate_max': float(metrics['fallback_rate']) <= thresholds.fallback_rate_max,
        'p95_latency_ms_max': latency_gate,
    }


def build_eval_report(
    records: list[EvalRecord], thresholds: EvalThresholds | None = None
) -> dict[str, Any]:
    effective_thresholds = thresholds or EvalThresholds()
    quality_metrics = compute_metric_rates(records)
    operational_metrics = compute_operational_metrics(records)
    metrics = {**quality_metrics, **operational_metrics}
    quality_gates = _gate_quality_metrics(quality_metrics, effective_thresholds)
    operational_gates = _gate_operational_metrics(operational_metrics, effective_thresholds)
    gates = {**quality_gates, **operational_gates}
    return {
        'generated_at': datetime.now(UTC).isoformat(),
        'record_count': len(records),
        'metrics': metrics,
        'thresholds': effective_thresholds.as_dict(),
        'gates': gates,
        'overall_pass': all(gates.values()),
    }
