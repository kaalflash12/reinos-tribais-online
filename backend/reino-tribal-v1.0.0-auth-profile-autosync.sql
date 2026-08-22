-- Reino Tribal v1.0.0 — sincronização automática Auth -> rt_players.
-- Mantém cada usuário Supabase Auth com um perfil correspondente no jogo.

create or replace function public.rt_sync_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = 'public','pg_temp'
as $$
declare
  uname text;
  px int;
  py int;
begin
  if exists(select 1 from public.rt_players where user_id=new.id) then
    return new;
  end if;

  uname := left(coalesce(
    nullif(trim(new.raw_user_meta_data->>'username'),''),
    nullif(trim(new.raw_user_meta_data->>'name'),''),
    nullif(split_part(coalesce(new.email,''),'@',1),''),
    'Governante'
  ),32);

  px := 470 + mod(abs(hashtext(new.id::text)),61);
  py := 470 + mod(abs(hashtext(reverse(new.id::text))),61);
  while exists(select 1 from public.rt_players where anchor_x=px and anchor_y=py) loop
    px := 470 + mod(px-469,61);
    py := 470 + mod(py-467,61);
  end loop;

  insert into public.rt_players(user_id,username,anchor_x,anchor_y)
  values(new.id,uname,px,py)
  on conflict(user_id) do nothing;
  return new;
end
$$;

drop trigger if exists rt_sync_auth_user_profile_trigger on auth.users;
create trigger rt_sync_auth_user_profile_trigger
after insert on auth.users
for each row execute function public.rt_sync_auth_user_profile();

do $$
declare r record; px int; py int; uname text;
begin
  for r in
    select u.id,u.email,u.raw_user_meta_data
    from auth.users u
    left join public.rt_players p on p.user_id=u.id
    where p.user_id is null
    order by u.created_at
  loop
    uname := left(coalesce(
      nullif(trim(r.raw_user_meta_data->>'username'),''),
      nullif(trim(r.raw_user_meta_data->>'name'),''),
      nullif(split_part(coalesce(r.email,''),'@',1),''),
      'Governante'
    ),32);
    px := 470 + mod(abs(hashtext(r.id::text)),61);
    py := 470 + mod(abs(hashtext(reverse(r.id::text))),61);
    while exists(select 1 from public.rt_players where anchor_x=px and anchor_y=py) loop
      px := 470 + mod(px-469,61);
      py := 470 + mod(py-467,61);
    end loop;
    insert into public.rt_players(user_id,username,anchor_x,anchor_y)
    values(r.id,uname,px,py)
    on conflict(user_id) do nothing;
  end loop;
end $$;

revoke all on function public.rt_sync_auth_user_profile() from anon, authenticated;
