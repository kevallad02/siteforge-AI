from evals.supabase_export import (
    build_eval_export_url,
    row_to_eval_record_payload,
)


def test_build_eval_export_url_contains_filters() -> None:
    url = build_eval_export_url(
        supabase_url='https://xyzcompany.supabase.co',
        since_iso='2026-02-14T00:00:00+00:00',
        limit=123,
        sources=['generation', 'generation_cached'],
    )
    assert url.startswith('https://xyzcompany.supabase.co/rest/v1/ai_training_examples?')
    assert 'source=in.(generation,generation_cached)' in url
    assert 'limit=123' in url
    assert 'created_at=gte.2026-02-14T00:00:00%2B00:00' in url


def test_row_to_eval_record_payload_uses_metadata_fallbacks() -> None:
    payload = row_to_eval_record_payload(
        {
            'id': 'example-id',
            'request_id': 'abc',
            'requested_provider': 'openai',
            'selected_provider': 'custom',
            'route_strategy': 'fallback',
            'fallback_used': None,
            'latency_ms': None,
            'metadata': {
                'schemaValid': True,
                'patchApplySuccess': False,
                'editedAfterGenerate': True,
                'publishedWithin7d': False,
                'safetyHtmlTailwindCompliant': True,
                'fallbackUsed': True,
                'latencyMs': 2100,
            },
        }
    )

    assert payload['record_id'] == 'example-id'
    assert payload['request_id'] == 'abc'
    assert payload['fallback_used'] is True
    assert payload['latency_ms'] == 2100
    assert payload['patch_apply_success'] is False
