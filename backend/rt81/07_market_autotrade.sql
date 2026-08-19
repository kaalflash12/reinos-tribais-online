create or replace function public.rt79_market_autotrade(p_world_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','auth','pg_temp'
as $function$
declare
  uid uuid:=auth.uid(); cfg jsonb; acfg jsonb; enabled boolean:=false; max_trades int:=1;
  min_cfg jsonb; target_cfg jsonb; ratio_cfg jsonb; default_min bigint:=1000; default_ratio numeric:=1;
  o public.market_offers%rowtype; b public.villages%rowtype; ratio numeric; allowed_ratio numeric; reserve bigint; target bigint;
  trades int:=0; failures int:=0; cap bigint; current_get numeric;
begin
  if uid is null then raise exception 'Sessão inválida';end if;
  if not exists(select 1 from public.player_worlds where world_id=p_world_id and user_id=uid and not is_suspended) then raise exception 'Jogador não participa deste mundo';end if;
  select config into cfg from public.rt78_strategy_settings where world_id=p_world_id and user_id=uid;
  acfg:=coalesce(cfg->'market'->'autoTrade','{}'::jsonb);
  enabled:=coalesce((acfg->>'enabled')::boolean,false);
  if not enabled then return jsonb_build_object('enabled',false,'trades',0);end if;
  max_trades:=greatest(1,least(10,coalesce((acfg->>'maxTradesPerCycle')::int,1)));
  default_min:=greatest(0,case when jsonb_typeof(acfg->'minStock')='number' then (acfg->>'minStock')::bigint else 1000 end);
  default_ratio:=greatest(.05,least(10,case when jsonb_typeof(acfg->'maxRatio')='number' then (acfg->>'maxRatio')::numeric else 1 end));
  min_cfg:=case when jsonb_typeof(acfg->'minStock')='object' then acfg->'minStock' else '{}'::jsonb end;
  target_cfg:=case when jsonb_typeof(acfg->'targetStock')='object' then acfg->'targetStock' else '{}'::jsonb end;
  ratio_cfg:=case when jsonb_typeof(acfg->'maxRatio')='object' then acfg->'maxRatio' else '{}'::jsonb end;

  for o in select * from public.market_offers where world_id=p_world_id and status='open' and seller_user_id<>uid order by (want_amount::numeric/nullif(give_amount,0)),created_at limit 200 loop
    exit when trades>=max_trades;
    ratio:=o.want_amount::numeric/nullif(o.give_amount,0);
    allowed_ratio:=greatest(.05,least(10,coalesce((ratio_cfg->>o.give_resource)::numeric,default_ratio)));
    if ratio is null or ratio>allowed_ratio then continue;end if;
    reserve:=greatest(0,coalesce((min_cfg->>o.want_resource)::bigint,default_min));
    target:=greatest(0,coalesce((target_cfg->>o.give_resource)::bigint,0));
    select * into b from public.villages
      where world_id=p_world_id and owner_user_id=uid
        and coalesce((resources->>o.want_resource)::numeric,0)>=o.want_amount+reserve
        and (target<=0 or coalesce((resources->>o.give_resource)::numeric,0)<target)
      order by coalesce((resources->>o.give_resource)::numeric,0) asc,coalesce((resources->>o.want_resource)::numeric,0) desc limit 1;
    if b.id is null then continue;end if;
    cap:=public.rt79_storage_capacity(coalesce((b.buildings->>'warehouse')::int,0));
    current_get:=coalesce((b.resources->>o.give_resource)::numeric,0);
    if current_get+o.give_amount>cap then continue;end if;
    if target>0 and current_get+o.give_amount>target*1.10 then continue;end if;
    begin
      if public.rt22_market_accept(o.id,b.id) then
        trades:=trades+1;
        insert into public.rt78_action_log(world_id,user_id,category,message,data)
        values(p_world_id,uid,'market','Oferta aceita automaticamente por estoque e razão-alvo',jsonb_build_object('offer_id',o.id,'ratio',ratio,'allowed_ratio',allowed_ratio,'reserve',reserve,'target_stock',target,'village_id',b.id));
      end if;
    exception when others then failures:=failures+1;end;
  end loop;
  return jsonb_build_object('enabled',true,'trades',trades,'failures',failures,'max_trades',max_trades);
end $function$;
