-- 0001_ai_training_examples_contract_template.sql
-- Purpose:
--   Enforce source-specific training data contracts in ai_training_examples.
-- Notes:
--   This template assumes ai_training_examples already exists.
--   Run in staging first and verify against representative payloads.

BEGIN;

-- 1) Generic shape guarantees.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_training_examples_output_site_json_object_check'
      AND conrelid = 'public.ai_training_examples'::regclass
  ) THEN
    ALTER TABLE public.ai_training_examples
      ADD CONSTRAINT ai_training_examples_output_site_json_object_check
      CHECK (jsonb_typeof(output_site_json) = 'object');
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_training_examples_input_site_json_object_check'
      AND conrelid = 'public.ai_training_examples'::regclass
  ) THEN
    ALTER TABLE public.ai_training_examples
      ADD CONSTRAINT ai_training_examples_input_site_json_object_check
      CHECK (input_site_json IS NULL OR jsonb_typeof(input_site_json) = 'object');
  END IF;
END $$;

-- 2) Generation contracts.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_training_examples_generation_contract_check'
      AND conrelid = 'public.ai_training_examples'::regclass
  ) THEN
    ALTER TABLE public.ai_training_examples
      ADD CONSTRAINT ai_training_examples_generation_contract_check
      CHECK (
        source NOT IN ('generation', 'generation_cached')
        OR (
          prompt IS NOT NULL
          AND provider IN ('openai', 'custom')
          AND patch_operations IS NULL
        )
      );
  END IF;
END $$;

-- 3) Patch contracts.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_training_examples_patch_contract_check'
      AND conrelid = 'public.ai_training_examples'::regclass
  ) THEN
    ALTER TABLE public.ai_training_examples
      ADD CONSTRAINT ai_training_examples_patch_contract_check
      CHECK (
        source <> 'patch'
        OR (
          input_site_json IS NOT NULL
          AND jsonb_typeof(patch_operations) = 'array'
          AND jsonb_typeof(metadata) = 'object'
          AND (metadata ? 'attemptedOps')
          AND (metadata ? 'appliedOps')
          AND (metadata ? 'applyErrors')
        )
      );
  END IF;
END $$;

-- 4) Save/publish contracts.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ai_training_examples_outcome_contract_check'
      AND conrelid = 'public.ai_training_examples'::regclass
  ) THEN
    ALTER TABLE public.ai_training_examples
      ADD CONSTRAINT ai_training_examples_outcome_contract_check
      CHECK (
        source NOT IN ('save', 'publish')
        OR (
          site_id IS NOT NULL
          AND jsonb_typeof(metadata) = 'object'
          AND (metadata ? 'capturedAt')
        )
      );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_ai_training_examples_source_created
  ON public.ai_training_examples(source, created_at DESC);

COMMIT;
