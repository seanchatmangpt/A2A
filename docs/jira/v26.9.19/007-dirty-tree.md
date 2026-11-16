# A2A: commit or clean uncommitted changes

- Standing: OPEN
- Created: 2026-09-19 (v26.9.19 gh survey wave)
- Source: working tree dirty at survey time
- Evidence: `git status --porcelain` → 156 path(s) (tracked-modified: 115, untracked: 41); sample:  D _build/default/28.3.dialyzer_warnings; D _build/default/rebar3_28.3_plt; D craftplan/a2a-agent/_build/default/plugins/.rebar3/rebar_compiler_erl/source_apps.dag;?? docs/yawl/api/;?? docs/yawl/archi

## Work to complete
- Review the 115 tracked-modified path(s); commit them as atomic pieces on a purpose branch, or revert what is transient.
- For the 41 untracked path(s): add intentional files to git and commit; gitignore or delete build artifacts/temp files.
- Note: this survey's ticket files under docs/jira/v26.9.19/ are intentionally uncommitted; include or exclude them deliberately in the commit plan.

## Acceptance
- `git status --porcelain` is clean (except items deliberately deferred and recorded here).

## History
- 2026-09-19 | OPEN | survey found dirty tree | 156 paths (T115/U41) | commit/clean pending
