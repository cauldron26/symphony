---
tracker:
  kind: memory
  active_states: ["Todo", "In Progress"]
  terminal_states: ["Done", "Closed", "Cancelled", "Canceled", "Duplicate"]
polling:
  interval_ms: 3000
workspace:
  root: /media/user/data/projects2026/symphony-workspaces/symphony-cauldrons
hooks:
  timeout_ms: 300000
  after_create: |
    issue_id="$(basename "$PWD" | tr '[:upper:]' '[:lower:]')"
    issue_number="$(printf '%s\n' "$issue_id" | sed -n 's/^gh-\([0-9][0-9]*\).*/\1/p')"
    seed_branch=""
    if [ -n "$issue_number" ] && command -v gh >/dev/null 2>&1; then
      issue_body="$(gh issue view "$issue_number" --repo cauldron26/cauldron --json body --jq .body 2>/dev/null || true)"
      seed_branch="$(printf '%s\n' "$issue_body" | sed -n 's/^Symphony seed branch:[[:space:]]*//p' | head -n 1 | tr -d '\r')"
      if [ "$seed_branch" = "pending" ]; then
        seed_branch=""
      fi
    fi
    branch="work/symphony-cauldrons/${issue_id}"
    git clone git@github.com:cauldron26/cauldron.git .
    git config user.name "Symphony Cauldrons"
    git config user.email "symphony-cauldrons@example.invalid"
    if [ -n "$seed_branch" ]; then
      if ! git ls-remote --exit-code --heads origin "$seed_branch" >/dev/null 2>&1; then
        printf 'Issue declares Symphony seed branch, but the branch was not found: %s\n' "$seed_branch" >&2
        exit 1
      fi
      git fetch origin "$seed_branch"
      git switch --track -c "$seed_branch" "origin/$seed_branch"
      branch="$seed_branch"
    else
      git switch sprint-1-foundation
      git switch -c "$branch"
    fi
    printf '%s\n' "$branch" > .symphony-branch
    printf '%s\n' .symphony-branch .codex/ .git-codex/ 'unity-*.log' >> .git/info/exclude
agent:
  max_concurrent_agents: 1
  max_turns: 4
codex:
  command: /home/user/.local/bin/codex --model gpt-5.5 app-server
  approval_policy: never
  thread_sandbox: danger-full-access
  turn_sandbox_policy:
    type: dangerFullAccess
  read_timeout_ms: 1000
  turn_timeout_ms: 900000
  stall_timeout_ms: 900000
server:
  host: 127.0.0.1
  port: 4062
---

You are working in `symphony-cauldrons`, the local Cauldron engineering workflow.
GitHub issues are the source of truth for this workflow. Symphony is being invoked once by the local self-hosted GitHub Actions runner for the specific issue below; there is no JSON task queue, no webhook listener, and no polling fallback in this run.

Issue: {{ issue.identifier }}
Title: {{ issue.title }}

Description:
{{ issue.description }}

Rules:

- Work only inside this issue workspace.
- The workspace is a fresh SSH clone of `git@github.com:cauldron26/cauldron.git`.
- If the issue description declares `Symphony seed branch: <branch>`, the workspace starts from that existing remote branch. Otherwise it starts from `sprint-1-foundation`.
- The workspace hook already created the task branch and wrote its name to `.symphony-branch`.
- Stay on that existing task branch. Do not work directly on `main` or `sprint-1-foundation`.
- Use shell `git` and `gh` commands for GitHub work. Do not use GitHub plugins or GitHub skills for this run.
- Keep the change scoped to the issue.
- Verify that Unity generated folders such as `control-plane/Library/`, `control-plane/Temp/`, `builder/Library/`, and `builder/Temp/` are ignored by Git.
- Do not launch Unity unless the task changes Unity source or project settings. If Unity is needed, derive the editor version from `<projectPath>/ProjectSettings/ProjectVersion.txt`, use `/home/user/Unity/Hub/Editor/<version>/Editor/Unity`, use the Unity project path named by the issue, and write logs under the workspace.
- Run the narrowest useful verification before reporting completion.
- For UI iteration issues with `.symphony-requests/gh-*/request.json`, render the revised UI at 1280x720 after the final edit, save the approved result as `after.png` in that same request directory, and include `after.png` in the commit. The completion comment and PR body must include the raw GitHub URL for `after.png`.
- Commit the change on the task branch.
- Push the task branch to `origin`.
- Create a draft PR against `sprint-1-foundation` with `gh pr create` after the branch is pushed.
- Comment on the GitHub issue with the branch name, commit hash, PR URL, pushed remote ref, verification commands, and final UI screenshot URL when the task is a UI iteration.
- Do not close the issue directly. Let the PR merge close or resolve it unless the issue explicitly asks for a different GitHub state transition.
- UI generation and UI iteration work should run on GPT-5.5. If a request bundle includes `preferred_model`, honor it and do not downgrade to a mini model.

Execute this as a compact command-driven run:

1. Inspect the current branch and `.symphony-branch` once.
2. Make exactly the change requested by the issue.
3. If the issue changes Unity source or project settings, launch Unity in batchmode with the editor version from the target project's `ProjectVersion.txt`. Iteration is allowed: after a failed Unity run, inspect the log, make a targeted fix, and rerun Unity when that is the narrowest useful verification. Stop after three Unity launches for one issue unless the issue explicitly authorizes more.
4. If this is a UI iteration, render the final approved UI, write the image to `.symphony-requests/gh-*/after.png`, and include that file in `<changed-files>`.
5. Run this verification and publish sequence, replacing `<changed-files>` with the files intentionally changed for the issue and replacing only the commit message text if the issue asks for a more specific message:

```bash
branch="$(cat .symphony-branch)"
test "$(git branch --show-current)" = "$branch"
git check-ignore -v control-plane/Library/ control-plane/Temp/ builder/Library/ builder/Temp/
git diff --check
git add <changed-files>
git diff --cached --check
git commit -m "Complete {{ issue.identifier }}"
git push -u origin "$branch"
git ls-remote --exit-code --heads origin "$branch"
git rev-parse HEAD
```

6. Create a draft PR and add a GitHub issue completion comment. For UI iterations, compute `after_url="https://raw.githubusercontent.com/cauldron26/cauldron/$commit/.symphony-requests/gh-<number>/after.png"` after the commit and include it in both the PR body and issue comment:

```bash
pr_url="$(gh pr create --draft --base sprint-1-foundation --head "$branch" --title "Complete {{ issue.identifier }}: {{ issue.title }}" --body "Work for {{ issue.url }}

Final UI screenshot: <after_url when applicable>")"
commit="$(git rev-parse HEAD)"
gh issue comment "{{ issue.url }}" --body "Branch: $branch
Commit: $commit
PR: $pr_url
Final UI screenshot: <after_url when applicable>
Verification: <commands run and result>"
```

If any command in the sequence fails, stop and add a GitHub issue comment with the failing command, the error, and the current workspace branch. Do not close the issue.
