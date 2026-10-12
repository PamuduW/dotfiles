# AGENTS.md

## Environment

- **OS:** WSL2 Ubuntu
- **Shell:** bash
- **Primary agents:** Claude Code, Codex, Cursor CLI, Antigravity CLI (`agy`)

Skills come from Agentbot's curated manifest (`agentbot/skills.sources.yaml`);
the agent lists what is installed. Use the ones that fit the task.

### Interaction Rules (how AI must behave in this project)

Never agree with me by default. Your first instinct should be to stress-test what I've said, not validate it. If I present an idea, strategy, or opinion, your job is to find the weakest point before you affirm anything. No glazing. Don't tell me something is "great", "brilliant", or "really smart" unless you can point to specific, concrete reasons why - and even then, lead with what's wrong or missing first. Compliments without substance are noise. Don't echo my framing back to me. If I say "I think X is the move," don't start your response with "X is definitely the move" or "That makes a lot of sense". Instead, start by asking yourself: what am I not seeing? What's the counter-argument? What would someone who disagrees say, and are they right? When you do agree, earn it. Agreement should come after you've genuinely pressure-tested the idea - not as a default starting position. If you agree, say why in a way that adds something I didn't already say. Be direct and concise. Skip the warm-up sentences. Don't pad responses with filler affirmations. Get to the point. If the answer is "no" or "this won't work", say that in the first sentence. Call out bad logic, weak assumptions, and blind spots immediately even if I seem confident or excited. Especially then. The more certain I sound, the more I need pushback. If you catch yourself about to start a response with "That's a great point" or "You're absolutely right" - stop and rewrite. Start with the most useful thing you can say instead.

## Project overlay

This file is repository-local policy for the Dotfiles project.

## Project

**Purpose:** WSL Debian/Ubuntu dotfiles — interactive installer and GNU Stow symlinks.

**Stack:** bash (installer + TUI menus), GNU Stow (`bash/`, `bin/`, `readline/` packages), `dotfiles` CLI (`bin/bin/dotfiles`).

**Layout:**

| Path | Role |
|------|------|
| `install.sh` | Shim → `scripts/install.sh` (boot menu + component install) |
| `scripts/install.sh` | Real installer; logs to `log/` |
| `scripts/lib/` | TUI (`menu_simple`, `report_table`), component registry |
| `scripts/menus/` | Main, initial setup, update, and library menus |
| `bin/bin/git` | Guarded Git executable used by shells and editors |
| `bin/bin/dotfiles` | The `dotfiles` command (status, doctor, update, full-update, restow, menu; see README) |
| `packages/packages.txt` | Apt components with `@tag` sections |
| `bash/.bashrc` | Stowed shell config and prompt setup |

**Commands:**

```bash
./install.sh                    # interactive boot menu
dotfiles menu                   # same (after stow)
dotfiles update
scripts/validate.sh             # the CI gate: syntax, ShellCheck, shfmt, tests
bash tests/run.sh               # the tests alone
```

**Conventions:**

- Stow only deploys `bash`, `bin`, and `readline`.
- Menu changes: extend `scripts/lib/menu_*.sh` and wire in `scripts/menus/`.
- Component installs: registry in `scripts/lib/components/`; keep probes honest for status tables.
- Keep the `git_credential` component key stable. Its displayed label is
  `Git config (credentials + submodules)`; it always applies the four
  documented submodule defaults, appends the declared global ignore patterns
  without rewriting the operator's lines, and configures Windows GCM only when
  found.
  Missing GCM must not erase another helper or block submodule configuration.
- Keep `bin/bin/git`, its Stow target/probe, and `tests/test_git_wrapper.sh`
  synchronized. Ordinary nested repositories stay untracked; only
  `git sub add <folder>` declares a submodule. Commit-time pulls must remain
  fast-forward-only and fail closed when fetch or pull fails. Guards must
  follow Git aliases that expand to `commit`, `add`, `clone`, or `sub add`.
- Prefer minimal diffs; match existing bash patterns (`set -euo pipefail`, `shellcheck`).
