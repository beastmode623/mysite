-- Applied to Supabase production on 2026-09-09.
alter table public.tournaments add column if not exists rules_text text;

create or replace function public.get_public_tournament_rules(p_tournament_id text)
returns table(tournament_id text,tournament_name text,game text,status text,rules_text text)
language sql stable security definer set search_path='public' as $$
  select t.id,t.name,t.game,t.status,t.rules_text from public.tournaments t where t.id=p_tournament_id;
$$;
grant execute on function public.get_public_tournament_rules(text) to anon,authenticated;

create or replace function public.admin_update_tournament_rules(p_tournament_id text,p_rules_text text)
returns text language plpgsql security definer set search_path='public','private','auth' as $$
begin
  if not public.is_tournament_admin() then raise exception 'Недостаточно прав'; end if;
  update public.tournaments set rules_text=nullif(trim(coalesce(p_rules_text,'')),''),updated_at=now() where id=p_tournament_id;
  if not found then raise exception 'Турнир не найден'; end if;
  return 'saved';
end;$$;
grant execute on function public.admin_update_tournament_rules(text,text) to authenticated;