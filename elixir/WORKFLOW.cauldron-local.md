---
tracker:
  kind: local
  path: /media/user/data/projects2026/symphony/local/cauldron-board.json
  active_states: ["Todo", "In Progress"]
  terminal_states: ["Done", "Closed", "Cancelled", "Canceled", "Duplicate"]
polling:
  interval_ms: 10000
workspace:
  root: /media/user/data/projects2026/symphony-workspaces/cauldron
hooks:
  timeout_ms: 120000
  after_create: |
    git clone https://github.com/cauldron26/cauldron.git .
    git switch sprint-1-foundation
agent:
  max_concurrent_agents: 1
  max_turns: 4
codex:
  command: codex app-server
  approval_policy: never
  thread_sandbox: workspace-write
server:
  host: 127.0.0.1
  port: 4057
---

You are working on a local Symphony issue for the Cauldron repository.

Issue: {{ issue.identifier }}
Title: {{ issue.title }}

Description:
{{ issue.description }}

Rules:

- Work only inside the issue workspace created by Symphony.
- Create a branch for the issue before changing files.
- Keep changes focused on the issue description.
- Run the narrowest useful verification before reporting completion.
- Commit your work and leave a concise summary with the `local_tracker` tool.
- Move the issue to `Done` with the `local_tracker` tool only after the work is committed and verified.
