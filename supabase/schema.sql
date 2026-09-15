create extension if not exists pgcrypto;
alter table public.rooms add column if not exists created_at timestamptz not null default now();
alter table public.rooms add column if not exists game_mode text not null default 'storyteller';
alter table public.rooms add column if not exists winner text;
alter table public.rooms add column if not exists nomination_target_id uuid;
alter table public.rooms add column if not exists phase_ends_at timestamptz;
alter table public.rooms add column if not exists dawn_message text;
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
create table if not exists public.timer_shortens(
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  day_number int not null,
  phase text not null check(phase in ('day','night')),
  created_at timestamptz not null default now(),
  primary key(room_id,user_id,day_number,phase)
);
alter table public.actions add column if not exists user_id uuid;
alter table public.actions add column if not exists day_number int not null default 1;
alter table public.actions add column if not exists action_type text;
alter table public.actions add column if not exists target_id uuid;
alter table public.actions add column if not exists submitted boolean not null default false;
alter table public.actions add column if not exists created_at timestamptz not null default now();
create unique index if not exists players_room_user_key on public.players(room_id,user_id);
create unique index if not exists actions_room_player_day_key on public.actions(room_id,actor_player_id,day_number);
alter table public.rooms enable row level security; alter table public.players enable row level security; alter table public.actions enable row level security; alter table public.game_events enable row level security; alter table public.player_notes enable row level security; alter table public.timer_shortens enable row level security;
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
drop policy if exists "own timer shortens read" on public.timer_shortens;
create policy "own timer shortens read" on public.timer_shortens for select to authenticated using(user_id=(select auth.uid()));
grant select,insert,update on public.rooms,public.players,public.actions,public.player_notes,public.timer_shortens to authenticated;
drop view if exists public.room_players;
create view public.room_players with (security_invoker=true) as
select p.id,p.room_id,p.user_id,p.nickname as name,
  case when p.user_id=(select auth.uid()) or exists(select 1 from public.rooms r where r.id=p.room_id and r.host_id=(select auth.uid()) and r.game_mode='storyteller') then p.role else null end as role,
  p.alive,p.seat_number as seat,p.is_storyteller
from public.players p;
grant select on public.room_players to authenticated;

create or replace function public.shorten_auto_phase(p_room_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_room public.rooms%rowtype; v_seconds int;
begin
  if not exists(select 1 from public.players p where p.room_id=p_room_id and p.user_id=(select auth.uid()) and not p.is_storyteller) then raise exception '이 방의 플레이어만 단축할 수 있습니다.'; end if;
  select * into v_room from public.rooms where id=p_room_id for update;
  if v_room.game_mode<>'auto' or v_room.status not in ('day','night') then raise exception '자동 진행 중에만 단축할 수 있습니다.'; end if;
  insert into public.timer_shortens(room_id,user_id,day_number,phase) values(p_room_id,(select auth.uid()),v_room.day_number,v_room.status) on conflict do nothing;
  if not found then raise exception '이번 단계의 단축권을 이미 사용했습니다.'; end if;
  v_seconds:=case when v_room.status='day' then 60 else 30 end;
  update public.rooms set phase_ends_at=greatest(now(),phase_ends_at-make_interval(secs=>v_seconds)) where id=p_room_id;
end $$;

create or replace function public.advance_auto_phase(p_room_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare v_room public.rooms%rowtype; v_count int; v_required int; v_done int; v_dead_names text; v_next_day int;
begin
  if not exists(select 1 from public.players p where p.room_id=p_room_id and p.user_id=(select auth.uid()) and not p.is_storyteller) then raise exception '이 방의 플레이어만 진행할 수 있습니다.'; end if;
  select * into v_room from public.rooms where id=p_room_id for update;
  if v_room.game_mode<>'auto' or v_room.status not in ('day','night') then return; end if;
  select count(*) into v_count from public.players where room_id=p_room_id and not is_storyteller;
  if v_room.status='night' then
    select count(*) into v_required from public.players where room_id=p_room_id and alive and not is_storyteller and role = any(case when v_room.day_number=1 then array['독살범','세탁부','사서','수사관','요리사','초공감자','점쟁이','집사','첩자'] else array['독살범','수도사','임프','초공감자','점쟁이','집사','첩자'] end);
    select count(distinct a.actor_player_id) into v_done from public.actions a join public.players p on p.id=a.actor_player_id where a.room_id=p_room_id and a.day_number=v_room.day_number and a.phase='night' and a.submitted and p.alive;
    if coalesce(v_room.phase_ends_at,now())>now() and v_done<v_required then return; end if;
    update public.players victim set alive=false where victim.id in (
      select imp.target_id from public.actions imp where imp.room_id=p_room_id and imp.day_number=v_room.day_number and imp.phase='night' and imp.action_type='임프' and imp.target_id is not null
      and not exists(select 1 from public.actions monk where monk.room_id=p_room_id and monk.day_number=v_room.day_number and monk.phase='night' and monk.action_type='수도사' and monk.target_id=imp.target_id)
    ) and victim.alive returning victim.nickname into v_dead_names;
    update public.rooms set status='day',phase_ends_at=now()+make_interval(secs=>v_count*60),dawn_message=case when v_dead_names is null then '밤사이 아무 일도 일어나지 않았습니다.' else '밤사이 '||v_dead_names||' 님이 사망했습니다.' end where id=p_room_id;
  else
    if coalesce(v_room.phase_ends_at,now())>now() then return; end if;
    v_next_day:=v_room.day_number+1;
    update public.rooms set status='night',day_number=v_next_day,phase_ends_at=now()+make_interval(secs=>v_count*30),dawn_message=null where id=p_room_id;
  end if;
end $$;
revoke all on function public.shorten_auto_phase(uuid) from public;
revoke all on function public.advance_auto_phase(uuid) from public;
grant execute on function public.shorten_auto_phase(uuid),public.advance_auto_phase(uuid) to authenticated;
do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='rooms') then alter publication supabase_realtime add table public.rooms; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='players') then alter publication supabase_realtime add table public.players; end if;
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='actions') then alter publication supabase_realtime add table public.actions; end if;
end $$;
