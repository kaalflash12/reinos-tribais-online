-- RT82: pontos derivados no servidor e player_worlds com escrita por coluna.
create or replace function private.rt82_set_village_points()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
begin
  new.points := public.rt82_village_points(coalesce(new.buildings,'{}'::jsonb));
  return new;
end;
$$;

create or replace function private.rt82_refresh_player_points()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  w uuid := coalesce(new.world_id, old.world_id);
  u uuid := coalesce(new.owner_user_id, old.owner_user_id);
begin
  if u is not null then
    update public.player_worlds pw
       set points = coalesce((select sum(v.points) from public.villages v where v.world_id=w and v.owner_user_id=u),0),
           updated_at = now()
     where pw.world_id=w and pw.user_id=u;
  end if;
  if tg_op='UPDATE' and old.owner_user_id is distinct from new.owner_user_id and old.owner_user_id is not null then
    update public.player_worlds pw
       set points = coalesce((select sum(v.points) from public.villages v where v.world_id=old.world_id and v.owner_user_id=old.owner_user_id),0),
           updated_at = now()
     where pw.world_id=old.world_id and pw.user_id=old.owner_user_id;
  end if;
  return coalesce(new,old);
end;
$$;

drop trigger if exists rt82_village_points_before_trg on public.villages;
create trigger rt82_village_points_before_trg
before insert or update of buildings on public.villages
for each row execute function private.rt82_set_village_points();

drop trigger if exists rt82_player_points_after_trg on public.villages;
create trigger rt82_player_points_after_trg
after insert or delete or update of points, owner_user_id, world_id on public.villages
for each row execute function private.rt82_refresh_player_points();

revoke insert, delete, truncate, references, trigger on table public.player_worlds from anon, authenticated;
revoke update on table public.player_worlds from anon, authenticated;
grant select on table public.player_worlds to authenticated;
grant update (player_name, crowns, hero, inventory, flags_inventory, premium, last_seen_at, updated_at) on table public.player_worlds to authenticated;
