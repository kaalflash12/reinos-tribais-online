-- RT81 — fechamento de leituras brutas que contornavam fog-of-war/Torre de Vigia.

drop policy if exists commands_read_involved on public.commands;
drop policy if exists commands_select_own on public.commands;
create policy commands_select_own on public.commands for select to authenticated
using ((select auth.uid()) = owner_user_id);

drop policy if exists villages_read_world on public.villages;
drop policy if exists villages_select_own on public.villages;
create policy villages_select_own on public.villages for select to authenticated
using ((select auth.uid()) = owner_user_id);

drop policy if exists player_worlds_read_world on public.player_worlds;
drop policy if exists player_worlds_select_own on public.player_worlds;
create policy player_worlds_select_own on public.player_worlds for select to authenticated
using ((select auth.uid()) = user_id);

create or replace function public.rt81_world_directory()
returns jsonb
language sql
security definer
set search_path = 'public','auth','pg_temp'
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'world_id', w.id,
    'player_count', coalesce(c.player_count,0),
    'joined', exists(select 1 from public.player_worlds me where me.world_id=w.id and me.user_id=auth.uid() and not me.is_suspended)
  ) order by w.created_at), '[]'::jsonb)
  from public.worlds w
  left join lateral (
    select count(*)::int player_count
    from public.player_worlds p
    where p.world_id=w.id and not p.is_suspended
  ) c on true
  where w.is_active and w.status='open' and auth.uid() is not null;
$$;
revoke all on function public.rt81_world_directory() from public, anon;
grant execute on function public.rt81_world_directory() to authenticated;
comment on function public.rt81_world_directory() is 'Safe world directory: only world population counts plus the caller membership flag; no other player profile fields.';
