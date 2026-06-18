# Safety rules

These rules are binding for any agent (human or automated) using
agent-delegation. They mirror the Safety section of `SKILL.md` and are the only
authoritative copy — no extra delegation rules live in plugin metadata.

## Scope: what this tool does NOT do

- **No board.** No task/issue/project board, no inbox/ready/in-progress states.
- **No GitHub sync.** It never reads or writes issues, labels, or projects.
- **No PR automation.** It never opens, reviews, or merges pull requests.
- **No remote / multi-machine / scheduled execution.** Local only.

Dispatch is **prompt-based only**. There is no routing by issue id, board id,
task id, or label.

## Commit / merge discipline

- Worktree agents may **commit locally** on their `adm-<uuid[:8]>` branch.
- **Pushing and merging are human actions.** Do not automate `git push`,
  `gh pr create`, or `gh pr merge` through this tool.
- Never silently delete a worktree that holds work you did not create — surface
  it and ask.

## Trust model

- Prompts and harnesses are **trusted local shell input**, `eval`-ed without a
  sandbox. Only pass commands you would run yourself.
- The repository does not isolate or restrict shell execution.
- Keep everything on your own machine; do not expect remote support.

## Operating posture

- Keep prompts explicit and short.
- Use `worktree` when the change must be isolated from the main checkout.
- Bound long runs with `timeout_sec`.
- Prefer the narrowest runtime and the minimal backend that can do the job.
