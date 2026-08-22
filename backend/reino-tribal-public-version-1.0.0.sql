-- Reino Tribal v1.0.0 — primeira versão pública oficial.
-- IDs RTxx anteriores permanecem apenas internos para compatibilidade técnica.

create table if not exists public.rt_public_release_state(
  slug text primary key,
  product_name text not null,
  public_version text not null,
  version_scheme text not null default 'semver',
  version_started_at date not null,
  git_commit text,
  notes text,
  updated_at timestamptz not null default now()
);

alter table public.rt_public_release_state enable row level security;

insert into public.rt_public_release_state(slug,product_name,public_version,version_scheme,version_started_at,notes,updated_at)
values('reino-tribal','Reino Tribal','1.0.0','semver',date '2026-08-22','Primeira versão pública oficial; identificadores RT anteriores são apenas internos.',now())
on conflict(slug) do update set product_name=excluded.product_name,public_version=excluded.public_version,version_scheme=excluded.version_scheme,version_started_at=excluded.version_started_at,notes=excluded.notes,updated_at=now();
