# Security boundaries

## Downloads

- Vendor shell installers are downloaded over HTTPS to a temporary file and
  syntax-checked before Bash executes them. They remain moving upstream
  channels rather than checksum-pinned artifacts.
- GitHub-release installers for lazygit and lazydocker verify the selected
  archive against the release checksum manifest.
- Boost installs a verified release asset and only the CLI binary.
- Portainer follows the stable LTS tag and preserves custom container layouts.

Remote metadata failures fail closed where ownership or integrity cannot be
proven. Optional GitHub authentication is loaded through a private curl-config
boundary so token values do not appear in process arguments or reports.

## Credentials and secrets

The optional shared GitHub token is stored under
`${XDG_CONFIG_HOME:-$HOME/.config}/agentbot/` with strict permissions. Command
and Package Lib never render its value. Invalid or unsafe saved state falls back
to anonymous access with a warning.

Generated SSH keys prompt for a passphrase. Only the public key and setup notes
belong in `~/.ssh/github-setup.txt`. Codex pairing values are terminal-only
secrets.

## Privilege boundary

Most tool installers run as the user. Apt, PowerShell repository setup, Docker,
Docker-group membership, `/etc/wsl.conf`, and selected system destinations use
`sudo`. Docker commands first try the user's current access and fall back to
`sudo docker` when required.

Docker daemon JSON is merged rather than overwritten. Conflicting logging
settings stop configuration and prevent a restart. Existing Git credential
helpers are preserved when Windows GCM cannot be found.

## Ownership boundary

Dotfiles updates only binaries whose installation owner it can prove. It does
not configure Graphify or Boost inside coding agents, manage Agentbot policy,
accept Boost agreements, enable BoostGraph, or silently remove external Codex
installations.

Repository replacement preserves recoverable Git state before changing a
dirty, ahead, or diverged checkout. It never runs `git clean` and leaves ignored
files alone.

