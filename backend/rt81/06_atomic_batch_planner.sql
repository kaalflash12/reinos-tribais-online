create or replace function public.rt81_schedule_batch(p_world_id uuid,p_orders jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public','auth','pg_temp'
as $function$
declare uid uuid:=auth.uid(); n int; item jsonb; idx int:=0; kind text; source_id uuid; target_id uuid; troops jsonb; arrival timestamptz; cat1 text; cat2 text; result jsonb; items jsonb:='[]'::jsonb;
begin
  if uid is null then raise exception 'Sessão inválida'; end if;
  if not exists(select 1 from public.player_worlds where world_id=p_world_id and user_id=uid and not is_suspended) then raise exception 'Jogador não participa deste mundo'; end if;
  if jsonb_typeof(p_orders)<>'array' then raise exception 'p_orders precisa ser uma lista'; end if;
  n:=jsonb_array_length(p_orders);
  if n<1 or n>50 then raise exception 'Planejamento em lote aceita de 1 a 50 ordens'; end if;
  for item in select value from jsonb_array_elements(p_orders) loop
    idx:=idx+1;
    begin
      source_id:=(item->>'source_village_id')::uuid;
      target_id:=(item->>'target_village_id')::uuid;
      troops:=coalesce(item->'troops','{}'::jsonb);
      kind:=lower(coalesce(item->>'kind','attack'));
      arrival:=(item->>'arrives_at')::timestamptz;
      cat1:=coalesce(item->>'catapult_target','random');
      cat2:=coalesce(item->>'catapult_target2','');
    exception when others then
      raise exception 'Ordem % inválida: %',idx,sqlerrm;
    end;
    if kind='support' then
      result:=public.rt78_schedule_support(p_world_id,source_id,target_id,troops,arrival);
    elsif kind in ('attack','fake','farm') then
      result:=public.rt78_schedule_attack(p_world_id,source_id,target_id,troops,kind,arrival,cat1,cat2);
    else
      raise exception 'Ordem %: tipo inválido %',idx,kind;
    end if;
    items:=items||jsonb_build_array(result||jsonb_build_object('index',idx,'target_village_id',target_id));
  end loop;
  insert into public.rt78_action_log(world_id,user_id,category,message,data)
  values(p_world_id,uid,'war','Planejamento multi-alvo programado de forma atômica',jsonb_build_object('orders',n,'items',items));
  return jsonb_build_object('version',81,'count',n,'items',items);
end $function$;
revoke all on function public.rt81_schedule_batch(uuid,jsonb) from public, anon;
grant execute on function public.rt81_schedule_batch(uuid,jsonb) to authenticated;
