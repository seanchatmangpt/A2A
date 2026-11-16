# A2A: land or delete remote branch `claude/gcp-marketplace-infrastructure-uw8Ns`

- Standing: OPEN
- Created: 2026-09-19 (v26.9.19 gh survey wave)
- Source: remote branch `claude/gcp-marketplace-infrastructure-uw8Ns` — not merged into `main`, no open PR
- Evidence: `git branch -r --no-merged origin/main` lists it; absent from `gh pr list` heads

## Work to complete
- Decide: open a PR (`gh pr create -R seanchatmangpt/A2A --head claude/gcp-marketplace-infrastructure-uw8Ns`) or delete (`git push origin --delete claude/gcp-marketplace-infrastructure-uw8Ns`).
- If superseded, delete; otherwise land through review.

## Acceptance
- After `git fetch --prune`, `git branch -r --no-merged origin/main` no longer lists `claude/gcp-marketplace-infrastructure-uw8Ns`.

## History
- 2026-09-19 | OPEN | survey found PR-less unmerged branch | claude/gcp-marketplace-infrastructure-uw8Ns | decision pending
