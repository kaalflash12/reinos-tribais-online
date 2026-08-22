-- Reino Tribal v1.0.0 — primeira versão pública oficial.
-- Os identificadores RTxx anteriores permanecem somente como IDs técnicos de compatibilidade.

create table if not exists public.rt_public_release_state(
  slug text primary key,
  product_name text not null,
  public_version text not null,
  version_scheme text not null default 'semver',
  version_started_at date not null,
  git_commit text,
  notes text,
  updated_at timestamptz not null default now(),
  constraint rt_public_release_version_chk check(public_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$')
);

alter table public.rt_public_release_state enable row level security;

insert into public.rt_public_release_state(slug,product_name,public_version,version_scheme,version_started_at,notes,updated_at)
values('reino-tribal','Reino Tribal','1.0.0','semver',date '2026-08-22','Primeira versão pública oficial; identificadores RT anteriores são apenas internos.',now())
on conflict(slug) do update set
  product_name=excluded.product_name,
  public_version=excluded.public_version,
  version_scheme=excluded.version_scheme,
  version_started_at=excluded.version_started_at,
  notes=excluded.notes,
  updated_at=now();

create or replace function public.reino_tribal_public_release()
returns jsonb
language sql
stable
security definer
set search_path='public','pg_temp'
as $$
  select jsonb_build_object(
    'name',product_name,
    'version',public_version,
    'scheme',version_scheme,
    'version_started_at',version_started_at,
    'git_commit',git_commit
  )
  from public.rt_public_release_state
  where slug='reino-tribal';
$$;
