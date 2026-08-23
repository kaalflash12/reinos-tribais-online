-- Reino Tribal v1.0.2 — correção do acesso administrativo e provas E2E.

insert into public.rt_public_release_state(
  slug,product_name,public_version,version_scheme,version_started_at,notes,updated_at
)
values(
  'reino-tribal','Reino Tribal','1.0.2','semver',date '2026-08-22',
  'Recuperação administrativa de uso único; interação mundial persistida validada; ciclo automático de eventos scheduled→active→finished validado.',
  now()
)
on conflict(slug) do update set
  product_name=excluded.product_name,
  public_version=excluded.public_version,
  version_scheme=excluded.version_scheme,
  version_started_at=excluded.version_started_at,
  notes=excluded.notes,
  updated_at=now();
