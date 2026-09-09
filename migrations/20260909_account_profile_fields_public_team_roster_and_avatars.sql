alter table public.profiles
  add column if not exists date_of_birth date,
  add column if not exists city text,
  add column if not exists country text,
  add column if not exists phone text,
  add column if not exists preferred_language text not null default 'ru',
  add column if not exists timezone text,
  add column if not exists steam_id text,
  add column if not exists steam_profile_url text,
  add column if not exists avatar_source text not null default 'manual',
  add column if not exists profile_visibility text not null default 'public';

alter table public.profiles drop constraint if exists profiles_avatar_source_check;
alter table public.profiles add constraint profiles_avatar_source_check check (avatar_source in ('manual','steam'));
alter table public.profiles drop constraint if exists profiles_visibility_check;
alter table public.profiles add constraint profiles_visibility_check check (profile_visibility in ('public','private'));
create unique index if not exists profiles_steam_id_unique on public.profiles(steam_id) where steam_id is not null;

drop policy if exists "profiles_public_read" on public.profiles;
drop policy if exists "profiles_owner_read" on public.profiles;
create policy "profiles_owner_read" on public.profiles for select to authenticated
using (id = auth.uid());

create or replace function public.get_public_team_roster(p_team_id text)
returns table(
  roster_position smallint,
  display_name text,
  role text,
  avatar_url text,
  account_linked boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select
    tm.roster_position,
    case
      when tm.user_id is not null then coalesce(nullif(trim(p.nickname), ''), tm.display_name)
      else tm.display_name
    end as display_name,
    tm.role,
    case when tm.user_id is not null then p.avatar_url else null end as avatar_url,
    (tm.user_id is not null) as account_linked
  from public.team_members tm
  join public.teams t on t.id = tm.team_id
  left join public.profiles p on p.id = tm.user_id
  where tm.team_id = p_team_id
    and t.registration_status = 'approved'
  order by tm.roster_position;
$$;
grant execute on function public.get_public_team_roster(text) to anon, authenticated;

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('avatars','avatars',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read" on storage.objects for select to public
using (bucket_id='avatars');

drop policy if exists "avatars_owner_insert" on storage.objects;
create policy "avatars_owner_insert" on storage.objects for insert to authenticated
with check (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists "avatars_owner_update" on storage.objects;
create policy "avatars_owner_update" on storage.objects for update to authenticated
using (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text)
with check (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);

drop policy if exists "avatars_owner_delete" on storage.objects;
create policy "avatars_owner_delete" on storage.objects for delete to authenticated
using (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);