# IDE Extension Decisions Checklist

> **Lean manifests applied (2026-07-08).** Manifests in this directory are now the lean set. **Do not** run live `restore --prune` until editors are open on each target. When ready, per target:
>
> ```bash
> dotfiles ext restore <target>    # install lean set
> dotfiles ext restore <target> --prune   # remove extras not in manifest
> ```
>
> Or for all targets: `dotfiles ext restore all` then `dotfiles ext restore all --prune`.

**Source:** `docs/research/07-ide-extensions.md` §4–5, `docs/plan/plan4-ide-extensions.md` Part B  
**Purpose:** Confirm prune and add actions per target before running `dotfiles ext restore --prune` or targeted uninstall/install.

**Status:** User confirmed **apply lean on all targets** — all items below marked confirmed.

---

## Global — Prune (high confidence)

Remove unless you use the feature weekly.

### Flutter / Dart (VS Code only — not on Cursor-WSL)

- [x] `dart-code.dart-code`
- [x] `dart-code.flutter`

**Targets:** vscode-wsl, vscode-win

### Azure sprawl (keep core only)

Keep: `ms-azuretools.vscode-azureresourcegroups` and/or `ms-azuretools.azure-dev`, plus `ms-vscode.azurecli` if using Azure CLI from IDE.

- [x] `ms-azuretools.vscode-azureappservice`
- [x] `ms-azuretools.vscode-azurefunctions`
- [x] `ms-azuretools.vscode-azurestaticwebapps`
- [x] `ms-azuretools.vscode-azurestorage`
- [x] `ms-azuretools.vscode-azurevirtualmachines`
- [x] `ms-azuretools.vscode-azurecontainerapps`
- [x] `ms-azuretools.vscode-apimanagement`
- [x] `ms-azuretools.vscode-cosmosdb`
- [x] `ms-azure-load-testing.microsoft-testing`
- [x] `ms-azuretools.vscode-dev-azurecloudshell-helper`
- [x] `ms-azuretools.vscode-azure-github-copilot`
- [x] `ms-windows-ai-studio.windows-ai-studio`
- [x] `ms-vscode.vscode-node-azure-pack`

**Targets:** vscode-wsl, vscode-win, cursor-win (subset installed)

### Legacy / duplicate Docker

Keep only `ms-azuretools.vscode-containers`.

- [x] `ms-azuretools.vscode-docker`
- [x] `docker.docker`

**Targets:** all four

### Copilot / ChatGPT companions (Cursor has built-in AI)

- [x] `openai.chatgpt`
- [x] `ms-vscode.vscode-copilot-vision`
- [x] `ms-vscode.vscode-websearchforcopilot`
- [x] `ms-azuretools.vscode-azure-github-copilot`
- [x] `ms-vscode.vscode-chat-customizations-evaluations`

**Targets:** vscode-wsl, vscode-win, cursor-wsl, cursor-win (where installed)

### Java stack (if not writing Java)

- [x] `redhat.java`
- [x] `vscjava.vscode-java-debug`
- [x] `vscjava.vscode-java-test`

**Targets:** vscode-wsl, vscode-win, cursor-win

### HTML preview cluster (keep ≤1 or zero)

- [x] `ritwickdey.liveserver`
- [x] `negokaz.live-server-preview`
- [x] `george-alisson.html-preview-vscode`
- [x] `searking.preview-vscode`

**Targets:** per inventory (see per-target sections below)

### Redundant XML

- [x] `dotjoshjohnson.xml` (superseded by `redhat.vscode-xml`)

**Targets:** vscode-wsl, vscode-win

### Git UI overlap (keep ≤1 history/blame tool)

- [x] `donjayamanne.githistory`
- [x] `mhutchie.git-graph`
- [x] `waderyan.gitblame`

**Targets:** all four (where installed)

### GitLab triple (keep official `gitlab.gitlab-workflow`)

- [x] `jameswain.gitlab-pipelines`
- [x] `jasonn-porch.gitlab-mr`

**Targets:** all four (where installed)

### Bash meta-pack (keep individual extensions)

- [x] `pinage404.bash-extension-pack`

**Targets:** all four (where installed)

### Web front-end noise (DevOps/infra focus)

