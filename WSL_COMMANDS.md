# WSL Management Commands

Quick reference for managing Windows Subsystem for Linux (WSL) instances.

## List & View Distributions

```powershell
# List all installed WSL distributions and their status
wsl --list --verbose
wsl -l -v

# List available distributions for installation
wsl --list --online
wsl -l -o

# List only running distributions
wsl --list --running
```

## Install & Uninstall

```powershell
# Install a specific distribution
wsl --install --distribution Ubuntu-24.04
wsl --install -d Ubuntu-24.04

# Unregister (delete) a distribution
# WARNING: This deletes all data in that WSL instance!
wsl --unregister Ubuntu-24.04

# Update WSL itself
wsl --update

# Check WSL version
wsl --version
```

## Start & Stop

```powershell
# Start a specific distribution
wsl -d Ubuntu-24.04

# Start in a specific directory
wsl -d Ubuntu-24.04 --cd ~
wsl -d Ubuntu-24.04 --cd /home/username

# Shutdown all WSL instances
wsl --shutdown

# Terminate a specific distribution
wsl --terminate Ubuntu-24.04
wsl -t Ubuntu-24.04
```

## Set Default Distribution

```powershell
# Set default WSL distribution
wsl --set-default Ubuntu-24.04
wsl -s Ubuntu-24.04

# Set default WSL version (1 or 2)
wsl --set-default-version 2

# Convert a distribution to WSL 2 (or WSL 1)
wsl --set-version Ubuntu-24.04 2
```

## Export & Import (Backup/Restore)

```powershell
# Export a distribution to a .tar file (backup)
wsl --export Ubuntu-24.04 C:\backup\ubuntu-backup.tar

# Import a distribution from a .tar file
wsl --import Ubuntu-Custom C:\WSL\Ubuntu-Custom C:\backup\ubuntu-backup.tar

# Import with specific version
wsl --import Ubuntu-Custom C:\WSL\Ubuntu-Custom C:\backup\ubuntu-backup.tar --version 2
```

## Run Commands

```powershell
# Run a command in the default distribution
wsl ls -la

# Run a command in a specific distribution
wsl -d Ubuntu-24.04 ls -la

# Run as a specific user
wsl -u root
wsl -d Ubuntu-24.04 -u username command

# Execute a command and exit
wsl -- command
```

## Networking & Files

```powershell
# Access WSL files from Windows (in File Explorer or terminal)
\\wsl$\Ubuntu-24.04\home\username
\\wsl.localhost\Ubuntu-24.04\home\username

# Access Windows files from WSL
cd /mnt/c/Users/YourName/Documents
```

## Configuration

```powershell
# View WSL configuration
wsl --status

# Update WSL kernel
wsl --update --web-download

# Mount a disk in WSL
wsl --mount \\.\PHYSICALDRIVE1
```

## Troubleshooting

```powershell
# Restart WSL service (run in PowerShell as Administrator)
Restart-Service LxssManager

# Full shutdown and restart
wsl --shutdown
wsl

# Check which WSL version a distribution is using
wsl -l -v

# Reset network (if networking breaks)
wsl --shutdown
# Then restart your WSL instance
```

## Common Workflows

### Fresh Install

```powershell
# 1. See available distributions
wsl --list --online

# 2. Install Ubuntu 24.04
wsl --install -d Ubuntu-24.04

# 3. Set as default
wsl --set-default Ubuntu-24.04

# 4. Launch and set up user
wsl -d Ubuntu-24.04
```

### Clean Reinstall

```powershell
# 1. Backup if needed
wsl --export Ubuntu-24.04 C:\backup\ubuntu-backup.tar

# 2. Unregister (deletes everything!)
wsl --unregister Ubuntu-24.04

# 3. Reinstall
wsl --install -d Ubuntu-24.04
```

### Clone/Duplicate a Distribution

```powershell
# 1. Export existing distribution
wsl --export Ubuntu-24.04 C:\temp\ubuntu-clone.tar

# 2. Import with new name
wsl --import Ubuntu-Dev C:\WSL\Ubuntu-Dev C:\temp\ubuntu-clone.tar --version 2

# 3. Set default user (run inside the new instance)
wsl -d Ubuntu-Dev
# Inside WSL, create /etc/wsl.conf:
sudo nano /etc/wsl.conf
# Add:
# [user]
# default=yourusername
```

## Tips

- **Always use WSL 2** for better performance: `wsl --set-default-version 2`
- **Shutdown regularly** to free up resources: `wsl --shutdown`
- **Backup before major changes**: Use `wsl --export`
- **Pin to taskbar**: Right-click WSL in Start menu → Pin to taskbar
- **Windows Terminal**: Use Windows Terminal for better experience with multiple WSL instances

## Quick Access from PowerShell/CMD

```powershell
# Start default WSL instance
wsl

# Start WSL in home directory
wsl ~

# Start specific distribution
wsl -d Ubuntu-24.04

# Open Windows Explorer in WSL current directory (from within WSL)
explorer.exe .
```

## Resources

- Official WSL Documentation: https://learn.microsoft.com/en-us/windows/wsl/
- WSL GitHub: https://github.com/microsoft/WSL
- Troubleshooting: https://learn.microsoft.com/en-us/windows/wsl/troubleshooting
