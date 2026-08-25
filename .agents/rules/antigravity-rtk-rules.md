# Output Compression — Agent Reference

Reduce shell-output tokens returned to the model context. Choose the method your agent supports.

## Universal rules (all agents)

- Noisy command → compress it.
- Short readable output → run it direct. Never add overhead for no gain.
- Exact evidence needed → always skip compression (`rtk proxy` / raw pipe).

## RTK (Gemini / Antigravity CLI)

**RTK** = built-in output filter. Rewrites noisy command output before it enters model context.

```bash
rtk git status
rtk cargo test
rtk rg "pattern" src/
rtk go test ./...
rtk docker ps
rtk gh pr list
```

Meta:
```bash
rtk gain              # Show token savings this session
rtk gain --history    # Per-command history
rtk discover          # Find missed RTK opportunities
rtk proxy <cmd>       # Run raw (no filtering — for debugging)
rtk powershell <cmd>  # PowerShell command with RTK filtering
```

## Equivalent for other agents

| Agent | Equivalent |
|---|---|
| Claude Code (CLI) | `--compact` flag; or pipe `\| head -n 80` |
| GPT / Codex | `\| Select-Object -First 50` in PowerShell |
| Cursor | Use built-in diff view; don't paste raw `git diff` |
| Any | `git diff --stat` instead of `git diff` for summaries |

RTK reduces shell-output tokens, not total model cost. Measure impact with `rtk gain`.
<!-- ponytail: RTK-only tool; ceiling is other-agent users get no compression tooling; upgrade: this table grows as agents add native filters -->

