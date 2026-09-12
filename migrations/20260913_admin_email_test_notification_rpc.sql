create or replace function public.admin_queue_test_email()
returns uuid
language plpgsql
security definer
set search_path to 'public','private','auth'
as $$
declare
  v_user uuid:=auth.uid();
  v_id uuid;
begin
  if v_user is null or not private.is_site_admin(v_user) then
    raise exception 'Недостаточно прав';
  end if;

  insert into private.user_notifications(user_id,kind,title,body,href)
  values(
    v_user,
    'admin_email_test',
    'Тест email-уведомлений',
    'Это тестовое уведомление отправлено через очередь Esports Platform → Supabase Edge Function → Resend.',
    'notifications.html'
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.admin_queue_test_email() from public, anon;
grant execute on function public.admin_queue_test_email() to authenticated;
