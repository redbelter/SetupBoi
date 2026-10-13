# SetupBoi

Turn a **fresh Windows install** into your machine with one JSON config.
Pure PowerShell — runs on stock Windows PowerShell 5.1, no dependencies, no
install step. Carry it on a USB stick or curl one file from GitHub.

```
  ____             _      ____    _  ___
 / ___|  ___  ___ | |__  | __ )  (_)/ _ \
 \___ \ / _ \/ __|| '_ \ |  _ \  | | (_) |
  ___) |  __/\__ \| | | || |_) | | |\__, |
 |____/ \___||___/|_| |_||____/  |_|   /_/
```

## What it does

| Section        | Effect                                                              |
|----------------|---------------------------------------------------------------------|
| `wallpaper`    | desktop wallpaper from a bundled file or URL (fill/fit/span/...)     |
| `colors`       | dark/light app+system mode, custom accent color + titlebar painting  |
| `desktopIcons` | This PC / Network / Recycle Bin toggles, or nuke every icon          |
| `taskbar`      | center/left, autohide, combine, and pinned apps (policy-based)       |
| `start`        | pinned Start apps via `ConfigureStartPins` (works unattended on 11)  |
| `experience`   | no bing search / no start recs / no lockscreen ads / extensions ...  |
| `bloatware`    | remove provisioned AppX junk (wildcards) + kill auto-app-install     |
| `onedrive`     | full removal: uninstaller + leftover folders/tasks/shell overlay     |
| `install`      | winget packages (self-bootstraps winget if the machine has none)     |
| `custom`       | raw registry writes, arbitrary commands, download+run files          |

## Quick start

### From a fresh PC with internet (nothing installed yet)

Open an **elevated** PowerShell and:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
Invoke-WebRequest https://raw.githubusercontent.com/redbelter/SetupBoi/main/setupboi.ps1 -OutFile setupboi.ps1
.\setupboi.ps1 -Config https://raw.githubusercontent.com/<you>/<you>/setup-config/config.json
```

That downloads the repo, unzips to `%TEMP%\SetupBoi`, and runs it.
Bring your own `config.json` via `-Config` (local path or URL), or accept the
bundled `config.example.jsonc`.

### From a USB stick / cloned repo

```powershell
cd SetupBoi
copy config.example.jsonc config.json    # then edit config.json
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

or just double-click `run.cmd`.

### Useful flags

```powershell
setup.ps1 -DryRun                # show every action, change nothing
setup.ps1 -Only colors,icons     # run a subset
setup.ps1 -Skip install          # run everything except...
setup.ps1 -Config ..\other.json  # alternate profile (work pc / gaming rig)
setup.ps1 -Reboot                # reboot at the end so pins apply
```

## Undo / rollback

Every mutation is journalled to `%LOCALAPPDATA%\SetupBoi\journal.json`
(append-as-you-go, so it survives a crash mid-run):

```powershell
.\undo.ps1            # roll back the LAST run
.\undo.ps1 -List      # show run history
.\undo.ps1 -Run 20261013-145833   # a specific run
.\undo.ps1 -All       # everything, newest run first
.\undo.ps1 -DryRun    # just show what would happen
```

What undo does:

- **registry values** → restored to their exact previous value; values that
  didn't exist before are *deleted* again
- **deleted files/folders** → re-copied from the per-run backup in
  `%LOCALAPPDATA%\SetupBoi\backup\<run-id>\` (auto-backup runs before every
  delete; trees > 300 MB skip the backup and say so)
- **files it created** → deleted
- **removed AppX packages** → listed with the reinstall hint (Store / winget);
  not auto-reinstalled on purpose
- **winget installs** → never uninstalled by undo; remove with
  `winget uninstall <id>` yourself

## Notes & gotchas

- **Start / taskbar pins** are applied through Windows' *policy* mechanism
  (`PolicyManager ConfigureStartPins` + `StartLayout` XML) — the only
  scriptable way that actually works unattended on Windows 11. They take
  effect **on next sign-in**. On 24H2 this is the officially supported GPO.
- The script **self-elevates** when sections need admin (bloatware/onedrive/
  installs). HKCU tweaks work fine without elevation.
- `bloatware.remove` supports wildcards (`Disney.*`, `*Netflix*`) and refuses
  to touch protected core packages (Explorer, Shell, Search, CDP...).
- Taskbar pins need a Start-Menu `.lnk`. Installs run **before** pinning, so
  an app listed in `install.winget` *and* in pins resolves in the same run.
  If a pin can't be resolved it's skipped with a warning, never fatal.
- Winget bootstrap (for a machine with no App Installer) pulls the latest
  release from `github.com/microsoft/winget-cli`.
- Everything is idempotent — run it again any time you edit the config.

## Layout

```
setup.ps1                  orchestrator (start here)
undo.ps1                   roll back any past run (uses the journal)
setupboi.ps1               one-file bootstrapper for bare PCs
run.cmd                    double-click launcher
config.example.jsonc       annotated example config
scripts/SetupBoi.psm1      shared helpers (registry, winget, wallpaper, pins, journal)
scripts/features/*.ps1     one file per section, each exposing Invoke-Boi<Thing>
wallpaper/wallpaper.jpg    placeholder wallpaper (replace with your own)
```

Adding a step = drop a `Invoke-BoiMyThing` in a new feature file and add one
line to the pipeline table in `setup.ps1`.
