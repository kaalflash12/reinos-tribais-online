create table if not exists public.rt85_login_aliases (
  alias text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  source text not null default 'system',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint rt85_login_alias_format check (alias ~ '^[a-z0-9][a-z0-9_.-]{2,31}$')
);
create index if not exists rt85_login_aliases_user_idx on public.rt85_login_aliases(user_id);
alter table public.rt85_login_aliases enable row level security;
revoke all on public.rt85_login_aliases from anon, authenticated;
grant all on public.rt85_login_aliases to service_role;

create or replace function public.rt85_normalize_alias(p_value text)
returns text
language sql
immutable
set search_path = public
as $$
  select trim(both '_' from left(regexp_replace(lower(coalesce(p_value,'')), '[^a-z0-9_.-]+', '_', 'g'), 32));
$$;
revoke all on function public.rt85_normalize_alias(text) from public, anon, authenticated;
grant execute on function public.rt85_normalize_alias(text) to service_role;

insert into public.rt85_login_aliases(alias,user_id,source)
select a.alias,u.id,'email_localpart'
from auth.users u
cross join lateral (select public.rt85_normalize_alias(split_part(coalesce(u.email,''),'@',1)) alias) a
where length(a.alias) between 3 and 32
on conflict (alias) do nothing;

insert into public.rt85_login_aliases(alias,user_id,source)
select a.alias,pw.user_id,'player_name'
from public.player_worlds pw
cross join lateral (select public.rt85_normalize_alias(pw.player_name) alias) a
where length(a.alias) between 3 and 32
on conflict (alias) do nothing;

with preferred as (
  select distinct on (user_id) user_id,alias
  from public.rt85_login_aliases
  order by user_id, case source when 'player_name' then 0 else 1 end, created_at
)
insert into public.rt_players(user_id,username,anchor_x,anchor_y,last_seen_at)
select u.id,coalesce(p.alias,public.rt85_normalize_alias(split_part(coalesce(u.email,''),'@',1)),'governante'),500,500,now()
from auth.users u
left join preferred p on p.user_id=u.id
on conflict (user_id) do update set username=excluded.username,last_seen_at=now();

create or replace function public.rt85_sync_current_user(p_preferred_alias text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid:=auth.uid();
  em text;
  preferred text:=public.rt85_normalize_alias(p_preferred_alias);
  fallback text;
  chosen text;
  conflict_uid uuid;
begin
  if uid is null then raise exception 'Sessão inválida'; end if;
  select email into em from auth.users where id=uid;
  fallback:=public.rt85_normalize_alias(split_part(coalesce(em,''),'@',1));
  if length(preferred) between 3 and 32 then
    select user_id into conflict_uid from public.rt85_login_aliases where alias=preferred;
    if conflict_uid is not null and conflict_uid<>uid then raise exception 'Nome de usuário já está em uso'; end if;
    insert into public.rt85_login_aliases(alias,user_id,source,updated_at)
    values(preferred,uid,'claimed',now())
    on conflict(alias) do update set updated_at=excluded.updated_at where public.rt85_login_aliases.user_id=excluded.user_id;
  end if;
  if length(fallback) between 3 and 32 then
    insert into public.rt85_login_aliases(alias,user_id,source,updated_at)
    values(fallback,uid,'email_localpart',now()) on conflict(alias) do nothing;
  end if;
  select alias into chosen from public.rt85_login_aliases where user_id=uid order by case source when 'claimed' then 0 when 'player_name' then 1 else 2 end,created_at limit 1;
  chosen:=coalesce(chosen,fallback,'governante');
  insert into public.rt_players(user_id,username,anchor_x,anchor_y,last_seen_at)
  values(uid,chosen,500,500,now())
  on conflict(user_id) do update set username=excluded.username,last_seen_at=now();
  return jsonb_build_object('user_id',uid,'username',chosen,'profile_ready',true);
end;
$$;
revoke all on function public.rt85_sync_current_user(text) from public, anon;
grant execute on function public.rt85_sync_current_user(text) to authenticated;

comment on table public.rt85_login_aliases is 'RT85 aliases de login; somente service_role acessa. O cliente nunca recebe e-mails resolvidos por alias.';