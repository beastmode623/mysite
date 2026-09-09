create table if not exists public.team_members (
  id uuid primary key default gen_random_uuid(),
  team_id text not null references public.teams(id) on delete cascade,
  tournament_id text not null references public.tournaments(id) on delete cascade,
  user_id uuid null references auth.users(id) on delete set null,
  display_name text not null,
  role text not null,
  roster_position smallint not null,
  created_at timestamptz not null default now(),
  linked_at timestamptz null,
  constraint team_members_role_check check (role in ('captain','main','reserve')),
  constraint team_members_position_check check (roster_position between 1 and 20),
  unique(team_id, roster_position)
);

create unique index if not exists team_members_team_user_unique on public.team_members(team_id, user_id) where user_id is not null;
create index if not exists team_members_user_idx on public.team_members(user_id);
create index if not exists team_members_tournament_idx on public.team_members(tournament_id);

alter table public.team_members enable row level security;
drop policy if exists "team_members_read_own" on public.team_members;
create policy "team_members_read_own" on public.team_members for select to authenticated
using (user_id = auth.uid() or exists (select 1 from public.teams t where t.id = team_members.team_id and t.owner_id = auth.uid()));

create table if not exists private.team_member_claims (
  member_id uuid primary key references public.team_members(id) on delete cascade,
  email text not null,
  created_at timestamptz not null default now()
);
create index if not exists team_member_claims_email_idx on private.team_member_claims(lower(email));

create or replace function private.sync_team_members_from_application(p_application_id uuid)
returns void language plpgsql security definer set search_path = public, private, auth as $$
declare
  v_app public.tournament_applications%rowtype; v_team public.teams%rowtype; v_item jsonb;
  v_pos integer := 0; v_member_id uuid; v_email text; v_role text; v_user uuid;
begin
  select * into v_app from public.tournament_applications where id = p_application_id;
  if v_app.id is null then raise exception 'Заявка не найдена'; end if;
  select * into v_team from public.teams where id = v_app.team_id;
  if v_team.id is null then raise exception 'Команда не найдена'; end if;
  delete from public.team_members where team_id = v_team.id;
  for v_item in select value from jsonb_array_elements(v_app.roster_private) loop
    v_pos := v_pos + 1;
    v_role := case when coalesce((v_item->>'captain')::boolean,false) then 'captain' when coalesce((v_item->>'reserve')::boolean,false) then 'reserve' else 'main' end;
    v_email := nullif(lower(trim(v_item->>'email')), ''); v_user := null;
    if v_role = 'captain' then v_user := v_team.owner_id;
    elsif v_email is not null then select u.id into v_user from auth.users u where lower(u.email)=v_email limit 1; end if;
    insert into public.team_members(team_id,tournament_id,user_id,display_name,role,roster_position,linked_at)
    values (v_team.id,v_team.tournament_id,v_user,coalesce(nullif(trim(v_item->>'full_name'),''),'Игрок '||v_pos),v_role,v_pos,case when v_user is not null then now() else null end)
    returning id into v_member_id;
    if v_email is not null then insert into private.team_member_claims(member_id,email) values (v_member_id,v_email) on conflict (member_id) do update set email=excluded.email; end if;
  end loop;
end;
$$;

create or replace function public.claim_my_team_memberships()
returns integer language plpgsql security definer set search_path = public, private, auth as $$
declare v_user uuid := auth.uid(); v_email text; v_count integer := 0;
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  select lower(email) into v_email from auth.users where id=v_user;
  if v_email is null then return 0; end if;
  update public.team_members tm set user_id=v_user, linked_at=coalesce(linked_at,now()) from private.team_member_claims c
  where c.member_id=tm.id and tm.user_id is null and lower(c.email)=v_email;
  get diagnostics v_count = row_count; return v_count;
end;
$$;
grant execute on function public.claim_my_team_memberships() to authenticated;

create or replace function public.get_my_team_memberships()
returns table(member_id uuid,team_id text,team_name text,team_tag text,tournament_id text,tournament_name text,game text,tournament_status text,registration_status text,display_name text,role text,roster_position smallint,is_captain boolean)
language plpgsql security definer set search_path = public, private, auth as $$
declare v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'Необходимо войти в аккаунт'; end if;
  perform public.claim_my_team_memberships();
  return query select tm.id,t.id,t.name,t.tag,tr.id,tr.name,tr.game,tr.status,t.registration_status,tm.display_name,tm.role,tm.roster_position,(tm.role='captain')
  from public.team_members tm join public.teams t on t.id=tm.team_id join public.tournaments tr on tr.id=tm.tournament_id
  where tm.user_id=v_user order by tm.created_at desc;
end;
$$;
grant execute on function public.get_my_team_memberships() to authenticated;

create or replace function public.admin_review_application(p_application_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public, private, auth as $$
declare v_team_id text;
begin
  if not public.is_tournament_admin() then raise exception 'Недостаточно прав'; end if;
  if p_status not in ('approved','rejected') then raise exception 'Некорректный статус'; end if;
  select team_id into v_team_id from public.tournament_applications where id=p_application_id for update;
  if v_team_id is null then raise exception 'Заявка не найдена'; end if;
  update public.tournament_applications set status=p_status, reviewed_at=now() where id=p_application_id;
  update public.teams set registration_status=p_status where id=v_team_id;
  if p_status='approved' then perform private.sync_team_members_from_application(p_application_id); else delete from public.team_members where team_id=v_team_id; end if;
end;
$$;

do $$ declare r record; begin for r in select id from public.tournament_applications where status='approved' loop perform private.sync_team_members_from_application(r.id); end loop; end $$;