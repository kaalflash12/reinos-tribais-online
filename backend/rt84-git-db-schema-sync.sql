-- RT84 - Registro canonico de sincronizacao GitHub <-> Supabase.
-- Este arquivo deve ser aplicado como migration e permanecer versionado no GitHub.
-- Nao contem dados de jogadores nem segredos.

create table if not exists public.rt_schema_sync_state (
  environment text primary key,
  github_repository text not null,
  github_schema_commit text not null,
  schema_manifest_hash text not null,
  manifest jsonb not null default '{}'::jsonb,
  synced_at timestamptz not null default now()
);

alter table public.rt_schema_sync_state enable row level security;
revoke all on table public.rt_schema_sync_state from public, anon, authenticated;
grant all on table public.rt_schema_sync_state to service_role;

create or replace function public.rt_schema_manifest()
returns jsonb
language sql
security definer
set search_path to 'public','pg_catalog'
as $function$
with f as (
  select count(*)::int cnt,
         md5(string_agg(p.proname||'('||pg_get_function_identity_arguments(p.oid)||')='||md5(pg_get_functiondef(p.oid)), E'\n' order by p.proname,pg_get_function_identity_arguments(p.oid))) h
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname like 'rt%'
), t as (
  select count(*)::int cnt,
         md5(string_agg(table_name||'='||columns_hash||':'||rls,E'\n' order by table_name)) h
  from (
    select c.table_name,
           md5(string_agg(c.column_name||':'||c.data_type||':'||coalesce(c.udt_name,'')||':'||c.is_nullable||':'||coalesce(c.column_default,''),'|' order by c.ordinal_position)) columns_hash,
           pc.relrowsecurity::text rls
    from information_schema.columns c
    join pg_class pc on pc.relname=c.table_name
    join pg_namespace pn on pn.oid=pc.relnamespace and pn.nspname='public'
    where c.table_schema='public'
      and (c.table_name like 'rt%' or c.table_name in ('worlds','player_worlds','villages','world_nodes','world_monsters','world_monster_hits'))
    group by c.table_name,pc.relrowsecurity
  ) q
), i as (
  select count(*)::int cnt,
         md5(string_agg(tablename||'.'||indexname||'='||md5(indexdef),E'\n' order by tablename,indexname)) h
  from pg_indexes
  where schemaname='public'
    and (tablename like 'rt%' or tablename in ('worlds','player_worlds','villages','world_nodes','world_monsters','world_monster_hits'))
), p as (
  select count(*)::int cnt,
         md5(string_agg(tablename||'.'||policyname||'='||md5(coalesce(cmd,'')||'|'||coalesce(array_to_string(roles,','),'')||'|'||coalesce(qual,'')||'|'||coalesce(with_check,'')),E'\n' order by tablename,policyname)) h
  from pg_policies
  where schemaname='public'
    and (tablename like 'rt%' or tablename in ('worlds','player_worlds','villages','world_nodes','world_monsters','world_monster_hits'))
), m as (
  select count(*)::int cnt,
         md5(string_agg(version||':'||name,E'\n' order by version)) h,
         max(version) latest_version
  from supabase_migrations.schema_migrations
)
select jsonb_build_object(
  'functions_count',f.cnt,'functions_hash',f.h,
  'tables_count',t.cnt,'tables_hash',t.h,
  'indexes_count',i.cnt,'indexes_hash',i.h,
  'policies_count',p.cnt,'policies_hash',p.h,
  'migrations_count',m.cnt,'migrations_hash',m.h,
  'latest_migration',m.latest_version,
  'overall_hash',md5(f.h||t.h||i.h||p.h||m.h)
)
from f,t,i,p,m;
$function$;

revoke all on function public.rt_schema_manifest() from public, anon, authenticated;
grant execute on function public.rt_schema_manifest() to service_role;
