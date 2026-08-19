# RTK - Rust Token Killer (Google Antigravity)

**Usage**: Token-optimized CLI proxy for shell commands.

## Rule

Use `rtk` for supported commands with noisy output. Keep short, readable
commands direct. Do not blindly prefix every command: filtering can hide
evidence and adds no useful savings for small output.

Examples:

```bash
rtk git status
rtk cargo test
rtk rg "pattern" src/
rtk go test ./...
rtk docker ps
rtk gh pr list
```

## Meta Commands

```bash
rtk gain              # Show token savings
rtk gain --history    # Command history with savings
rtk discover          # Find missed RTK opportunities
rtk proxy <cmd>       # Run raw (no filtering, for debugging)
```

## Selection

- Noisy command: `rtk <command>`.
- Short PowerShell read: direct `Get-Content`, `rg`, or targeted check.
- Exact evidence: `rtk proxy <command>`.
- PowerShell command needing RTK filtering: `rtk powershell <command>`.

RTK reduces shell-output tokens, not total model cost. Verify impact with
`rtk gain` and `rtk gain --history`.
