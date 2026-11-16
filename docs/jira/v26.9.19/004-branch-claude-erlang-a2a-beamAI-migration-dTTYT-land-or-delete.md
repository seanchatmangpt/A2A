# A2A: land or delete remote branch `claude/erlang-a2a-beamAI-migration-dTTYT`

- Standing: OPEN
- Created: 2026-09-19 (v26.9.19 gh survey wave)
- Source: remote branch `claude/erlang-a2a-beamAI-migration-dTTYT` — not merged into `main`, no open PR
- Evidence: `git branch -r --no-merged origin/main` lists it; absent from `gh pr list` heads

## Work to complete
- Decide: open a PR (`gh pr create -R seanchatmangpt/A2A --head claude/erlang-a2a-beamAI-migration-dTTYT`) or delete (`git push origin --delete claude/erlang-a2a-beamAI-migration-dTTYT`).
- If superseded, delete; otherwise land through review.

## Acceptance
- After `git fetch --prune`, `git branch -r --no-merged origin/main` no longer lists `claude/erlang-a2a-beamAI-migration-dTTYT`.

## History
- 2026-09-19 | OPEN | survey found PR-less unmerged branch | claude/erlang-a2a-beamAI-migration-dTTYT | decision pending
