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
    fallback_used: bool = False
    latency_ms: int | None = None
    requested_provider: str | None = None
    selected_provider: str | None = None
    route_strategy: str | None = None
    request_id: str | None = None
    tenant_id: str | None = None
    route_id: str | None = None
    model_id: str | None = None
    model_version_id: str | None = None

    @staticmethod
    def from_dict(payload: dict[str, Any]) -> EvalRecord:
        return EvalRecord(
            record_id=str(payload.get('record_id') or payload.get('id') or 'unknown'),
            schema_valid=bool(payload.get('schema_valid')),
            patch_apply_success=bool(payload.get('patch_apply_success')),
            edited_after_generate=bool(payload.get('edited_after_generate')),
            published_within_7d=bool(payload.get('published_within_7d')),
            safety_html_tailwind_compliant=bool(payload.get('safety_html_tailwind_compliant')),
            fallback_used=bool(payload.get('fallback_used', False)),
            latency_ms=(
                int(payload['latency_ms']) if payload.get('latency_ms') is not None else None
            ),
            requested_provider=(
                str(payload.get('requested_provider'))
                if payload.get('requested_provider') is not None
                else None
            ),
            selected_provider=(
                str(payload.get('selected_provider'))
                if payload.get('selected_provider') is not None
                else None
            ),
            route_strategy=(
                str(payload.get('route_strategy'))
                if payload.get('route_strategy') is not None
                else None
            ),
            request_id=(
                str(payload.get('request_id')) if payload.get('request_id') is not None else None
            ),
            tenant_id=(
                str(payload.get('tenant_id')) if payload.get('tenant_id') is not None else None
            ),
            route_id=(
                str(payload.get('route_id')) if payload.get('route_id') is not None else None
            ),
            model_id=(
                str(payload.get('model_id')) if payload.get('model_id') is not None else None
            ),
            model_version_id=(
                str(payload.get('model_version_id'))
                if payload.get('model_version_id') is not None
                else None
            ),
        )


@dataclass(frozen=True, slots=True)
class EvalThresholds:
    """Release gates for quality metrics."""

    schema_valid_rate: float = 0.99
    patch_apply_success: float = 0.95
    edit_after_generate_rate: float = 0.30
    publish_conversion_proxy: float = 0.15
    safety_html_tailwind_compliance: float = 0.995
    fallback_rate_max: float = 0.25
    p95_latency_ms_max: int = 45000

    def as_dict(self) -> dict[str, float | int]:
        return {
            'schema_valid_rate': self.schema_valid_rate,
            'patch_apply_success': self.patch_apply_success,
            'edit_after_generate_rate': self.edit_after_generate_rate,
            'publish_conversion_proxy': self.publish_conversion_proxy,
            'safety_html_tailwind_compliance': self.safety_html_tailwind_compliance,
            'fallback_rate_max': self.fallback_rate_max,
            'p95_latency_ms_max': self.p95_latency_ms_max,
        }
