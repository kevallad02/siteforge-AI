from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True, slots=True)
class EvalRecord:
    """Single evaluation sample with normalized binary outcomes."""

    record_id: str
    schema_valid: bool
    patch_apply_success: bool
    edited_after_generate: bool
    published_within_7d: bool
    safety_html_tailwind_compliant: bool

    @staticmethod
    def from_dict(payload: dict[str, Any]) -> 'EvalRecord':
        return EvalRecord(
            record_id=str(payload.get('record_id') or payload.get('id') or 'unknown'),
            schema_valid=bool(payload.get('schema_valid')),
            patch_apply_success=bool(payload.get('patch_apply_success')),
            edited_after_generate=bool(payload.get('edited_after_generate')),
            published_within_7d=bool(payload.get('published_within_7d')),
            safety_html_tailwind_compliant=bool(payload.get('safety_html_tailwind_compliant')),
        )


@dataclass(frozen=True, slots=True)
class EvalThresholds:
    """Release gates for quality metrics."""

    schema_valid_rate: float = 0.99
    patch_apply_success: float = 0.95
    edit_after_generate_rate: float = 0.30
    publish_conversion_proxy: float = 0.15
    safety_html_tailwind_compliance: float = 0.995

    def as_dict(self) -> dict[str, float]:
        return {
            'schema_valid_rate': self.schema_valid_rate,
            'patch_apply_success': self.patch_apply_success,
            'edit_after_generate_rate': self.edit_after_generate_rate,
            'publish_conversion_proxy': self.publish_conversion_proxy,
            'safety_html_tailwind_compliance': self.safety_html_tailwind_compliance,
        }
