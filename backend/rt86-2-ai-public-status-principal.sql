-- RT86.2 — endpoint público somente-leitura do Diretor IA e bloqueio das funções mutáveis.
create or replace function public.rt86_ai_public_status(p_world_id uuid)
returns jsonb language sql security definer set search_path='public','pg_temp' as $$
select jsonb_build_object(
  'version',86,
  'principal','ai_director',
  'director',(select jsonb_build_object(
    'enabled',d.enabled,
    'mode',d.mode,
    'target_difficulty',d.target_difficulty,
    'pace_multiplier',d.pace_multiplier,
    'event_pressure',d.event_pressure,
    'monster_pressure',d.monster_pressure,
    'player_median_points',d.player_median_points,
    'npc_median_points',d.npc_median_points,
    'last_tick',d.last_tick,
    'next_tick',d.next_tick,
    'state',d.state
  ) from public.rt86_ai_director_state d where d.world_id=p_world_id),
  'agents',coalesce((select jsonb_agg(jsonb_build_object(
    'id',a.id,'name',a.display_name,'personality',a.personality,
    'traits',a.traits,'goals',a.goals,'metrics',a.metrics,'cycles',a.cycles,
    'last_action',a.last_action,'last_tick',a.last_tick,'next_tick',a.next_tick,'enabled',a.enabled
  ) order by a.display_name) from public.rt86_npc_ai_agents a where a.world_id=p_world_id),'[]'::jsonb),
  'active_orders',(select count(*) from public.rt86_ai_orders o where o.world_id=p_world_id and o.status in('outbound','returning')),
  'recent_decisions',coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('actor',l.actor,'category',l.category,'action',l.action,'target',l.target,'data',l.data,'created_at',l.created_at) x
    from public.rt86_ai_decision_log l where l.world_id=p_world_id order by l.created_at desc limit 30
  ) q),'[]'::jsonb)
)
$$;

grant execute on function public.rt86_ai_public_status(uuid) to anon,authenticated;
revoke all on function public.rt86_ai_director_tick(uuid) from public,anon,authenticated;
revoke all on function public.rt86_ai_agents_tick(uuid,integer) from public,anon,authenticated;
