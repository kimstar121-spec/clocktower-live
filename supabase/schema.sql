create extension if not exists pgcrypto;
alter table public.rooms add column if not exists created_at timestamptz not null default now();
alter table public.rooms add column if not exists game_mode text not null default 'storyteller';
alter table public.rooms add column if not exists winner text;
alter table public.rooms add column if not exists nomination_target_id uuid;
alter table public.rooms drop constraint if exists rooms_code_check;
alter table public.rooms add constraint rooms_code_check check(code ~ '^[0-9]{4}$') not valid;
alter table public.rooms drop constraint if exists rooms_status_check;
alter table public.rooms add constraint rooms_status_check check(status in ('lobby','setup','day','night','ended','finished'));
alter table public.players add column if not exists user_id uuid;
alter table public.players add column if not exists role text;
alter table public.players add column if not exists alive boolean not null default true;
alter table public.players add column if not exists created_at timestamptz not null default now();
alter table public.players add column if not exists is_storyteller boolean not null default false;
alter table public.players add column if not exists position_x real;
alter table public.players add column if not exists position_y real;
alter table public.players add column if not exists rmk_role text;
create table if not exists public.player_notes(
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  target_player_id uuid not null references public.players(id) on delete cascade,
  position_x real,
  position_y real,
  rmk_role text,
  primary key(room_id,user_id,target_player_id)
);
alter table public.actions add column if not exists user_id uuid;
alter table public.actions add column if not exists day_number int not null default 1;
alter table public.actions add column if not exists action_type text;
alter table public.actions add column if not exists target_id uuid;
alter table public.actions add column if not exists submitted boolean not null default false;
alter table public.actions add column if not exists created_at timestamptz not null default now();
create unique index if not exists players_room_user_key on public.players(room_id,user_id);
create unique index if not exists actions_room_player_day_key on public.actions(room_id,actor_player_id,day_number);
alter table public.rooms enable row level security; alter table public.players enable row level security; alter table public.actions enable row level security; alter table public.game_events enable row level security; alter table public.player_notes enable row level security;
do $$ declare p record; begin
  for p in select tablename,policyname from pg_policies where schemaname='public' and tablename in ('rooms','players','actions') loop
    execute format('drop policy if exists %I on public.%I',p.policyname,p.tablename);
  end loop;
end $$;
create policy "rooms read" on public.rooms for select to authenticated using(true);
create policy "rooms create" on public.rooms for insert to authenticated with check(host_id=(select auth.uid()));
create policy "host updates room" on public.rooms for update to authenticated using(host_id=(select auth.uid())) with check(host_id=(select auth.uid()));
create policy "players read room" on public.players for select to authenticated using(true);
create policy "players join" on public.players for insert to authenticated with check(user_id=(select auth.uid()));
create policy "players update" on public.players for update to authenticated using(user_id=(select auth.uid()) or exists(select 1 from public.rooms r where r.id=room_id and r.host_id=(select auth.uid()))) with check(user_id=(select auth.uid()) or exists(select 1 from public.rooms r where r.id=room_id and r.host_id=(select auth.uid())));
create policy "actions read" on public.actions for select to authenticated using(user_id=(select auth.uid()) or exists(select 1 from public.rooms r where r.id=room_id and r.host_id=(select auth.uid())));
create policy "actions write" on public.actions for insert to authenticated with check(user_id=(select auth.uid()));
create policy "actions change" on public.actions for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()));
drop policy if exists "personal notes read" on public.player_notes;
drop policy if exists "personal notes create" on public.player_notes;
drop policy if exists "personal notes change" on public.player_notes;
create policy "personal notes read" on public.player_notes for select to authenticated using(user_id=(select auth.uid()));
create policy "personal notes create" on public.player_notes for insert to authenticated with check(user_id=(select auth.uid()) and exists(select 1 from public.players p where p.id=player_notes.target_player_id and p.room_id=player_notes.room_id));
create policy "personal notes change" on public.player_notes for update to authenticated using(user_id=(select auth.uid())) with check(user_id=(select auth.uid()) and exists(select 1 from public.players p where p.id=player_notes.target_player_id and p.room_id=player_notes.room_id));
grant select,insert,update on public.rooms,public.players,public.actions,public.player_notes to authenticated;
drop view if exists public.room_players;
create view public.room_players with (security_invoker=true) as
select p.id,p.room_id,p.user_id,p.nickname as name,
  case when p.user_id=(select auth.uid()) or exists(select 1 from public.rooms r where r.id=p.room_id and r.host_id=(select auth.uid()) and r.game_mode='storyteller') then p.role else null end as role,
  p.alive,p.seat_number as seat,p.is_storyteller
from public.players p;
grant select on public.room_players to authenticated;
do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='rooms') then alter publication supabase_realtime add table public.rooms; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='players') then alter publication supabase_realtime add table public.players; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='actions') then alter publication supabase_realtime add table public.actions; end if;
end $$;
