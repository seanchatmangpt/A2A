# A2A migration plan v26.11.16

Standing: UNVERIFIED

## Identity
- Path: /Users/sac/A2A
- Remote: https://github.com/seanchatmangpt/A2A (fork of a2aproject/A2A)
- Branch: main@305385c (upstream origin/main)
- Last commit: 2026-08-23 ("docs: position A2A in the Forward Deployment OS (#2)")
- Commits: 500; size: 233 MB
- Languages/build: Erlang (rebar3, erlang.mk), Python (elrmcp_bridge, .ruff.toml), mkdocs docs,
  ggen.toml; no CLAUDE.md
- Nested repos: none (`.erlang.mk.build` is an unmapped submodule gitlink, see Observed state)

## Observed state
- Dirty: 115 tracked, untracked: 82 (census). Grouped by top-level path:
  - craftplan/ (79): mostly ` D` deletions of committed `_build/default/plugins/pc/*` artifacts
  - erlang/a2a_erl/src/*.erl, include/yawl_types.hrl (52): modified YAWL/CPN sources
  - docs/ (20), elrmcp_bridge/src/metrics.py (modified), _build/ (2 deleted dialyzer files)
  - erl_crash.dump deleted at root and craftplan/mcp-server (crash dumps were committed)
- Ahead 0 / behind 1 upstream. Stash count: 490 (census) — extremely large.
- Unpushed local branches: 0.
- Build/dep dirs: `_build/` artifacts were committed to git (now showing as deleted);
  no live `_build`/`deps` dirs of note at root.
- Submodules: `git submodule status` fails: "no submodule mapping found in .gitmodules for
  path '.erlang.mk.build'" — a gitlink without a .gitmodules entry.

## What it is
Sean's fork of the Agent2Agent (A2A) protocol repo, extended with a pure-Erlang YAWL workflow
implementation and REST API (`erlang/a2a_erl`), a craftplan agent, and an elrmcp Python bridge.
README is the upstream A2A README, so the fork's own purpose lives in the commit log, not docs.

## Classification
WARM (census agrees: last real commit 2026-08-23, but 115 dirty files of Erlang source edits).

## Migration risk
- Uncommitted edits to 52 Erlang source files + metrics.py + docs (real work, not noise).
- 490 stash entries of unknown content — history that would be lost on a fresh clone.
- Broken gitlink `.erlang.mk.build` (no .gitmodules mapping) may break clone/checkout steps.
- No .env/.db/data dirs found at top level.
Rating: HIGH (uncommitted source + massive stash backlog).

## Recommended action
COMMIT-PUSH

1. Review source edits: `git -C /Users/sac/A2A diff --stat -- erlang elrmcp_bridge docs`.
2. Commit the real work on a branch:
   `git checkout -b wip/pre-migration-2026-11-16 && git add erlang elrmcp_bridge docs &&
   git commit -m "wip: pre-migration snapshot"`.
3. Commit the `_build`/`erl_crash.dump` deletions separately (they should never have been
   tracked): `git add -A craftplan/_build _build erl_crash.dump craftplan/mcp-server/erl_crash.dump
   && git commit -m "chore: drop committed build artifacts"`.
4. DECISION: 490 stashes. `git stash list > /Volumes/archive/A2A-stashes.txt`, then bundle the
   whole repo so nothing is lost: `git bundle create /Volumes/archive/A2A-full.bundle --all`
   plus `tar czf /Volumes/archive/A2A-dotgit.tgz -C /Users/sac/A2A .git` (stash refs travel
   only via the .git tarball).
5. Fix the orphan gitlink: `git rm --cached .erlang.mk.build` and commit, or add it to
   `.gitmodules`. DECISION: is `.erlang.mk.build` needed?
6. `git push -u origin wip/pre-migration-2026-11-16`.
7. On the new machine: clone; do not rsync the working tree.

## First commands on the new machine
`git clone https://github.com/seanchatmangpt/A2A && cd A2A && rebar3 compile` (Erlang) and
`ruff check elrmcp_bridge` (Python). Stated, not run.

## See Also
- ../v26.9.19/
- /Users/sac/docs/jira/v26.11.16/README.md
