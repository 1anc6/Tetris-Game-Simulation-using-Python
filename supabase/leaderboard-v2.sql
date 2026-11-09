-- Stackfall leaderboard v2: game modes, protected names, checked submissions, ranks.
-- Run once in the Supabase SQL editor, after leaderboard.sql.

-- ---- modes and extra game data on each score
alter table public.scores add column if not exists mode text not null default 'marathon';
alter table public.scores drop constraint if exists scores_mode_check;
alter table public.scores add constraint scores_mode_check check (mode in ('marathon', 'sprint', 'ultra'));
alter table public.scores add column if not exists ms int check (ms between 0 and 86400000);
alter table public.scores add column if not exists pieces int check (pieces between 0 and 1000000);

-- ---- names: the first device to use a name keeps it (it holds a secret only it knows)
create table if not exists public.players (
  name text primary key check (name ~ '^[A-Z0-9 _-]{1,12}$'),
  secret_hash text not null,
  created_at timestamptz not null default now()
);
alter table public.players enable row level security;           -- no policies: nobody reads it directly
revoke all on public.players from anon, authenticated;

-- ---- scores can only be added through submit_score() now
drop policy if exists "anyone can add a plausible score" on public.scores;
revoke insert on public.scores from anon, authenticated;

-- ---- each player's best per mode (sprint: fastest time, others: highest score)
drop view if exists public.best_scores;
create view public.best_scores with (security_invoker = on) as
  select distinct on (mode, name) name, mode, score, ms, lines, level, created_at
  from public.scores
  order by mode, name,
    case when mode = 'sprint' then ms::bigint else -score::bigint end,
    created_at;
grant select on public.best_scores to anon, authenticated;

create index if not exists scores_mode_score on public.scores (mode, score desc);

-- ---- claim a name (or check that this device owns it)
create or replace function public.claim_name(p_name text, p_secret text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  h text;
  owner_hash text;
begin
  if p_name is null or p_name !~ '^[A-Z0-9 _-]{1,12}$' or p_secret is null or length(p_secret) < 16 then
    return 'invalid';
  end if;
  h := encode(digest(p_secret, 'sha256'), 'hex');
  insert into players (name, secret_hash) values (p_name, h) on conflict (name) do nothing;
  select secret_hash into owner_hash from players where name = p_name;
  return case when owner_hash = h then 'ok' else 'taken' end;
end $$;

-- ---- where a player stands in a mode
create or replace function public.player_rank(p_mode text, p_name text)
returns json language plpgsql stable security definer set search_path = public as $$
declare
  me record;
  better int;
begin
  select * into me from best_scores where mode = p_mode and name = p_name;
  if not found then return null; end if;
  if p_mode = 'sprint' then
    select count(*) into better from best_scores where mode = p_mode and ms < me.ms;
  else
    select count(*) into better from best_scores where mode = p_mode and score > me.score;
  end if;
  return json_build_object('rank', better + 1, 'score', me.score, 'ms', me.ms,
                           'lines', me.lines, 'level', me.level);
end $$;

-- ---- add a score. p_log has one entry per line clear: [rows, points, level, combo, chain]
create or replace function public.submit_score(
  p_name text, p_secret text, p_mode text, p_score int, p_lines int, p_level int,
  p_ms int, p_pieces int, p_log jsonb)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  claim text;
  e jsonb;
  n int; pts int; lvl int; cmb int; chn int;
  prev_combo int := -1;
  prev_chain int := 0;
  tot_lines int := 0;
  tot_pts bigint := 0;
begin
  claim := claim_name(p_name, p_secret);
  if claim <> 'ok' then raise exception 'name %', claim using errcode = 'P0001'; end if;
  if p_mode not in ('marathon', 'sprint', 'ultra') then raise exception 'bad mode' using errcode = 'P0001'; end if;
  if p_score is null or p_score < 1 or p_lines is null or p_ms is null or p_pieces is null
     or jsonb_typeof(p_log) <> 'array' or jsonb_array_length(p_log) > 20000 then
    raise exception 'bad data' using errcode = 'P0001';
  end if;
  -- one score per name every 10 seconds
  if exists (select 1 from scores where name = p_name and created_at > now() - interval '10 seconds') then
    raise exception 'too fast' using errcode = 'P0001';
  end if;

  -- replay the clears: levels, combos and chains must follow the game's rules,
  -- and no clear may score more than the best possible clear at that point
  for e in select value from jsonb_array_elements(p_log) loop
    n := (e->>0)::int; pts := (e->>1)::int; lvl := (e->>2)::int; cmb := (e->>3)::int; chn := (e->>4)::int;
    if n is null or n < 1 or n > 20 then raise exception 'bad clear' using errcode = 'P0001'; end if;
    if lvl <> 1 + tot_lines / 10 then raise exception 'bad level' using errcode = 'P0001'; end if;
    if not (cmb = 0 or cmb = prev_combo + 1) then raise exception 'bad combo' using errcode = 'P0001'; end if;
    if not (chn = 0 or (chn = prev_chain + 1 and cmb = prev_combo + 1)) then
      raise exception 'bad chain' using errcode = 'P0001';
    end if;
    if pts < 100 * lvl or pts::bigint > lvl::bigint * (2400 * (chn + 1) + 50 * cmb + 3200) then
      raise exception 'bad points' using errcode = 'P0001';
    end if;
    tot_lines := tot_lines + n; tot_pts := tot_pts + pts;
    prev_combo := cmb; prev_chain := chn;
  end loop;

  if tot_pts <> p_score or tot_lines <> p_lines or p_level <> 1 + p_lines / 10 then
    raise exception 'totals do not match' using errcode = 'P0001';
  end if;
  -- every row needs 10 blocks and a piece brings 4; nobody places 20 pieces a second
  if p_pieces * 4 < p_lines * 10 or p_ms < p_pieces * 50 then
    raise exception 'too fast to be real' using errcode = 'P0001';
  end if;
  if p_mode = 'sprint' and p_lines < 40 then raise exception 'sprint not finished' using errcode = 'P0001'; end if;
  if p_mode = 'ultra' and p_ms > 125000 then raise exception 'ultra too long' using errcode = 'P0001'; end if;

  insert into scores (name, grp, mode, score, lines, level, ms, pieces)
  values (p_name, '', p_mode, p_score, p_lines, p_level, p_ms, p_pieces);
  return player_rank(p_mode, p_name);
end $$;

revoke all on function public.claim_name(text, text) from public;
revoke all on function public.player_rank(text, text) from public;
revoke all on function public.submit_score(text, text, text, int, int, int, int, int, jsonb) from public;
grant execute on function public.claim_name(text, text) to anon, authenticated;
grant execute on function public.player_rank(text, text) to anon, authenticated;
grant execute on function public.submit_score(text, text, text, int, int, int, int, int, jsonb) to anon, authenticated;
