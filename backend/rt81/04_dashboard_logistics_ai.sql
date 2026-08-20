create or replace function public.rt79_dashboard(p_world_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','auth','pg_temp'
as $function$
declare uid uuid:=auth.uid(); base jsonb; tactical jsonb; events jsonb; outgoing jsonb; scjobs jsonb; transfers jsonb; barbs jsonb;
begin
  if uid is null then raise exception 'Sessao invalida';end if;
  base:=public.rt78_dashboard(p_world_id);
  tactical:=coalesce(base->'incoming','[]'::jsonb);
  select coalesce(jsonb_agg(to_jsonb(x) order by x.starts_at),'[]'::jsonb) into events from (select id,name,category,status,starts_at,ends_at,config,rewards from public.world_events where world_id=p_world_id and status in ('scheduled','active') and coalesce(ends_at,now()+interval '1 day')>now() order by starts_at limit 50) x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.arrives_at),'[]'::jsonb) into outgoing from (select c.id,c.source_village_id,c.target_village_id,c.kind,c.phase,c.troops,c.arrives_at from public.commands c where c.world_id=p_world_id and c.owner_user_id=uid and c.resolved_at is null order by c.arrives_at limit 200) x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.finishes_at),'[]'::jsonb) into scjobs from (select id,village_id,option_id,troops,loot,started_at,finishes_at,status from public.rt79_scavenge_jobs where world_id=p_world_id and user_id=uid order by created_at desc limit 100) x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.arrives_at),'[]'::jsonb) into transfers from (
    select tr.id,tr.source_village_id,tr.target_village_id,s.name source_name,t.name target_name,tr.resource,tr.amount,tr.status,tr.depart_at,tr.arrives_at,tr.delivered_at,tr.metadata
    from public.rt79_resource_transfers tr left join public.villages s on s.id=tr.source_village_id left join public.villages t on t.id=tr.target_village_id
    where tr.world_id=p_world_id and tr.user_id=uid order by tr.created_at desc limit 150
  ) x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.threat_level desc,x.points desc),'[]'::jsonb) into barbs from (
    select v.id,v.name,v.x,v.y,v.points,coalesce((v.buildings->>'wall')::int,0) wall,st.personality,st.threat_level,st.cycles,st.last_tick,st.next_tick
    from public.villages v join public.rt79_barbarian_ai_state st on st.village_id=v.id
    where v.world_id=p_world_id and v.owner_kind='barbarian' order by st.threat_level desc,v.points desc limit 80
  ) x;
  return base||jsonb_build_object('version',81,'incoming_tactical',tactical,'upcoming_events',events,'outgoing',outgoing,'scavenge_jobs',scjobs,'resource_transfers',transfers,'barbarian_ai',barbs);
end $function$;
