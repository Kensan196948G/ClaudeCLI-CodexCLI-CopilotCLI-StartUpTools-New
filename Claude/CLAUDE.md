# ClaudeOS v4 Kernel

ClaudeOS Autonomous Development Organization

## Position In This Repository

This directory contains ClaudeOS-compatible policy documents and operating concepts.

These files are reference policies, not the source of truth for the repository implementation.

For this repository, precedence is:

1. root `CLAUDE.md`
2. current repository implementation in `scripts/main/`, `config/`, `docs/`
3. this `Claude/claudeos/` policy set

If a ClaudeOS policy conflicts with the current repository implementation, follow the root `CLAUDE.md` and the actual codebase.

## Current Repository Alignment

The current repository is a unified startup tool for:

- Claude Code
- Codex CLI
- GitHub Copilot CLI

Current execution is centered on:

- `start.bat`
- `scripts/main/Start-Menu.ps1`
- `scripts/main/Start-All.ps1`
- `scripts/main/Start-ClaudeCode.ps1`
- `scripts/main/Start-CodexCLI.ps1`
- `scripts/main/Start-CopilotCLI.ps1`

This means older assumptions such as DevTools-first workflows, tmux-first orchestration, mandatory CI loops, or fixed daily project rotation are not repository-wide requirements.

## Boot Sequence

Load core system:

- `claudeos/system/orchestrator.md`
- `claudeos/system/project-switch.md`
- `claudeos/system/token-budget.md`
- `claudeos/system/loop-guard.md`

Load executive layer:

- `claudeos/executive/ai-cto.md`
- `claudeos/executive/architecture-board.md`

Load management layer:

- `claudeos/management/scrum-master.md`
- `claudeos/management/dev-factory.md`

Load development loops:

- `claudeos/loops/monitor-loop.md`
- `claudeos/loops/build-loop.md`
- `claudeos/loops/verify-loop.md`
- `claudeos/loops/improve-loop.md`
- `claudeos/loops/architecture-check-loop.md`

Load CI system:

- `claudeos/ci/ci-manager.md`

Load evolution system:

- `claudeos/evolution/self-evolution.md`

## Applicability Rule

Apply these policies only when they fit the current task and repository state.

Examples:

- If no CI workflow exists locally, CI monitoring becomes optional.
- If the task is documentation-only, build-loop steps are not mandatory.
- If the repository is mid-migration, do not enforce legacy assumptions over current files.
- Do not create commits automatically unless explicitly requested.
