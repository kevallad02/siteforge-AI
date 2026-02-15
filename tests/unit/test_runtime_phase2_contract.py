from data_contracts.runtime_phase2 import (
    RuntimeGenerationTelemetry,
    validate_runtime_generation_telemetry,
)


def test_validate_runtime_generation_telemetry_passes() -> None:
    telemetry = RuntimeGenerationTelemetry(
        request_id='cb3a5e65-f665-4ed8-9d96-e60359ff3be1',
        requested_provider='openai',
        selected_provider='custom',
        route_strategy='fallback',
        fallback_provider='custom',
        fallback_used=True,
        latency_ms=3200,
        prompt_template_version='v1',
    )
    assert validate_runtime_generation_telemetry(telemetry) == []


def test_validate_runtime_generation_telemetry_rejects_invalid_values() -> None:
    telemetry = RuntimeGenerationTelemetry(
        request_id=None,
        requested_provider='invalid',
        selected_provider='invalid',
        route_strategy='not_a_strategy',
        fallback_provider=None,
        fallback_used=True,
        latency_ms=-1,
        prompt_template_version='',
    )
    errors = validate_runtime_generation_telemetry(telemetry)
    assert len(errors) == 6
