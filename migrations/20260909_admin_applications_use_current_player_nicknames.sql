create or replace function public.admin_list_applications(p_tournament_id text default null)
returns table(
  application_id uuid,
  tournament_id text,
  tournament_name text,
  team_id text,
  team_name text,
  team_tag text,
  application_status text,
  submitted_at timestamptz,
  reviewed_at timestamptz,
  roster_private jsonb,
  submitter_nickname text,
  submitter_email text
)
language plpgsql
security definer
set search_path to 'public','private','auth'
as $$
begin
  if not public.is_tournament_admin() then
    raise exception 'Недостаточно прав';
  end if;

  return query
  select
    a.id,
    a.tournament_id,
    tr.name,
    a.team_id,
    tm.name,
    tm.tag,
    a.status,
    a.submitted_at,
    a.reviewed_at,
    coalesce(r.current_roster, a.roster_private),
    p.nickname,
    u.email::text
  from public.tournament_applications a
  join public.tournaments tr on tr.id = a.tournament_id
  join public.teams tm on tm.id = a.team_id
  left join public.profiles p on p.id = a.submitted_by
  left join auth.users u on u.id = a.submitted_by
  left join lateral (
    select jsonb_agg(
      case
        when tmem.user_id is not null and nullif(trim(pp.nickname), '') is not null
          then jsonb_set(player.item, '{full_name}', to_jsonb(pp.nickname), true)
        else player.item
      end
      order by player.ord
    ) as current_roster
    from jsonb_array_elements(coalesce(a.roster_private, '[]'::jsonb)) with ordinality as player(item, ord)
    left join public.team_members tmem
      on tmem.team_id = a.team_id
     and tmem.roster_position = player.ord::smallint
    left join public.profiles pp on pp.id = tmem.user_id
  ) r on true
  where p_tournament_id is null or a.tournament_id = p_tournament_id
  order by a.submitted_at desc;
end;
$$;
