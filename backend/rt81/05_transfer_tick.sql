create or replace function public.rt79_transfer_tick(p_world_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public','auth','pg_temp'
as $function$
declare uid uuid:=auth.uid(); tr public.rt79_resource_transfers%rowtype; dst public.villages%rowtype; src public.villages%rowtype; dr jsonb; sr jsonb; dval numeric; sval numeric; cap bigint; delivered bigint; overflow bigint; n int:=0;
begin
  if uid is null then raise exception 'Sessao invalida'; end if;
  for tr in select * from public.rt79_resource_transfers where world_id=p_world_id and user_id=uid and status='in_transit' and arrives_at<=now() order by arrives_at for update skip locked loop
    select * into dst from public.villages where id=tr.target_village_id for update;
    select * into src from public.villages where id=tr.source_village_id for update;
    if dst.id is null then
      update public.rt79_resource_transfers set status='failed',updated_at=now(),metadata=metadata||jsonb_build_object('error','target_missing') where id=tr.id;
      continue;
    end if;
    dr:=coalesce(dst.resources,'{}'::jsonb);dval:=coalesce((dr->>tr.resource)::numeric,0);cap:=public.rt79_storage_capacity(coalesce((dst.buildings->>'warehouse')::int,0));
    delivered:=greatest(0,least(tr.amount,cap-floor(dval)::bigint));overflow:=tr.amount-delivered;
    if delivered>0 then dr:=jsonb_set(dr,array[tr.resource],to_jsonb(dval+delivered),true);update public.villages set resources=dr,updated_at=now() where id=dst.id;end if;
    if overflow>0 and src.id is not null then sr:=coalesce(src.resources,'{}'::jsonb);sval:=coalesce((sr->>tr.resource)::numeric,0);sr:=jsonb_set(sr,array[tr.resource],to_jsonb(sval+overflow),true);update public.villages set resources=sr,updated_at=now() where id=src.id;end if;
    update public.rt79_resource_transfers set status='arrived',delivered_at=now(),updated_at=now(),metadata=metadata||jsonb_build_object('delivered',delivered,'overflow_returned',overflow) where id=tr.id;
    insert into public.rt78_action_log(world_id,user_id,category,message,data) values(tr.world_id,uid,'logistics','Remessa chegou ao destino',jsonb_build_object('transfer_id',tr.id,'delivered',delivered,'overflow_returned',overflow,'resource',tr.resource));n:=n+1;
  end loop;
  return jsonb_build_object('processed',n);
end $function$;
