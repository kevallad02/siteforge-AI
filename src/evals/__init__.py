"""Evaluation package for offline/online quality checks."""

from .contracts import EvalRecord, EvalThresholds
from .runner import build_eval_report, compute_metric_rates, load_eval_records

__all__ = [
    'EvalRecord',
    'EvalThresholds',
    'build_eval_report',
    'compute_metric_rates',
    'load_eval_records',
]
