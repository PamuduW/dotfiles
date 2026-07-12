# AGENTS.md

## Environment

- **OS:** WSL2 Ubuntu
- **Shell:** bash
- **Primary agents:** Cursor, Claude Code, Codex, GitHub Copilot
- **Bootstrap home:** `$AGENT_BOOTSTRAP_HOME` (agent_bootstrap repo on PATH)

Invoke skills in Agent chat by typing `/<skill-name>`.

**Pick 2–4 skills per session by phase — do not load all at once.**

Skills below match `skills.sources.yaml` (enabled upstreams installed via `./install.sh skills install` in the sibling `agent_bootstrap` clone).

### Methodology

| Skill | Description |
|---|---|
| `brainstorming` | Explore options and trade-offs before committing to a direction. |
| `council` | Parallel subagent exploration and synthesis for multi-area codebase review. |
| `grilling` | Stress-test a plan or design before building; matches Interaction Rules below. |
| `recursive-decomposition` | Partition large inputs (10+ files, 50k+ tokens) via subagents and aggregation. |
| `yagni` | Simplest solution that works; resist premature complexity. |
| `karpathy-guidelines` | Think before coding; surgical changes only; verifiable success criteria. |
| `best-practices-research` | Live web recon on current practices before non-trivial implementation. |
| `literature-review` | Structured review of papers, docs, and prior art with citations. |

### Architecture

| Skill | Description |
|---|---|
| `architecture-decision-records` | Capture architectural decisions as lightweight ADRs with rationale. |
| `domain-modeling` | Build and sharpen domain terminology and ubiquitous language. |
| `codebase-design` | Deep-module vocabulary for interfaces, seams, and testability. |
| `codebase-onboarding` | Structured onboarding guide for an unfamiliar codebase. |
| `improve-codebase-architecture` | Scan for deepening opportunities; visual report and review. |
| `decision-mapping` | Turn a loose idea into sequenced investigation tickets. |

### Planning

| Skill | Description |
|---|---|
| `writing-plans` | Turn requirements into phased, actionable implementation plans. |
| `implement-plan` | Router: council + best-practices research, implement, then yagni pass. |
| `prototype` | Throwaway prototype to flesh out design (CLI or UI variations). |
| `to-prd` | Synthesize conversation into a PRD; publish to issue tracker when configured. |
| `to-issues` | Break a plan or PRD into independently grabbable tracker issues. |
| `triage` | Move issues through triage roles on the project issue tracker. |
| `setup-matt-pocock-skills` | Scaffold tracker, triage labels, and domain docs for planning skills. |
| `executing-plans` | Work through a plan incrementally with checkpoints. |
| `subagent-driven-development` | Delegate implementation slices to focused subagents. |

### Quality

| Skill | Description |
|---|---|
| `tdd` | Test-driven development via public interfaces; red-green-refactor. |
| `test-driven-development` | Red-green-refactor cycle; tests before implementation. |
| `diagnosing-bugs` | Diagnosis loop for hard bugs and performance regressions. |
| `owasp` | Security review against OWASP guidance. |
| `explain-code` | Scannable code explanation with TL;DR and small examples. |

### Docs / handoff

| Skill | Description |
|---|---|
| `document` | Create or update durable repo documentation verified against code. |
| `handoff` | Compact session handoff to `docs/handoffs/CURRENT.md` for continuation. |
| `pitstop` | Action-first, compressed replies with numbered steps and lap restatement. |

### Implementation / DevOps (load on demand)

| Skill | Description |
|---|---|
| `kubernetes` / `k8s` | Cluster manifests, deployments, and operational patterns. |
| `kubernetes-specialist` | Deep K8s troubleshooting, networking, and production hardening. |
| `terraform` | IaC modules, state, and environment provisioning. |
| `github-actions` / `gitlab-ci` | CI/CD pipelines, workflows, and release automation. |
| `devops-engineer` | Cross-cutting infra, observability, and delivery practices. |

### Interaction Rules (how AI must behave in this project)

Never agree with me by default. Your first instinct should be to stress-test what I've said, not validate it. If I present an idea, strategy, or opinion, your job is to find the weakest point before you affirm anything. No glazing. Don't tell me something is "great", "brilliant", or "really smart" unless you can point to specific, concrete reasons why - and even then, lead with what's wrong or missing first. Compliments without substance are noise. Don't echo my framing back to me. If I say "I think X is the move," don't start your response with "X is definitely the move" or "That makes a lot of sense". Instead, start by asking yourself: what am I not seeing? What's the counter-argument? What would someone who disagrees say, and are they right? When you do agree, earn it. Agreement should come after you've genuinely pressure-tested the idea - not as a default starting position. If you agree, say why in a way that adds something I didn't already say. Be direct and concise. Skip the warm-up sentences. Don't pad responses with filler affirmations. Get to the point. If the answer is "no" or "this won't work", say that in the first sentence. Call out bad logic, weak assumptions, and blind spots immediately even if I seem confident or excited. Especially then. The more certain I sound, the more I need pushback. If you catch yourself about to start a response with "That's a great point" or "You're absolutely right" - stop and rewrite. Start with the most useful thing you can say instead.

## Project overlay

Scaffolded from `agent_bootstrap/base/` via `agentboot`. Canonical templates stay in the sibling `agent_bootstrap` repo; this file is the live dotfiles instance with project notes below.

## Project

**Purpose:** WSL Debian/Ubuntu dotfiles — interactive installer, GNU Stow symlinks, and integration with sibling `agent_bootstrap` for skills and agent scaffolding.

**Stack:** bash (installer + TUI menus), GNU Stow (`bash/`, `bin/`, `readline/` packages), `dotfiles` CLI (`bin/bin/dotfiles`).

**Layout:**

| Path | Role |
|------|------|
| `install.sh` | Shim → `scripts/install.sh` (boot menu + component install) |
| `scripts/install.sh` | Real installer; logs to `log/` |
| `scripts/lib/` | TUI (`menu_simple`, `report_table`), component registry |
| `scripts/menus/` | Main, initial setup, update, agents submenus |
| `bin/bin/dotfiles` | `update`, `upgrade`, `restow`, `menu` |
| `packages/packages.txt` | Apt components with `@tag` sections |
| `bash/.bashrc` | Stowed shell config; sources `agent_bootstrap_paths.sh` |

**Sibling repo:** `agent_bootstrap/` next to this repo (`../agent_bootstrap`). Agents menu clones, bootstraps, and links `agentboot` from there. `AGENT_BOOTSTRAP_HOME` resolves to the sibling when `install.sh` exists.

**Commands:**

```bash
./install.sh                    # interactive boot menu
dotfiles menu                   # same (after stow)
dotfiles update && dotfiles upgrade
find scripts -name '*.sh' -print0 | xargs -0 -n1 bash -n   # shell syntax check
```

**Conventions:**

- Stow only deploys `bash`, `bin`, `readline` — not agent policy files (those come from `agent_bootstrap`).
- Menu changes: extend `scripts/lib/menu_*.sh` and wire in `scripts/menus/`.
- Component installs: registry in `scripts/lib/components/`; keep probes honest for status tables.
- Prefer minimal diffs; match existing bash patterns (`set -euo pipefail`, `shellcheck`).
