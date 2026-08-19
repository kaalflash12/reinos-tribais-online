create or replace function public.rt79_farm_batch_smart(p_world_id uuid,p_source_village_id uuid,p_limit integer default 5,p_max_distance numeric default 30,p_max_wall integer default 10)
returns jsonb
language plpgsql
security definer
set search_path to 'public','auth','pg_temp'
as $function$
declare uid uuid:=auth.uid(); cfg jsonb; fcfg jsonb; templates jsonb; src public.villages%rowtype; rec jsonb; model text; troops jsonb; travel bigint; arr timestamptz; sent int:=0; errors jsonb:='[]'::jsonb;
begin
  if uid is null then raise exception 'Sessão inválida'; end if;
  select * into src from public.villages where id=p_source_village_id and world_id=p_world_id and owner_user_id=uid;
  if src.id is null then raise exception 'Aldeia de origem inválida'; end if;
  select config into cfg from public.rt78_strategy_settings where world_id=p_world_id and user_id=uid;
  fcfg:=coalesce(cfg->'farm','{}'::jsonb);
  templates:=jsonb_build_object('A',jsonb_build_object('spear',25),'B',jsonb_build_object('axe',40,'light',10),'C',jsonb_build_object('light',40,'spy',1))||coalesce(fcfg->'templates','{}'::jsonb);
  for rec in select value from jsonb_array_elements(public.rt79_farm_recommend(p_world_id,p_source_village_id,p_limit,p_max_distance,p_max_wall)) loop
    model:=coalesce(rec->>'recommended_model','A');
    troops:=coalesce(templates->model,'{}'::jsonb);
    begin
      travel:=public.rt78_travel_ms(p_world_id,src.id,(rec->>'id')::uuid,troops,uid);
      arr:=clock_timestamp()+make_interval(secs=>travel/1000.0);
      perform public.rt78_schedule_attack(p_world_id,src.id,(rec->>'id')::uuid,troops,'farm',arr,'random','');
      sent:=sent+1;
    exception when others then errors:=errors||jsonb_build_array(jsonb_build_object('target_id',rec->>'id','model',model,'error',sqlerrm)); end;
  end loop;
  perform public.rt78_process_automations(p_world_id);
  insert into public.rt78_action_log(world_id,user_id,category,message,data) values(p_world_id,uid,'farm','Lote inteligente de farm executado com recomendação unificada',jsonb_build_object('sent',sent,'errors',errors));
  return jsonb_build_object('sent',sent,'errors',errors);
end $function$;

comment on function public.rt81_schedule_batch(uuid,jsonb) is 'RT81 atomic multi-target server-authoritative planner. Entire batch rolls back if any order is invalid.';
