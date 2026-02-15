# Training Data Contracts v1

## Record types

- `generation`
- `generation_cached`
- `patch`
- `save`
- `publish`

## Required fields (all records)

- `user_id`
- `site_id` (nullable only if not available)
- `source`
- `provider`
- `output_site_json`
- `metadata.contractVersion = "v1"`

## Patch contract

- `patch_operations` must validate against operation union:
  - `add_block`
  - `update_props`
  - `move_section`
  - `remove_block`
  - `remove_section`
- Must include:
  - `input_site_json`
  - `output_site_json`
  - `metadata.attemptedOps`
  - `metadata.appliedOps`
  - `metadata.applyErrors`

## Quality filters before training

- Drop invalid `site_json` against canonical schema
- Drop duplicate `(prompt_hash, output_site_json_hash)`
- Drop rows failing HTML/Tailwind safety checks
- Keep `publish` as highest-quality positives
