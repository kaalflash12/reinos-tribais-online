create or replace function public.rt78_process_automations(p_world_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','auth'
as $function$
declare
  caller uuid:=auth.uid();
  c public.rt78_scheduled_commands%rowtype;
  r public.rt78_market_routes%rowtype;
  s public.villages%rowtype;
  t public.villages%rowtype;
  cid uuid;
  sent int:=0;
  supports int:=0;
  routes int:=0;
  synced int:=0;
  sr jsonb;
  tr jsonb;
  scur numeric;
  tcur numeric;
  moved bigint;
  pending bigint;
  tid uuid;
  cmd record;
  lootn bigint;
begin
  if caller is null then raise exception 'Sessão inválida'; end if;
  if not exists(select 1 from public.player_worlds where world_id=p_world_id and user_id=caller and not is_suspended) then
    raise exception 'Jogador não participa deste mundo';
  end if;

  for c in
    select * from public.rt78_scheduled_commands
    where world_id=p_world_id and user_id=caller and status='scheduled' and depart_at<=clock_timestamp()
    order by depart_at for update skip locked
  loop
    begin
      if c.kind='support' then
        insert into public.online_supports(world_id,source_village_id,target_village_id,owner_user_id,troops,started_at,arrives_at,status,created_at)
        values(c.world_id,c.source_village_id,c.target_village_id,c.user_id,c.troops,clock_timestamp(),c.arrives_at,'outbound',now())
        returning id into cid;
        update public.rt78_scheduled_commands set status='sent',command_id=null,updated_at=now(),error='support_id='||cid::text where id=c.id;
        supports:=supports+1;
        insert into public.rt78_action_log(world_id,user_id,category,message,data)
        values(c.world_id,c.user_id,'support','Apoio programado enviado pelo servidor',jsonb_build_object('schedule_id',c.id,'support_id',cid));
      else
        insert into public.commands(world_id,source_village_id,target_village_id,owner_user_id,kind,phase,troops,loot,payload,started_at,arrives_at)
        values(c.world_id,c.source_village_id,c.target_village_id,c.user_id,'attack','outbound58',c.troops,jsonb_build_object('wood',0,'clay',0,'iron',0),jsonb_build_object('travel_ms',greatest(0,extract(epoch from (c.arrives_at-c.depart_at))*1000)::bigint,'attack_type',c.attack_type,'catapult_target',c.catapult_target,'catapult_target2',c.catapult_target2,'rt78_schedule_id',c.id,'rt78_kind',c.kind),clock_timestamp(),c.arrives_at)
        returning id into cid;
        update public.rt78_scheduled_commands set status='sent',command_id=cid,updated_at=now() where id=c.id;
        sent:=sent+1;
        insert into public.rt78_action_log(world_id,user_id,category,message,data)
        values(c.world_id,c.user_id,'war','Ordem programada enviada pelo servidor',jsonb_build_object('schedule_id',c.id,'command_id',cid));
      end if;
    exception when others then
      update public.rt78_scheduled_commands set status='failed',error=sqlerrm,updated_at=now() where id=c.id;
    end;
  end loop;

  for r in
    select * from public.rt78_market_routes
    where world_id=p_world_id and user_id=caller and enabled
      and (last_run_at is null or last_run_at+make_interval(secs=>interval_seconds)<=clock_timestamp())
    order by coalesce(last_run_at,'epoch'::timestamptz) for update skip locked
  loop
    begin
      select * into s from public.villages where id=r.source_village_id and owner_user_id=caller for update;
      select * into t from public.villages where id=r.target_village_id and owner_user_id=caller;
      if s.id is null or t.id is null then raise exception 'Aldeia de rota inválida'; end if;
      sr:=coalesce(s.resources,'{}'::jsonb);
      tr:=coalesce(t.resources,'{}'::jsonb);
      scur:=coalesce((sr->>r.resource)::numeric,0);
      tcur:=coalesce((tr->>r.resource)::numeric,0);
      select coalesce(sum(amount),0)::bigint into pending
        from public.rt79_resource_transfers
        where world_id=p_world_id and user_id=caller and target_village_id=t.id
          and resource=r.resource and status='in_transit';
      moved:=least(r.amount,greatest(0,floor(scur-r.min_source)::bigint));
      if r.target_max>0 then
        moved:=least(moved,greatest(0,floor(r.target_max-tcur-pending)::bigint));
      end if;
      if moved>=100 then
        tid:=public.rt79_enqueue_transfer_internal(
          p_world_id,caller,s.id,t.id,r.resource,moved,
          jsonb_build_object('source','route','route_id',r.id)
        );
        routes:=routes+1;
        insert into public.rt78_action_log(world_id,user_id,category,message,data)
        values(r.world_id,caller,'market','Rota automática despachou remessa com tempo de viagem',jsonb_build_object('route_id',r.id,'transfer_id',tid,'resource',r.resource,'amount',moved,'source',s.id,'target',t.id));
      end if;
      update public.rt78_market_routes set last_run_at=clock_timestamp(),updated_at=now() where id=r.id;
    exception when others then
      update public.rt78_market_routes set last_run_at=clock_timestamp(),updated_at=now() where id=r.id;
      insert into public.rt78_action_log(world_id,user_id,category,message,data)
      values(r.world_id,caller,'market','Falha em rota automática',jsonb_build_object('route_id',r.id,'error',sqlerrm));
    end;
  end loop;

  for cmd in
    select id,world_id,owner_user_id,target_village_id,loot,payload from public.commands
    where world_id=p_world_id and owner_user_id=caller and resolved_at is not null
      and payload ? 'rt78_schedule_id'
      and coalesce(payload->>'rt78_kind','') <> 'farm'
      and not (payload ? 'rt78_intel_synced')
    limit 200
  loop
    lootn:=coalesce((cmd.loot->>'wood')::bigint,0)+coalesce((cmd.loot->>'clay')::bigint,0)+coalesce((cmd.loot->>'iron')::bigint,0);
    insert into public.rt78_target_intel(world_id,user_id,target_village_id,last_seen_at,visits,last_result,last_loot,snapshot)
    values(cmd.world_id,caller,cmd.target_village_id,now(),1,'resolved',lootn,jsonb_build_object('last_command_id',cmd.id,'last_loot',lootn,'resolved_at',now()))
    on conflict(world_id,user_id,target_village_id) do update
      set last_seen_at=now(),visits=public.rt78_target_intel.visits+1,last_result='resolved',last_loot=lootn,snapshot=public.rt78_target_intel.snapshot||excluded.snapshot;
    update public.commands set payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object('rt78_intel_synced',true) where id=cmd.id;
    synced:=synced+1;
  end loop;

  return jsonb_build_object('scheduled_sent',sent,'supports_sent',supports,'routes_dispatched',routes,'intel_synced',synced,'server_time',now());
end $function$;
