-- Execute com service_role/console administrativa.
-- Resultado esperado: overall_hash igual ao backend/PRODUCTION_DB_MANIFEST_RT84.json
select public.rt_schema_manifest() as live_manifest;
select environment,github_repository,github_schema_commit,schema_manifest_hash,manifest,synced_at
from public.rt_schema_sync_state
order by environment;
