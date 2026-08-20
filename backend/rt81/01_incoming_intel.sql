create or replace function private.rt81_incoming_intel(
  p_buildings jsonb,
  p_troops jsonb,
  p_kind text,
  p_arrives_at timestamptz
) returns jsonb
language sql
stable
set search_path = ''
as $$
  with q as (
    select
      greatest(0, coalesce((p_buildings->>'watchtower')::int,0)) as lvl,
      coalesce((select sum(greatest(0,(value)::bigint)) from jsonb_each_text(coalesce(p_troops,'{}'::jsonb))),0)::bigint as total,
      coalesce((p_troops->>'noble')::bigint,0)>0 as has_noble,
      (coalesce((p_troops->>'ram')::bigint,0)+coalesce((p_troops->>'catapult')::bigint,0))>0 as has_siege,
      coalesce((p_troops->>'spy')::bigint,0)>0 as has_spy
  ), x as (
    select q.*,
      case when lvl between 1 and 4 then greatest(1,(round(total::numeric/25)*25)::bigint)
           when lvl>=5 then total else null::bigint end as visible_total,
      case when p_arrives_at < now()+interval '10 minutes' then 20 else 0 end as urgency
    from q
  )
  select jsonb_build_object(
    'watchtower_level',lvl,
    'visibility',case when lvl<1 then 'unknown' when lvl<5 then 'approximate' when lvl<10 then 'quantity' when lvl<15 then 'tactical' else 'composition' end,
    'total_units',visible_total,
    'approximate',lvl between 1 and 4,
    'class',case
      when lvl<1 then 'unknown'
      when lvl<5 then 'hostile'
      when lvl<10 then case when lower(coalesce(p_kind,'attack'))='attack' then 'attack' else lower(coalesce(p_kind,'movement')) end
      when has_noble then 'noble'
      when has_siege then 'siege'
      when has_spy and total<=coalesce((p_troops->>'spy')::bigint,0)+2 then 'spy'
      when total<=10 then 'fake_likely'
      else case when lower(coalesce(p_kind,'attack'))='attack' then 'attack' else lower(coalesce(p_kind,'movement')) end
    end,
    'siege_detected',case when lvl>=10 then has_siege else null::boolean end,
    'noble_detected',case when lvl>=10 then has_noble else null::boolean end,
    'troops',case when lvl>=15 then coalesce(p_troops,'{}'::jsonb) else '{}'::jsonb end,
    'risk',least(100,greatest(1,
      20 + urgency
      + case when lvl>=1 then least(50,coalesce(visible_total,0)/20) else 0 end
      + case when lvl>=10 and has_noble then 25 else 0 end
      + case when lvl>=10 and has_siege then 15 else 0 end
    ))::int
  ) from x;
$$;
revoke all on function private.rt81_incoming_intel(jsonb,jsonb,text,timestamptz) from public, anon, authenticated;
