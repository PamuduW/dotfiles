# WSL Bash dotfiles (GNU Stow)

This repo bootstraps a consistent Bash environment on Debian/Ubuntu (especially WSL distros) using **GNU Stow** symlinks.

## What you get

- Managed dotfiles via **GNU Stow** (symlink-based “install”).
- A custom Bash prompt showing:
  - time (`\t`), `user@host`, working directory
  - git branch (or short commit hash)
  - git status markers: staged / modified / untracked
  - last command exit code when non-zero
- Cross-terminal history syncing (`history -a; history -n`).
- Convenience aliases in `~/.bash_aliases`.
- A WSL helper command: `ex` to launch **Windows Explorer** from inside Linux.

**Bonus:** See [WSL_COMMANDS.md](WSL_COMMANDS.md) for a comprehensive guide to managing WSL instances (install, backup, clone, etc.).

References:
- GNU Stow manual: https://www.gnu.org/s/stow/manual/stow.html
- Stow defaults (`--target` / parent directory): https://man.archlinux.org/man/stow.8
- Bash `PROMPT_COMMAND`: https://www.gnu.org/software/bash/manual/bash.html
- Bash prompt escapes (`\t`, `\u`, `\h`, `\w`, `\$`): https://www.gnu.org/software/bash/manual/html_node/Controlling-the-Prompt.html
- Bash `history` builtin (`-a`, `-n`): https://www.gnu.org/software/bash/manual/html_node/Bash-History-Builtins.html
- WSL running Windows tools from Linux (`explorer.exe`): https://learn.microsoft.com/en-us/windows/wsl/filesystems

---

## Repo layout

```
.
├── bash
│   ├── .bashrc
│   └── .bash_aliases
├── bin
│   └── bin
│       └── ex
├── packages
│   ├── packages.txt
│   └── README.md
├── install.sh
└── README.md
```

There are two Stow “packages”:
- `bash` → installs `~/.bashrc` and `~/.bash_aliases`
- `bin`  → installs `~/bin/ex`

---

## Important assumption about where you place this folder

Your `install.sh` runs `stow bash bin` **without** specifying `--target`.

By default, Stow’s target is the **parent directory of the stow directory** (the directory you run `stow` from). That means:

- If this project is located like: `$HOME/dotfiles/` (i.e., the `dotfiles` directory is directly under your home directory), then Stow will install into `$HOME` and everything works as intended.
- If the project is located somewhere else (e.g., `$HOME/projects/freeplayground/dotfiles/`), then Stow will install into `$HOME/projects/freeplayground/` instead of `$HOME`.

If you want this to work from anywhere, run Stow with an explicit target (see “Install (robust method)” below).

---

## Install (recommended)

### Install (simple method, matches `install.sh`)

1) Place the folder so you have: `$HOME/dotfiles/`  
2) Run:

```bash
chmod +x "$HOME/dotfiles/install.sh" "$HOME/dotfiles/bin/bin/ex"
"$HOME/dotfiles/install.sh"
```

### What `install.sh` does (step-by-step)

On Debian/Ubuntu (including WSL Ubuntu/Debian), the script:

1) Enables strict mode: `set -euo pipefail`
2) Reads all packages from `packages/packages.txt` (ignoring comments and blank lines)
3) Runs package installation:
   - `sudo apt-get update -qq` (quiet mode)
   - `sudo apt-get install -y <packages from packages.txt>`
4) Attempts to install `lazygit` and `lazydocker` from GitHub releases if not available via apt
5) Creates `~/bin` directory and adds convenience symlinks (e.g., `fd → fdfind`)
6) Runs `stow bash bin` to create dotfile symlinks
7) Prints "Done" and reminds you to run `source ~/.bashrc` or open a new terminal

---

## What changes in `$HOME`

After stowing into your home directory, you’ll typically have:

- `~/.bashrc`        → symlink to `dotfiles/bash/.bashrc`
- `~/.bash_aliases`  → symlink to `dotfiles/bash/.bash_aliases`
- `~/bin/ex`         → symlink to `dotfiles/bin/bin/ex`

If Stow reports a conflict, it means a real file already exists where it wants to create a symlink (example: a pre-existing `~/.bashrc`). Stow will not overwrite by default.

---

## Bash prompt details

The prompt is updated via `PROMPT_COMMAND`:

- `PROMPT_COMMAND="__dotfiles_prompt; history -a; history -n"`

Bash executes `PROMPT_COMMAND` right before printing `PS1`, so it’s the right hook to dynamically compute git status and last-exit-code display.

### What you’ll see

- A blank line before each prompt
- Time in 24h with seconds (`\t`)
- `user@host`
- current working directory (`\w`)
- git info when inside a repo
- failure marker when the last command failed: `✗<exit_code>`

### Git marker legend

When you are inside a git repo, the prompt shows:

- `✚` staged changes exist (`git diff --cached` is not clean)
- `✱` modified tracked files exist (`git diff` is not clean)
- `?` untracked files exist

Examples:
- `(main)` clean
- `(main ✚)` staged only
- `(main ✱?)` modified + untracked
- `(main ✚✱?)` everything

---

## History syncing across terminal tabs

After each command, the prompt hook runs:

- `history -a` append new lines from this session to the history file
- `history -n` read lines appended by other sessions since this session started

Result: multiple terminal tabs stay much more “in sync” than default Bash history behavior.

---

## WSL helper: `ex`

`ex` is a tiny wrapper around:

```bash
explorer.exe "$@"
```

Usage:
- `ex .` → open Windows Explorer in the current directory
- `ex /mnt/c` → open Explorer at the Windows C: drive mount
- `ex somefile.pdf` → open the file with Windows default app

Tip: because the wrapper passes arguments as-is, `ex` with no arguments just calls `explorer.exe` with no path (Windows decides what to show). In practice, `ex .` is the most predictable.

---

## Aliases

Aliases live in `~/.bash_aliases` and are sourced from `.bashrc`.

Highlights:
- git shortcuts: `gitlog`
- safety flags: `cp -i`, `mv -i`, `rm -i`
- Docker Portainer helper: `dpot` / `dpotstop`
- `cleanzone` to remove `Zone.Identifier` files

---

## Update / re-apply

If you edit files in this repo, symlinks already point to them, so changes are immediate for new shells.

If you add/remove packages or want to refresh links:

```bash
cd "$HOME/dotfiles"
stow --restow bash bin
```

---

## Uninstall (remove symlinks)

```bash
cd "$HOME/dotfiles"
stow -D bash bin
```

This removes symlinks created by Stow without deleting your repo files.

---

## Troubleshooting

### 1) Stow conflicts
If you see conflicts, it’s usually because you already have:
- a real `~/.bashrc`
- a real `~/.bash_aliases`
- a real `~/bin/ex`

Fix options:
- back up and remove the existing file, then re-run
- merge content, then re-run Stow

### 2) `explorer.exe` doesn’t run
WSL interop may be disabled or broken. Test with:

```bash
notepad.exe
```

If that fails too, check WSL interop settings / troubleshooting:
- https://learn.microsoft.com/en-us/windows/wsl/troubleshooting
