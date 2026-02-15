from __future__ import annotations

from dataclasses import dataclass
from uuid import UUID

ALLOWED_PROVIDERS = {'openai', 'custom'}
ALLOWED_ROUTE_STRATEGIES = {'single_provider', 'weighted', 'fallback'}


@dataclass(frozen=True, slots=True)
class RuntimeGenerationTelemetry:
    request_id: str | None
    tenant_id: str
    requested_provider: str | None
    selected_provider: str
    route_strategy: str
    fallback_provider: str | None
    fallback_used: bool
    latency_ms: int | None
    prompt_template_version: str
    route_id: str | None = None
    model_id: str | None = None
    model_version_id: str | None = None


def _is_valid_uuid(value: str | None) -> bool:
    if value is None:
        return True
    try:
        UUID(value)
    except (TypeError, ValueError):
        return False
    return True


def validate_runtime_generation_telemetry(
    telemetry: RuntimeGenerationTelemetry,
) -> list[str]:
    errors: list[str] = []

    if not _is_valid_uuid(telemetry.request_id):
        errors.append('request_id must be a valid UUID when provided')

    if not telemetry.tenant_id:
        errors.append('tenant_id is required')
    elif not _is_valid_uuid(telemetry.tenant_id):
        errors.append('tenant_id must be a valid UUID')

    if telemetry.selected_provider not in ALLOWED_PROVIDERS:
        errors.append(f'selected_provider must be one of {sorted(ALLOWED_PROVIDERS)}')

    if telemetry.requested_provider and telemetry.requested_provider not in ALLOWED_PROVIDERS:
        errors.append(
            f'requested_provider must be one of {sorted(ALLOWED_PROVIDERS)} when provided'
        )

    if telemetry.fallback_provider and telemetry.fallback_provider not in ALLOWED_PROVIDERS:
        errors.append(f'fallback_provider must be one of {sorted(ALLOWED_PROVIDERS)} when provided')

    if telemetry.route_strategy not in ALLOWED_ROUTE_STRATEGIES:
        errors.append(f'route_strategy must be one of {sorted(ALLOWED_ROUTE_STRATEGIES)}')

    if telemetry.fallback_used and not telemetry.fallback_provider:
        errors.append('fallback_provider is required when fallback_used=true')

    if telemetry.latency_ms is not None and telemetry.latency_ms < 0:
        errors.append('latency_ms must be >= 0 when provided')

    if not telemetry.prompt_template_version:
        errors.append('prompt_template_version is required')

    if not _is_valid_uuid(telemetry.route_id):
        errors.append('route_id must be a valid UUID when provided')

    if not _is_valid_uuid(telemetry.model_id):
        errors.append('model_id must be a valid UUID when provided')

    if not _is_valid_uuid(telemetry.model_version_id):
        errors.append('model_version_id must be a valid UUID when provided')

    return errors
