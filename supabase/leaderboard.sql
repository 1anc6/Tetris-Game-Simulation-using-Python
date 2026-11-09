-- Stackfall leaderboard. Run once in the Supabase SQL editor.
create table if not exists public.scores (
  id bigint generated always as identity primary key,
  name text not null check (name ~ '^[A-Z0-9 _-]{1,12}$'),
  grp text not null default '' check (grp ~ '^[A-Z0-9]{0,12}$'),
  score int not null check (score between 1 and 100000000),
  lines int not null check (lines between 0 and 100000),
  level int not null check (level between 1 and 1000),
  created_at timestamptz not null default now()
);

alter table public.scores enable row level security;

drop policy if exists "anyone can read scores" on public.scores;
create policy "anyone can read scores" on public.scores
  for select to anon, authenticated using (true);

-- loose sanity check: blocks absurd scores for the lines cleared
drop policy if exists "anyone can add a plausible score" on public.scores;
create policy "anyone can add a plausible score" on public.scores
  for insert to anon, authenticated
  with check (score::bigint <= (lines + 1)::bigint * (lines + 1) * level * 3000);

-- players can only send these columns (no faking id or created_at), and never update/delete
revoke all on public.scores from anon, authenticated;
grant select on public.scores to anon, authenticated;
grant insert (name, grp, score, lines, level) on public.scores to anon, authenticated;

create index if not exists scores_grp_score on public.scores (grp, score desc);

-- each player's best score per group
create or replace view public.best_scores with (security_invoker = on) as
  select distinct on (grp, name) name, grp, score, lines, level, created_at
  from public.scores
  order by grp, name, score desc, created_at;

grant select on public.best_scores to anon, authenticated;