- [x] `ecmel.vscode-html-css`
- [x] `hwencc.html-tag-wrapper`
- [x] `sidthesloth.html5-boilerplate`
- [x] `xabikos.javascriptsnippets`
- [x] `wix.vscode-import-cost`

**Targets:** vscode-wsl, vscode-win, cursor-win (where installed)

### Misc low-use

- [x] `formulahendry.code-runner`
- [x] `m4ns0ur.base64`
- [x] `mccarter.start-git-bash`
- [x] `wscats.cors-browser`
- [x] `sumitnalavade.vscode-readme-editor`
- [x] `spmeesseman.vscode-taskexplorer`

**Targets:** per inventory

### Optional / situational

- [x] `figma.figma-vscode-extension` — only if doing design handoff
- [x] `ms-edgedevtools.vscode-edge-devtools` — web debugging, not core DevOps
- [x] `atlassian.atlascode` — only if actively on Jira/Bitbucket (GitLab primary)

**Targets:** per inventory

---

## Medium confidence — Prune (consolidate)

- [x] `ms-kubernetes-tools.vscode-aks-tools` — keep only if managing AKS
- [x] `ms-vscode-remote.vscode-remote-extensionpack` — meta-pack; uninstall if children present
- [x] `ms-toolsai.jupyter` (+ satellite extensions) — uninstall main if notebooks not used in IDE

**Targets:** vscode-win, cursor-win (where installed)

---

## Global — Add (missing, high value)

- [x] `hashicorp.terraform` — IaC authoring, validation, module navigation
- [x] `amazonwebservices.aws-toolkit-vscode` — Lambda, CloudWatch, SSM, ECS/EKS
- [x] `usernamehw.errorlens` — inline diagnostics for Python/YAML/Terraform
- [x] `tamasfe.even-better-toml` — pyproject.toml, Cargo, tool configs
- [x] `eamodio.gitlens` — deep blame/history (already on vscode-win; add to WSL targets if desired)
- [x] `googlecloudtools.cloudcode` — **optional**, only if actively on GCP *(skipped — not in any manifest)*

**Targets:** add to cursor-wsl, cursor-win, vscode-wsl; vscode-win already has GitLens

---

## Per-target notes

### vscode-wsl (82 → 45 extensions)

**Pruned:** Flutter/Dart, full Azure sprawl, legacy Docker, Copilot companions, Java, Live Server, HTML preview, git overlap, GitLab triple, bash pack, web front-end noise, misc low-use, Figma, task explorer, AKS tools.

**Added:** terraform, AWS toolkit, error lens, TOML, GitLens.

**Kept VS Code-specific (do not sync to Cursor):** `ms-python.vscode-pylance`, `ms-vscode.powershell`

### cursor-wsl (49 → 39 extensions)

**Pruned:** legacy Docker, third-party Docker, Copilot websearch, git overlap (3), GitLab triple (2), bash pack, misc low-use (5), HTML preview.

**Added:** terraform, AWS toolkit, error lens, TOML, GitLens.

**Canonical list:** `cursor-core.txt` (~39 extensions)

### vscode-win (114 → 63 extensions)

**Pruned:** all global categories above plus AKS tools, remote meta-pack, Jupyter stack.

**Kept Windows-remote essentials:** `ms-vscode-remote.remote-wsl`, `remote-ssh`, `remote-containers`, `remote-ssh-edit`, `remote-explorer`, `remote-repositories`, `remote-server`.

### cursor-win (96 → 40 extensions)

**Pruned:** Azure subset, Docker duplicates, Copilot/ChatGPT, Java, HTML preview cluster, git overlap, GitLab triple, bash pack, web front-end noise, misc low-use, Figma, Edge devtools, Atlassian, Jupyter stack, remote meta-pack.

**Kept Cursor-specific:** `anysphere.cursorpyright`, `anysphere.remote-wsl`

**Restore from:** `cursor-core.txt` + `anysphere.remote-wsl`

---

## After confirmation

1. ~~Apply confirmed **adds** via `dotfiles ext restore cursor-wsl` (from updated `cursor-core.txt`) or manual install.~~ **Done in manifests** — run restore when editors are open.
2. Apply confirmed **prunes** via `dotfiles ext restore --prune` per target when ready.
3. Re-run `dotfiles ext backup` to refresh manifests after live changes.
4. Copy `dotfiles/templates/vscode-extensions.json` to repo `.vscode/extensions.json` for team recommendations.
