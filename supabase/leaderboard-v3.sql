-- Stackfall leaderboard v3: one row per game.
-- Run once in the Supabase SQL editor, after leaderboard-v2.sql.
--
-- The game sends an id with every save (gid). A retry after a dropped connection,
-- or a later auto save of the same game, now updates that game's row (only if the
-- score went up) instead of adding another one. Older versions of the game that
-- don't send an id still work and add rows as before.

alter table public.scores add column if not exists gid bigint;
create unique index if not exists scores_name_gid on public.scores (name, gid);

-- the old 9-argument version would clash with the new one when called by name
drop function if exists public.submit_score(text, text, text, int, int, int, int, int, jsonb);

-- ---- add a score. p_log has one entry per line clear: [rows, points, level, combo, chain]
create or replace function public.submit_score(
  p_name text, p_secret text, p_mode text, p_score int, p_lines int, p_level int,
  p_ms int, p_pieces int, p_log jsonb, p_gid bigint default null)
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
  -- the same save arriving again (a retry): nothing to do, just answer
  if p_gid is not null and exists (select 1 from scores where name = p_name and gid = p_gid and score >= p_score) then
    return player_rank(p_mode, p_name);
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

  -- a game saved before (auto save, then game over) keeps one row, raised to the new score
  insert into scores as s (name, grp, mode, score, lines, level, ms, pieces, gid)
  values (p_name, '', p_mode, p_score, p_lines, p_level, p_ms, p_pieces, p_gid)
  on conflict (name, gid) do update
    set score = excluded.score, lines = excluded.lines, level = excluded.level,
        ms = excluded.ms, pieces = excluded.pieces, created_at = now()
    where s.score < excluded.score;
  return player_rank(p_mode, p_name);
end $$;

revoke all on function public.submit_score(text, text, text, int, int, int, int, int, jsonb, bigint) from public;
grant execute on function public.submit_score(text, text, text, int, int, int, int, int, jsonb, bigint) to anon, authenticated;
