create table if not exists public.rt81_incoming_signals (
  command_id uuid primary key references public.commands(id) on delete cascade,
  world_id uuid not null,
  target_user_id uuid not null,
  target_village_id uuid not null,
  arrives_at timestamptz,
  phase text,
  updated_at timestamptz not null default now()
);

create index if not exists rt81_incoming_signals_user_world_idx on public.rt81_incoming_signals(target_user_id,world_id,updated_at desc);
create index if not exists rt81_incoming_signals_arrival_idx on public.rt81_incoming_signals(world_id,arrives_at);

alter table public.rt81_incoming_signals enable row level security;
drop policy if exists rt81_incoming_signal_own on public.rt81_incoming_signals;
create policy rt81_incoming_signal_own on public.rt81_incoming_signals for select to authenticated using ((select auth.uid())=target_user_id);
revoke all on table public.rt81_incoming_signals from anon, authenticated;
grant select on table public.rt81_incoming_signals to authenticated;

create or replace function private.rt81_sync_incoming_signal()
returns trigger
language plpgsql
security definer
set search_path=public,auth,pg_temp
as $$
declare target_uid uuid;
begin
  if tg_op='DELETE' then
    delete from public.rt81_incoming_signals where command_id=old.id;
    return old;
  end if;

  if coalesce(new.kind,'')<>'attack'
     or new.resolved_at is not null
     or coalesce(new.phase,'') not like 'outbound%' then
    delete from public.rt81_incoming_signals where command_id=new.id;
    return new;
  end if;

  select owner_user_id into target_uid from public.villages where id=new.target_village_id;
  if target_uid is null or target_uid=new.owner_user_id then
    delete from public.rt81_incoming_signals where command_id=new.id;
    return new;
  end if;

  insert into public.rt81_incoming_signals(command_id,world_id,target_user_id,target_village_id,arrives_at,phase,updated_at)
  values(new.id,new.world_id,target_uid,new.target_village_id,new.arrives_at,new.phase,now())
  on conflict(command_id) do update set
    world_id=excluded.world_id,
    target_user_id=excluded.target_user_id,
    target_village_id=excluded.target_village_id,
    arrives_at=excluded.arrives_at,
    phase=excluded.phase,
    updated_at=now();
  return new;
end $$;

revoke all on function private.rt81_sync_incoming_signal() from public,anon,authenticated;

drop trigger if exists rt81_commands_incoming_signal_trg on public.commands;
create trigger rt81_commands_incoming_signal_trg
after insert or update or delete on public.commands
for each row execute function private.rt81_sync_incoming_signal();

do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='rt81_incoming_signals') then
    alter publication supabase_realtime add table public.rt81_incoming_signals;
  end if;
end $$;
