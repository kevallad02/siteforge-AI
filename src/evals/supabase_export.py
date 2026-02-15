from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta
from typing import Any
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def _to_bool(value: Any, default: bool) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {'true', '1', 'yes'}:
            return True
        if normalized in {'false', '0', 'no'}:
            return False
    return default


def _to_int(value: Any) -> int | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str):
        stripped = value.strip()
        if not stripped:
            return None
        try:
            return int(float(stripped))
        except ValueError:
            return None
    return None


def build_eval_export_url(
    supabase_url: str,
    since_iso: str,
    limit: int,
    sources: list[str] | None = None,
) -> str:
    source_values = sources or ['generation', 'generation_cached']
    query = urlencode(
        {
            'select': (
                'id,request_id,requested_provider,selected_provider,route_strategy,'
                'fallback_used,latency_ms,metadata,created_at,source'
            ),
            'source': f'in.({",".join(source_values)})',
            'created_at': f'gte.{since_iso}',
            'order': 'created_at.desc',
            'limit': str(limit),
        },
        safe='(),.:',
    )
    return f'{supabase_url.rstrip("/")}/rest/v1/ai_training_examples?{query}'


def fetch_training_example_rows(
    supabase_url: str,
    service_role_key: str,
    since_iso: str,
    limit: int = 1000,
    sources: list[str] | None = None,
) -> list[dict[str, Any]]:
    url = build_eval_export_url(
        supabase_url=supabase_url,
        since_iso=since_iso,
        limit=limit,
        sources=sources,
    )
    request = Request(
        url=url,
        headers={
            'apikey': service_role_key,
            'Authorization': f'Bearer {service_role_key}',
            'Accept': 'application/json',
        },
        method='GET',
    )
    with urlopen(request, timeout=30) as response:  # noqa: S310
        payload = response.read().decode('utf-8')
    parsed = json.loads(payload)
    if not isinstance(parsed, list):
        raise ValueError('Expected list response from Supabase REST API')
    return [row for row in parsed if isinstance(row, dict)]


def row_to_eval_record_payload(row: dict[str, Any]) -> dict[str, Any]:
    metadata = row.get('metadata') if isinstance(row.get('metadata'), dict) else {}
    request_id = row.get('request_id')
    record_id = row.get('id') or request_id or 'unknown'

    schema_valid = _to_bool(metadata.get('schemaValid'), True)
    patch_apply_success = _to_bool(metadata.get('patchApplySuccess'), True)
    edited_after_generate = _to_bool(metadata.get('editedAfterGenerate'), False)
    published_within_7d = _to_bool(metadata.get('publishedWithin7d'), False)
    safety_html_tailwind_compliant = _to_bool(metadata.get('safetyHtmlTailwindCompliant'), True)
    fallback_used = _to_bool(
        row.get('fallback_used'),
        _to_bool(metadata.get('fallbackUsed'), False),
    )
    latency_ms = _to_int(row.get('latency_ms'))
    if latency_ms is None:
        latency_ms = _to_int(metadata.get('latencyMs'))

    return {
        'record_id': str(record_id),
        'request_id': str(request_id) if request_id is not None else None,
        'schema_valid': schema_valid,
        'patch_apply_success': patch_apply_success,
        'edited_after_generate': edited_after_generate,
        'published_within_7d': published_within_7d,
        'safety_html_tailwind_compliant': safety_html_tailwind_compliant,
        'fallback_used': fallback_used,
        'latency_ms': latency_ms,
        'requested_provider': row.get('requested_provider'),
        'selected_provider': row.get('selected_provider'),
        'route_strategy': row.get('route_strategy'),
        'tenant_id': row.get('tenant_id') or metadata.get('tenantId'),
        'route_id': row.get('route_id') or metadata.get('routeId'),
        'model_id': row.get('model_id') or metadata.get('modelId'),
        'model_version_id': row.get('model_version_id') or metadata.get('modelVersionId'),
    }


def compute_since_iso(days: int) -> str:
    window_start = datetime.now(UTC) - timedelta(days=days)
    return window_start.isoformat()
