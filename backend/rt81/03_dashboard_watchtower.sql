create or replace function public.rt78_dashboard(p_world_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','auth'
as $function$
declare uid uuid:=auth.uid(); cfg jsonb; result jsonb;
begin
  if uid is null then raise exception 'Sessão inválida'; end if;
  if not exists(select 1 from public.player_worlds where world_id=p_world_id and user_id=uid) then raise exception 'Jogador não participa deste mundo'; end if;
  select config into cfg from public.rt78_strategy_settings where world_id=p_world_id and user_id=uid;
  select jsonb_build_object(
    'version',81,
    'settings',coalesce(cfg,'{}'::jsonb),
    'villages',coalesce((select jsonb_agg(to_jsonb(x)) from (select id,name,x,y,points,loyalty,resources,units,buildings,build_queue,recruit_queue,unit_research_queue,scavenging from public.villages where world_id=p_world_id and owner_user_id=uid order by points desc) x),'[]'::jsonb),
    'targets',coalesce((select jsonb_agg(to_jsonb(x)) from (select id,name,owner_kind,owner_name,tribe_name,x,y,points,loyalty,coalesce((buildings->>'wall')::int,0) wall from public.villages where world_id=p_world_id and coalesce(owner_user_id,'00000000-0000-0000-0000-000000000000'::uuid)<>uid order by case owner_kind when 'barbarian' then 0 when 'ai' then 1 else 2 end,points desc limit 1500) x),'[]'::jsonb),
    'scheduled',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.rt78_scheduled_commands where world_id=p_world_id and user_id=uid order by created_at desc limit 100) x),'[]'::jsonb),
    'routes',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.rt78_market_routes where world_id=p_world_id and user_id=uid order by created_at desc limit 100) x),'[]'::jsonb),
    'intel',coalesce((select jsonb_agg(to_jsonb(x)) from (select i.*,v.name,v.owner_kind,v.owner_name,v.tribe_name,v.x,v.y,v.points from public.rt78_target_intel i join public.villages v on v.id=i.target_village_id where i.world_id=p_world_id and i.user_id=uid order by i.last_seen_at desc limit 200) x),'[]'::jsonb),
    'incoming',coalesce((
      select jsonb_agg(to_jsonb(x) order by x.arrives_at) from (
        select c.id,c.source_village_id,c.target_village_id,c.owner_user_id,c.phase,c.kind,
          (intel->'troops') as troops,
          c.started_at,c.arrives_at,
          case when coalesce((intel->>'watchtower_level')::int,0)>=15 then c.payload else '{}'::jsonb end as payload,
          s.name source_name,s.x source_x,s.y source_y,t.name target_name,t.x target_x,t.y target_y,
          (intel->>'watchtower_level')::int watchtower,
          intel->>'visibility' visibility,
          nullif(intel->>'total_units','')::bigint total_units,
          coalesce((intel->>'approximate')::boolean,false) approximate,
          intel->>'class' class,
          nullif(intel->>'siege_detected','')::boolean siege_detected,
          nullif(intel->>'noble_detected','')::boolean noble_detected,
          (intel->>'risk')::int risk
        from public.commands c
        join public.villages t on t.id=c.target_village_id
        left join public.villages s on s.id=c.source_village_id
        cross join lateral private.rt81_incoming_intel(t.buildings,c.troops,c.kind,c.arrives_at) intel
        where c.world_id=p_world_id and c.resolved_at is null and t.owner_user_id=uid and c.owner_user_id<>uid
        order by c.arrives_at limit 100
      ) x
    ),'[]'::jsonb),
    'logs',coalesce((select jsonb_agg(to_jsonb(x)) from (select * from public.rt78_action_log where world_id=p_world_id and user_id=uid order by created_at desc limit 100) x),'[]'::jsonb)
  ) into result;
  return result;
end $function$;
