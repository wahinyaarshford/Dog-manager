create table if not exists public.dogcare_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  revision integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.dogcare_state enable row level security;

drop policy if exists "Users can read their own dog-care data" on public.dogcare_state;
create policy "Users can read their own dog-care data"
  on public.dogcare_state
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on public.dogcare_state from anon;
revoke insert, update, delete on public.dogcare_state from authenticated;
grant select on public.dogcare_state to authenticated;

create or replace function public.save_dogcare_state(p_data jsonb, p_expected_revision integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_revision integer;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  select revision into current_revision
  from public.dogcare_state
  where user_id = auth.uid()
  for update;

  if not found then
    if p_expected_revision is distinct from 0 then
      raise exception 'sync_conflict';
    end if;
    insert into public.dogcare_state (user_id, data, revision, updated_at)
    values (auth.uid(), p_data, 1, now());
    return 1;
  end if;

  if current_revision <> p_expected_revision then
    raise exception 'sync_conflict';
  end if;

  update public.dogcare_state
  set data = p_data, revision = current_revision + 1, updated_at = now()
  where user_id = auth.uid();

  return current_revision + 1;
end;
$$;

revoke all on function public.save_dogcare_state(jsonb, integer) from public, anon;
grant execute on function public.save_dogcare_state(jsonb, integer) to authenticated;

insert into storage.buckets (id, name, public)
values ('dogcare-photos', 'dogcare-photos', false)
on conflict (id) do update set public = false;

drop policy if exists "Users can read their own dog-care photos" on storage.objects;
create policy "Users can read their own dog-care photos"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'dogcare-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "Users can upload their own dog-care photos" on storage.objects;
create policy "Users can upload their own dog-care photos"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'dogcare-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "Users can update their own dog-care photos" on storage.objects;
create policy "Users can update their own dog-care photos"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'dogcare-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  )
  with check (
    bucket_id = 'dogcare-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );

drop policy if exists "Users can delete their own dog-care photos" on storage.objects;
create policy "Users can delete their own dog-care photos"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'dogcare-photos'
    and (storage.foldername(name))[1] = (select auth.uid()::text)
  );
