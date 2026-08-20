create or replace function public.rt82_assign_flag(p_world_id uuid,p_village_id uuid,p_flag_key text)
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare uid uuid:=auth.uid(); pw public.player_worlds%rowtype; v public.villages%rowtype; inv jsonb; parts text[]; typ text; lvl int; oldkey text; nowms bigint:=floor(extract(epoch from clock_timestamp())*1000)::bigint;
begin
 if uid is null then raise exception 'Sessão inválida'; end if;
 parts:=regexp_split_to_array(coalesce(p_flag_key,''),'_'); if array_length(parts,1)<>2 then raise exception 'Bandeira inválida'; end if;
 typ:=parts[1]; lvl:=parts[2]::int;
 if typ not in ('production','recruitment','attack','defense','luck','population','coin','loot') or lvl<1 or lvl>9 then raise exception 'Bandeira inválida'; end if;
 select * into pw from public.player_worlds where world_id=p_world_id and user_id=uid for update;
 select * into v from public.villages where id=p_village_id and world_id=p_world_id and owner_user_id=uid for update;
 if pw.id is null or v.id is null then raise exception 'Aldeia inválida'; end if;
 inv:=coalesce(pw.flags_inventory,'{}'::jsonb); if coalesce((inv->>p_flag_key)::int,0)<=0 then raise exception 'Bandeira indisponível'; end if;
 if v.flag is not null and jsonb_typeof(v.flag)='object' and coalesce(v.flag->>'type','')<>'' then oldkey:=(v.flag->>'type')||'_'||coalesce(v.flag->>'level','1'); inv:=jsonb_set(inv,array[oldkey],to_jsonb(coalesce((inv->>oldkey)::int,0)+1),true); end if;
 inv:=jsonb_set(inv,array[p_flag_key],to_jsonb(coalesce((inv->>p_flag_key)::int,0)-1),true);
 update public.player_worlds set flags_inventory=inv,updated_at=now() where id=pw.id;
 update public.villages set flag=jsonb_build_object('type',typ,'level',lvl,'assignedAt',nowms),updated_at=now() where id=v.id;
 return jsonb_build_object('flag',jsonb_build_object('type',typ,'level',lvl,'assignedAt',nowms),'flags_inventory',inv);
end $$;

create or replace function public.rt82_remove_flag(p_world_id uuid,p_village_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare uid uuid:=auth.uid(); pw public.player_worlds%rowtype; v public.villages%rowtype; inv jsonb; oldkey text;
begin
 if uid is null then raise exception 'Sessão inválida'; end if;
 select * into pw from public.player_worlds where world_id=p_world_id and user_id=uid for update;
 select * into v from public.villages where id=p_village_id and world_id=p_world_id and owner_user_id=uid for update;
 if pw.id is null or v.id is null then raise exception 'Aldeia inválida'; end if;
 inv:=coalesce(pw.flags_inventory,'{}'::jsonb);
 if v.flag is null or jsonb_typeof(v.flag)<>'object' or coalesce(v.flag->>'type','')='' then return jsonb_build_object('flag',null,'flags_inventory',inv); end if;
 oldkey:=(v.flag->>'type')||'_'||coalesce(v.flag->>'level','1'); inv:=jsonb_set(inv,array[oldkey],to_jsonb(coalesce((inv->>oldkey)::int,0)+1),true);
 update public.player_worlds set flags_inventory=inv,updated_at=now() where id=pw.id; update public.villages set flag=null,updated_at=now() where id=v.id;
 return jsonb_build_object('flag',null,'flags_inventory',inv);
end $$;

create or replace function public.rt82_combine_flags(p_world_id uuid,p_flag_key text)
returns jsonb language plpgsql security definer set search_path=public,auth,pg_temp as $$
declare uid uuid:=auth.uid(); pw public.player_worlds%rowtype; inv jsonb; parts text[]; typ text; lvl int; nextkey text;
begin
 if uid is null then raise exception 'Sessão inválida'; end if;
 parts:=regexp_split_to_array(coalesce(p_flag_key,''),'_'); if array_length(parts,1)<>2 then raise exception 'Bandeira inválida'; end if;
 typ:=parts[1]; lvl:=parts[2]::int; if typ not in ('production','recruitment','attack','defense','luck','population','coin','loot') or lvl<1 or lvl>=9 then raise exception 'Nível máximo ou bandeira inválida'; end if;
 select * into pw from public.player_worlds where world_id=p_world_id and user_id=uid for update; if pw.id is null then raise exception 'Jogador inválido'; end if;
 inv:=coalesce(pw.flags_inventory,'{}'::jsonb); if coalesce((inv->>p_flag_key)::int,0)<3 then raise exception 'São necessárias 3 bandeiras iguais'; end if;
 nextkey:=typ||'_'||(lvl+1)::text; inv:=jsonb_set(inv,array[p_flag_key],to_jsonb(coalesce((inv->>p_flag_key)::int,0)-3),true); inv:=jsonb_set(inv,array[nextkey],to_jsonb(coalesce((inv->>nextkey)::int,0)+1),true);
 update public.player_worlds set flags_inventory=inv,updated_at=now() where id=pw.id; return jsonb_build_object('flags_inventory',inv,'created',nextkey);
end $$;

revoke all on function public.rt82_assign_flag(uuid,uuid,text) from public,anon; grant execute on function public.rt82_assign_flag(uuid,uuid,text) to authenticated;
revoke all on function public.rt82_remove_flag(uuid,uuid) from public,anon; grant execute on function public.rt82_remove_flag(uuid,uuid) to authenticated;
revoke all on function public.rt82_combine_flags(uuid,text) from public,anon; grant execute on function public.rt82_combine_flags(uuid,text) to authenticated;
