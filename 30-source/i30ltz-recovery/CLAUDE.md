# Automatic checkpoints for Claude mobile/cloud

This repository has command hooks in `.claude/settings.json`. In a single-repository
Claude cloud session, they save eligible changes after Write/Edit/Bash tools and
retry pushes at session start/resume, Stop, StopFailure (including rate-limit
errors), and PreCompact. They use Git, not model
API calls. Keep the session on its assigned `claude/*` branch; never force-push or
switch to main to work around a failed checkpoint. Existing staged changes and
Git operations are left alone. A checkpoint is a backup, not proof of passing tests.

Before finishing, run the relevant tests, commit any intentionally staged work,
and confirm the latest commit is on GitHub. Read `.git/cloud-checkpoint-status.json`
for the last successful push (its hash can be stale after a later failure). Report
any pending push, excluded files, or test failures honestly. Open a PR when work
is ready; don't merge unfinished task branches automatically.

Local LUCILLE drive sync reconciles this repository's main every ten minutes.
Cloud task branches are fetched locally for safekeeping but only merged into main
after review. These hooks do not retroactively enter older cloud sessions. They
cannot run while an environment is suspended, expired, or has no GitHub access.
Multi-repository Claude cloud sessions do not load repository hooks; use separate
sessions for Lucille Assistant and Recovery OS.
