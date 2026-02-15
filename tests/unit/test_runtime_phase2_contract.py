from data_contracts.runtime_phase2 import (
    RuntimeGenerationTelemetry,
    validate_runtime_generation_telemetry,
)


def test_validate_runtime_generation_telemetry_passes() -> None:
    telemetry = RuntimeGenerationTelemetry(
        request_id='cb3a5e65-f665-4ed8-9d96-e60359ff3be1',
        tenant_id='23d83f8d-a4e2-4de1-8953-f19088480a9d',
        requested_provider='openai',
        selected_provider='custom',
        route_strategy='fallback',
        fallback_provider='custom',
        fallback_used=True,
        latency_ms=3200,
        prompt_template_version='v1',
        route_id='3c2dc17e-31d2-44fd-81bc-cbb9154a9f73',
        model_id='ca7ebd18-b894-4254-a8f9-2db3fd94938d',
        model_version_id='4d5672bb-3c84-45ab-a97a-695b369eff3f',
    )
    assert validate_runtime_generation_telemetry(telemetry) == []


def test_validate_runtime_generation_telemetry_rejects_invalid_values() -> None:
    telemetry = RuntimeGenerationTelemetry(
        request_id='not-a-uuid',
        tenant_id='bad-tenant',
        requested_provider='invalid',
        selected_provider='invalid',
        route_strategy='not_a_strategy',
        fallback_provider=None,
        fallback_used=True,
        latency_ms=-1,
        prompt_template_version='',
        route_id='bad-route-id',
        model_id='bad-model-id',
        model_version_id='bad-model-version-id',
    )
    errors = validate_runtime_generation_telemetry(telemetry)
    assert len(errors) == 11
