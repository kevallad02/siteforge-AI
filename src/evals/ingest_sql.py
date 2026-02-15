from __future__ import annotations

import json
from dataclasses import dataclass
from typing import Any
from uuid import UUID, uuid4

from .contracts import EvalRecord, EvalThresholds
from .runner import build_eval_report

_VALID_RUN_TYPES = {'offline', 'shadow', 'canary'}
_VALID_SCHEMA_VARIANTS = {'sitecraft', 'v2'}


@dataclass(frozen=True, slots=True)
class EvalIngestContext:
    run_type: str = 'offline'
    triggered_by: str | None = 'local-cli'
    commit_sha: str | None = None
    dataset_ref: str | None = None
    source: str = 'scripts/evals/generate_eval_ingest_sql.py'
    schema_variant: str = 'sitecraft'


def _sql_text(value: str | None) -> str:
    if value is None:
        return 'NULL'
    escaped = value.replace("'", "''")
    return f"'{escaped}'"


def _sql_bool(value: bool) -> str:
    return 'true' if value else 'false'


def _sql_int(value: int | None) -> str:
    return 'NULL' if value is None else str(value)


def _sql_jsonb(value: dict[str, Any]) -> str:
    payload = json.dumps(value, separators=(',', ':'), sort_keys=True)
    return f'{_sql_text(payload)}::jsonb'


def _uuid_or_none(value: str | None) -> str | None:
    if value is None:
        return None
    try:
        return str(UUID(value))
    except (ValueError, TypeError):
        return None


def _map_sitecraft_run_type(run_type: str) -> str:
    if run_type == 'shadow':
        return 'online_shadow'
    return run_type


def build_eval_ingest_sql(
    records: list[EvalRecord],
    thresholds: EvalThresholds,
    context: EvalIngestContext,
    report: dict[str, Any] | None = None,
    run_id: str | None = None,
) -> tuple[str, str, str]:
    if context.run_type not in _VALID_RUN_TYPES:
        raise ValueError(
            f'Unsupported run_type: {context.run_type}. Must be one of {_VALID_RUN_TYPES}'
        )
    if context.schema_variant not in _VALID_SCHEMA_VARIANTS:
        raise ValueError(
            'Unsupported schema_variant: '
            f'{context.schema_variant}. Must be one of {_VALID_SCHEMA_VARIANTS}'
        )

    active_run_id = run_id or str(uuid4())
    eval_report = report or build_eval_report(records, thresholds=thresholds)
    status = 'passed' if bool(eval_report['overall_pass']) else 'failed'

    run_metadata = {
        'source': context.source,
        'recordCount': len(records),
        'metrics': eval_report['metrics'],
        'gates': eval_report['gates'],
        'triggeredBy': context.triggered_by,
        'commitSha': context.commit_sha,
        'thresholds': thresholds.as_dict(),
    }

    if context.schema_variant == 'sitecraft':
        sitecraft_status = 'completed' if status == 'passed' else 'failed'
        run_insert = (
            'INSERT INTO public.ai_eval_runs ('
            'id, run_type, status, dataset_ref, provider, model, prompt_set_version, '
            'metrics, metadata, started_at, completed_at'
            ') VALUES ('
            f'{_sql_text(active_run_id)}::uuid, '
            f'{_sql_text(_map_sitecraft_run_type(context.run_type))}, '
            f'{_sql_text(sitecraft_status)}, '
            f'{_sql_text(context.dataset_ref)}, '
            'NULL, '
            'NULL, '
            'NULL, '
            f'{_sql_jsonb(eval_report["metrics"])}, '
            f'{_sql_jsonb(run_metadata)}, '
            "timezone('utc', now()), "
            "timezone('utc', now())"
            ');'
        )
    else:
        run_insert = (
            'INSERT INTO public.ai_eval_runs ('
            'run_id, run_type, triggered_by, commit_sha, dataset_ref, thresholds, status, '
            'started_at, finished_at, metadata'
            ') VALUES ('
            f'{_sql_text(active_run_id)}::uuid, '
            f'{_sql_text(context.run_type)}, '
            f'{_sql_text(context.triggered_by)}, '
            f'{_sql_text(context.commit_sha)}, '
            f'{_sql_text(context.dataset_ref)}, '
            f'{_sql_jsonb(thresholds.as_dict())}, '
            f'{_sql_text(status)}, '
            "timezone('utc', now()), "
            "timezone('utc', now()), "
            f'{_sql_jsonb(run_metadata)}'
            ');'
        )

    lines = ['BEGIN;', run_insert]
    for index, record in enumerate(records, start=1):
        valid_request_id = _uuid_or_none(record.request_id)
        sample_metadata: dict[str, Any] = {'recordId': record.record_id}
        if record.request_id and valid_request_id is None:
            sample_metadata['invalidRequestId'] = record.request_id

        if context.schema_variant == 'sitecraft':
            sample_key = f'{record.record_id}-{index}'
            sample_metadata = {
                **sample_metadata,
                'requestId': valid_request_id,
                'requestedProvider': record.requested_provider,
                'selectedProvider': record.selected_provider,
                'routeStrategy': record.route_strategy,
                'fallbackUsed': record.fallback_used,
            }
            sample_insert = (
                'INSERT INTO public.ai_eval_samples ('
                'run_id, sample_key, prompt_hash, provider, model, schema_valid, '
                'patch_apply_success, safety_html_tailwind_compliant, edited_after_generate, '
                'published_within_7d, latency_ms, metadata'
                ') VALUES ('
                f'{_sql_text(active_run_id)}::uuid, '
                f'{_sql_text(sample_key)}, '
                'NULL, '
                f'{_sql_text(record.selected_provider)}, '
                'NULL, '
                f'{_sql_bool(record.schema_valid)}, '
                f'{_sql_bool(record.patch_apply_success)}, '
                f'{_sql_bool(record.safety_html_tailwind_compliant)}, '
                f'{_sql_bool(record.edited_after_generate)}, '
                f'{_sql_bool(record.published_within_7d)}, '
                f'{_sql_int(record.latency_ms)}, '
                f'{_sql_jsonb(sample_metadata)}'
                ');'
            )
        else:
            sample_insert = (
                'INSERT INTO public.ai_eval_samples ('
                'run_id, request_id, requested_provider, selected_provider, route_strategy, '
                'fallback_used, latency_ms, schema_valid, patch_apply_success, '
                'edited_after_generate, '
                'published_within_7d, safety_html_tailwind_compliant, metadata'
                ') VALUES ('
                f'{_sql_text(active_run_id)}::uuid, '
                f'{_sql_text(valid_request_id)}::uuid, '
                f'{_sql_text(record.requested_provider)}, '
                f'{_sql_text(record.selected_provider)}, '
                f'{_sql_text(record.route_strategy)}, '
                f'{_sql_bool(record.fallback_used)}, '
                f'{_sql_int(record.latency_ms)}, '
                f'{_sql_bool(record.schema_valid)}, '
                f'{_sql_bool(record.patch_apply_success)}, '
                f'{_sql_bool(record.edited_after_generate)}, '
                f'{_sql_bool(record.published_within_7d)}, '
                f'{_sql_bool(record.safety_html_tailwind_compliant)}, '
                f'{_sql_jsonb(sample_metadata)}'
                ');'
            )
        lines.append(sample_insert)

    lines.append('COMMIT;')
    lines.append('')
    return '\n'.join(lines), active_run_id, status
