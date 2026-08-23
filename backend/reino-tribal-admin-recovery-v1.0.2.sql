-- Reino Tribal v1.0.2 — recuperação segura da conta administrativa.
-- O token bruto nunca é persistido: somente SHA-256, expiração e uso único.

create table if not exists public.rt_admin_recovery_tokens (
  token_hash text primary key,
  username text not null default 'reinos_admin',
  expires_at timestamptz not null,
  used_at timestamptz null,
  created_at timestamptz not null default now()
);

alter table public.rt_admin_recovery_tokens enable row level security;
revoke all on table public.rt_admin_recovery_tokens from anon, authenticated;

create or replace function public.rt102_admin_recovery_consume(
  p_token_hash text,
  p_username text,
  p_password text
) returns boolean
language plpgsql
security definer
set search_path to 'public','extensions','pg_temp'
as $$
declare
  aid uuid;
  tok public.rt_admin_recovery_tokens%rowtype;
begin
  if length(coalesce(p_password,'')) < 12 then
    raise exception 'A nova senha precisa ter pelo menos 12 caracteres';
  end if;

  select * into tok
  from public.rt_admin_recovery_tokens
  where token_hash=p_token_hash
    and lower(username)=lower(coalesce(p_username,'reinos_admin'))
    and used_at is null
    and expires_at>now()
  for update;

  if tok.token_hash is null then return false; end if;

  select id into aid
  from public.rt_admin_accounts
  where lower(username)=lower(coalesce(p_username,'reinos_admin')) and active=true
  limit 1;

  if aid is null then return false; end if;

  update public.rt_admin_accounts
     set password_hash=extensions.crypt(p_password,extensions.gen_salt('bf',10)),
         updated_at=now(),
         last_login_at=null
   where id=aid;

  update public.rt_admin_recovery_tokens set used_at=now() where token_hash=p_token_hash;
  delete from public.rt_admin_sessions where admin_id=aid;

  insert into public.rt_admin_audit_log(admin_id,action,payload)
  values(aid,'admin_password_recovered',jsonb_build_object('username',coalesce(p_username,'reinos_admin'),'recovered_at',now()));

  return true;
end;
$$;

revoke all on function public.rt102_admin_recovery_consume(text,text,text) from public, anon, authenticated;
grant execute on function public.rt102_admin_recovery_consume(text,text,text) to service_role;
