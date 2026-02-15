"""Data contract package scaffolds."""

from .runtime_phase2 import (
    RuntimeGenerationTelemetry,
    validate_runtime_generation_telemetry,
)

__all__ = [
    'RuntimeGenerationTelemetry',
    'validate_runtime_generation_telemetry',
]
