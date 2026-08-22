-- Exportador de auditoria do schema de producao.
-- Executar somente em console administrativa/service_role.
-- Nao retorna linhas de dados de jogadores; apenas metadata/schema.

-- 1) Manifesto agregado para detectar drift.
select public.rt_schema_manifest() as manifest;

-- 2) Historico de migrations aplicado no Supabase.
select version,name
from supabase_migrations.schema_migrations
order by version;

-- 3) Funcoes de jogo/backend e hash de cada definicao.
select p.proname as function_name,
       pg_get_function_identity_arguments(p.oid) as identity_args,
       md5(pg_get_functiondef(p.oid)) as definition_hash,
       pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname like 'rt%'
order by p.proname,pg_get_function_identity_arguments(p.oid);

-- 4) Tabelas/colunas do jogo (metadata apenas).
select c.table_name,c.ordinal_position,c.column_name,c.data_type,c.udt_name,
       c.is_nullable,c.column_default,pc.relrowsecurity as rls_enabled
from information_schema.columns c
join pg_class pc on pc.relname=c.table_name
join pg_namespace pn on pn.oid=pc.relnamespace and pn.nspname='public'
where c.table_schema='public'
  and (c.table_name like 'rt%' or c.table_name in ('worlds','player_worlds','villages','world_nodes','world_monsters','world_monster_hits'))
order by c.table_name,c.ordinal_position;

-- 5) Indices.
select tablename,indexname,indexdef,md5(indexdef) as definition_hash
from pg_indexes
where schemaname='public'
  and (tablename like 'rt%' or tablename in ('worlds','player_worlds','villages','world_nodes','world_monsters','world_monster_hits'))
order by tablename,indexname;

-- 6) RLS/policies.
select tablename,policyname,cmd,roles,qual,with_check
from pg_policies
where schemaname='public'
  and (tablename like 'rt%' or tablename in ('worlds','player_worlds','villages','world_nodes','world_monsters','world_monster_hits'))
order by tablename,policyname;

-- 7) Commit Git oficialmente registrado no banco.
select environment,github_repository,github_schema_commit,schema_manifest_hash,manifest,synced_at
from public.rt_schema_sync_state
order by environment;
