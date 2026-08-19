create or replace function public.rt79_farm_recommend(p_world_id uuid,p_source_village_id uuid,p_limit integer default 10,p_max_distance numeric default 30,p_max_wall integer default 10)
returns jsonb
language plpgsql
security definer
set search_path to 'public','auth','pg_temp'
as $function$
declare uid uuid:=auth.uid(); src public.villages%rowtype; out jsonb;
begin
  if uid is null then raise exception 'Sessão inválida'; end if;
  select * into src from public.villages where id=p_source_village_id and world_id=p_world_id and owner_user_id=uid;
  if src.id is null then raise exception 'Aldeia de origem inválida'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'name',r.name,'x',r.vx,'y',r.vy,'points',r.points,'wall',r.wall,'distance',r.distance,
    'last_visit',r.last_visit,'last_loot',r.last_loot,'fullness',r.fullness,'last_result',r.last_result,'visits',r.visits,
    'score',r.score,'recommended_model',r.recommended_model,'risk',r.risk,'threat_level',r.threat_level,'personality',r.personality,
    'cooldown_seconds',r.cooldown_seconds,'confidence',r.confidence
  ) order by r.score,r.distance),'[]'::jsonb) into out
  from (
    select v.id,v.name,v.x vx,v.y vy,v.points,coalesce((v.buildings->>'wall')::int,0) wall,
      round((sqrt(power(v.x-src.x,2)+power(v.y-src.y,2)))::numeric,2) distance,
      i.last_seen_at last_visit,coalesce(i.last_loot,0) last_loot,coalesce(i.fullness,0) fullness,
      coalesce(i.last_result,'unknown') last_result,coalesce(i.visits,0) visits,
      coalesce(st.threat_level,0) threat_level,coalesce(st.personality,'unknown') personality,
      greatest(0,ceil(extract(epoch from ((coalesce(i.last_seen_at,'epoch'::timestamptz)+interval '12 minutes')-now()))))::int cooldown_seconds,
      least(100,20+coalesce(i.visits,0)*12+case when i.last_seen_at>now()-interval '24 hours' then 20 else 0 end)::int confidence,
      round((sqrt(power(v.x-src.x,2)+power(v.y-src.y,2))*7
        + coalesce((v.buildings->>'wall')::numeric,0)*18
        + coalesce(st.threat_level,0)*3
        + case coalesce(i.last_result,'unknown') when 'empty' then 90 when 'partial' then 20 when 'full' then -18 else 0 end
        + case when i.last_seen_at>now()-interval '12 minutes' then 60 else 0 end
        - least(40,coalesce(i.last_loot,0)/250.0))::numeric,2) score,
      case when coalesce(st.threat_level,0)>=8 or coalesce((v.buildings->>'wall')::int,0)>=6 then 'B'
           when coalesce(i.last_result,'unknown')='full' and coalesce((v.buildings->>'wall')::int,0)<=2 and coalesce(st.threat_level,0)<=4 then 'C'
           when coalesce(i.last_result,'unknown')='partial' or coalesce((v.buildings->>'wall')::int,0)>=3 then 'B'
           else 'A' end recommended_model,
      least(100,greatest(0,round(coalesce((v.buildings->>'wall')::numeric,0)*7 + v.points/650.0 + coalesce(st.threat_level,0)*4)))::int risk
    from public.villages v
    left join public.rt78_target_intel i on i.world_id=v.world_id and i.user_id=uid and i.target_village_id=v.id
    left join public.rt79_barbarian_ai_state st on st.village_id=v.id and st.world_id=v.world_id
    where v.world_id=p_world_id and v.owner_kind='barbarian'
      and sqrt(power(v.x-src.x,2)+power(v.y-src.y,2))<=greatest(1,p_max_distance)
      and coalesce((v.buildings->>'wall')::int,0)<=greatest(0,p_max_wall)
    order by score,distance limit greatest(1,least(50,coalesce(p_limit,10)))
  ) r;
  return out;
end $function$;
