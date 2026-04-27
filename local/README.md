# Local Symphony Board

This directory is a non-Linear task source for the local Symphony checkout.

Run Symphony with:

```bash
cd /media/user/data/projects2026/symphony/elixir
./bin/symphony --i-understand-that-this-will-be-running-without-the-usual-guardrails --port 4057 ./WORKFLOW.cauldron-local.md
```

The dashboard will be available at:

```text
http://127.0.0.1:4057/
```

Tasks live in `cauldron-board.json` under the `issues` array. Set an issue to
`Todo` or `In Progress` to make it eligible. Set it to `Done`, `Closed`,
`Cancelled`, `Canceled`, or `Duplicate` to stop work and mark it terminal.

Start a fresh local board with:

```bash
cp /media/user/data/projects2026/symphony/local/cauldron-board.example.json \
  /media/user/data/projects2026/symphony/local/cauldron-board.json
```
