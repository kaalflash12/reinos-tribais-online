-- Reino Tribal v1.0.1 — sincronização final de contas e entrega reproduzível.
-- IDs RTxx permanecem apenas internos para compatibilidade técnica.

insert into public.rt_public_release_state(
  slug,product_name,public_version,version_scheme,version_started_at,notes,updated_at
)
values(
  'reino-tribal','Reino Tribal','1.0.1','semver',date '2026-08-22',
  'Sincronização Auth↔perfil concluída; 1 perfil rt_players por usuário Auth; pacote oficial regenerado a partir do main final.',
  now()
)
on conflict(slug) do update set
  product_name=excluded.product_name,
  public_version=excluded.public_version,
  version_scheme=excluded.version_scheme,
  version_started_at=excluded.version_started_at,
  notes=excluded.notes,
  updated_at=now();
