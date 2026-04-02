# ArchInstall Framework — Phase 3 Implementation Prompt
## For: GitHub Copilot Pro (Claude Sonnet 4.6 Agent)

---

## ROLE

You are a senior Linux systems engineer and Arch Linux expert working on a modular Arch Linux installer framework written in Bash with a `dialog` UI.

You MUST follow the roadmap strictly. Improve the project to production-grade quality without breaking existing working features.

---

## CODEBASE SUMMARY (READ CAREFULLY — DO NOT RE-READ FILES UNNECESSARILY)

**Language:** Pure Bash, `set -uo pipefail`, no external frameworks  
**UI:** `dialog` with automatic TTY fallback; `INSTALL_UI_MODE` controls mode  
**State:** Tab-separated flat file at `/tmp/archinstall_state` via `get_state`/`set_state`  
**Config:** `config/packages.conf` loaded by `profiles.sh:load_system_package_config()`  
**Install log:** `/tmp/archinstall_install.log`  
**Progress log:** `/tmp/archinstall_progress.log`  
**Chroot:** Generated heredoc via `build_chroot_script()` → piped to `arch-chroot /mnt /bin/bash -s`

### File Layout

```
installer/
  install.sh          Main dialog UI, progress loop, profile capture, confirmation
  executor.sh         run_install(), partitioning, pacstrap, chroot script builder
  disk.sh             Disk selection / strategy orchestration
  ui.sh               dialog wrappers (menu, input_box, error_box, warning_box)
  state.sh            get_state / set_state
  modules/
    packages.sh       resolve_package_strategy() — full package merge
    profiles.sh       load_system_package_config(), append_unique_packages()
    desktop.sh        select_display_manager(), desktop_profile_packages()
    snapshots.sh      snapshot_required_packages(), snapshot_chroot_setup_snippet()
    hardware.sh       hardware_profile_packages() — microcode, GPU, VM tools
    network.sh        Live ISO pacman bootstrap helpers
    detect.sh         Boot mode, virt, GPU, CPU detection
    runtime.sh        refresh_runtime_system_state()
    disk/
      manager.sh      Disk workflows: wipe, free-space, dual-boot, manual
      space.sh        Free space estimation
    system/
      network.sh      network_required_packages()
      audio.sh        audio_required_packages()
      bluetooth.sh    bluetooth_required_packages()
config/
  packages.conf       Package policy (all profiles and tool definitions)
```

---

## WHAT IS ALREADY WORKING (DO NOT TOUCH)

These are confirmed working from real install tests:

- Full install flow: partitioning → format → mount → pacstrap → chroot → bootloader
- Btrfs 4-subvolume layout: @, @home, @var, @snapshots — all created, mounted, fstab entries written
- LUKS2 encryption with cryptdevice kernel parameter
- systemd-boot (UEFI) and GRUB (BIOS) bootloader install
- Intel/AMD microcode auto-detection and initrd line
- CPU microcode selection from CPU_VENDOR state
- GPU driver selection (mesa, nvidia, fallback)
- VM guest tools (vmware, virtualbox, kvm/qemu patterns)
- Snapper timeline snapshots with cleanup timers
- grub-btrfs only added for BIOS installs (not UEFI)
- iwd enabled in chroot + NM wifi backend configured
- SDDM display manager config with Breeze theme
- greetd/tuigreet display manager config
- EFI 1 GiB partition on wipe installs
- BIOS+GPT safety check (chroot guard + disk manager)
- pacstrap with -K flag (target keyring init)
- Install manifest written to user home post-install
- 50-line failure log in dialog
- Secure Boot (assisted/advanced) with sbctl
- Plugin hook system
- Progress dialog with mixed-gauge
- dialog TTY fallback

---

## EXACT PROBLEMS FOUND IN REAL TESTS (PHASE 3 TASKS)

### PROBLEM 1: Progress System Appears Frozen at ~95%

**Root cause:** `install_progress_percent()` in `install.sh` counts `[STEP]` log lines and divides by `estimate_install_step_count()`. During long pacstrap (which is one STEP that takes 2–8 minutes), the counter doesn't advance — UI appears frozen.

**Current code location:** `install.sh:install_progress_percent()`, `install.sh:estimate_install_step_count()`

**Required fix:** Replace step-count-based percentage with stage-based milestones:

```
[5%]   Pre-install checks
[10%]  Partitioning
[20%]  Mounting filesystems
[30%]  Starting pacstrap
[75%]  Pacstrap complete (this is where the real wait is)
[80%]  Generating fstab
[85%]  Configuring system (chroot)
[95%]  Bootloader install
[100%] Complete
```

Implement by writing a stage marker to the progress log at each major step in `run_install()` and reading it in the dialog update loop. Do NOT use step counting. Keep the dialog always updating (heartbeat approach).

---

### PROBLEM 2: Mirror Selection Lag

**Root cause:** No mirror refresh happens automatically before pacstrap. User must have run reflector manually. If mirrors are slow, pacstrap hangs with no feedback.

**Current code:** `executor.sh:initialize_pacman_environment()` handles pacman-key init but does NOT run reflector.

**Required fix:** Before calling pacstrap, add:

```bash
run_optional_step_with_retry "Refreshing pacman mirror list" 2 \
    reflector --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
```

This is non-critical (optional step with retry, not fatal). Add a 30-second timeout fallback. Only run if `reflector` is available. Add a progress log message: `"[MIRROR] Selecting fast mirrors..."`.

---

### PROBLEM 3: Pacman Interactive Prompts Cause Freeze

**Root cause:** Even with `--noconfirm`, certain conflicts (e.g., `iptables` vs `iptables-nft`) prompt the user. The required package `iptables-nft` conflicts with `iptables`.

**Current state:** `PACMAN_OPTS='--noconfirm --needed'` is set. `iptables-nft` is in `ARCHINSTALL_REQUIRED_PACKAGES`. BUT: if another package pulls in `iptables` as a dependency, pacman will still prompt.

**Required fix:** Add to pacstrap call:

```bash
pacstrap -K /mnt "${packages[@]}" --noconfirm --needed
```

This is already done. Additionally add before pacstrap:

```bash
# Pre-remove conflicting packages from live ISO context to avoid resolver prompts
pacman -Rdd iptables --noconfirm 2>/dev/null || true
```

This clears the conflict before pacstrap sees it. This should go in `initialize_pacman_environment()` or just before `run_pacstrap_install()` in `run_install()`.

---

### PROBLEM 4: Custom Profile Has Unnecessary Default Packages

**Root cause:** `config/packages.conf` defines:

```bash
ARCHINSTALL_USER_PACKAGES_custom=""
```

This is correct for `custom`. BUT `daily` profile includes:

```bash
ARCHINSTALL_USER_PACKAGES_daily="kate,git,curl,wget,htop,tmux,unzip,p7zip,rsync,man-db,man-pages,less,fastfetch"
```

The roadmap says: remove `tmux`, `htop` from defaults. Make them optional.

**Required fix:**

In `config/packages.conf`:
- Remove `htop` and `tmux` from `ARCHINSTALL_USER_PACKAGES_daily`
- Remove `htop` and `tmux` from `ARCHINSTALL_USER_PACKAGES_dev`
- Add them to `ARCHINSTALL_DEFAULT_VISIBLE_TOOLS_daily` and `ARCHINSTALL_DEFAULT_VISIBLE_TOOLS_dev` (already there — good)
- Their toggle packages are already defined (`ARCHINSTALL_TOOL_PACKAGES_htop`, `ARCHINSTALL_TOOL_PACKAGES_tmux`)

So htop/tmux will still appear in the Optional Tools checklist (already supported) and be installed if toggled — just not hardcoded in user packages.

---

### PROBLEM 5: Display Manager Conflict Risk

**Root cause:** Chroot script enables a display manager service but does NOT disable other DMs first. If user reinstalls or the system has leftover state, both sddm and greetd could be enabled.

**Required fix:** At the START of the display manager configuration block in `build_chroot_script()` (inside the chroot heredoc), before enabling any DM, add:

```bash
# Disable all known display managers before enabling the selected one
for _dm_service in sddm.service greetd.service lightdm.service gdm.service lxdm.service; do
    systemctl disable "$_dm_service" 2>/dev/null || true
done
```

Add this right before the `case $TARGET_DISPLAY_MANAGER in` block.

---

### PROBLEM 6: Network Status Not Displayed

**Root cause:** The installer header (backtitle) shows boot mode + environment. It does NOT show network status.

**Required fix:** Add a `detect_network_status()` function in `installer/modules/detect.sh` or `installer/modules/runtime.sh`:

```bash
detect_network_status() {
    local default_route=""
    local ip_addr=""
    local connection_type="unknown"

    default_route="$(ip route show default 2>/dev/null | head -n1 || true)"
    if [[ -z $default_route ]]; then
        printf 'Not Connected\n'
        return 0
    fi

    # Detect WiFi vs Ethernet
    local iface=""
    iface="$(printf '%s' "$default_route" | awk '{print $5}' 2>/dev/null || true)"
    if [[ -d /sys/class/net/${iface}/wireless ]] || \
       [[ -L /sys/class/net/${iface}/phy80211 ]]; then
        connection_type="WiFi"
    else
        connection_type="Ethernet"
    fi

    ip_addr="$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1 || true)"
    if [[ -n $ip_addr ]]; then
        printf 'Connected (%s) — %s\n' "$connection_type" "$ip_addr"
    else
        printf 'Connected (%s)\n' "$connection_type"
    fi
}
```

Then update `refresh_runtime_context()` in `install.sh` to set:

```bash
ARCHINSTALL_NETWORK_STATUS="$(detect_network_status 2>/dev/null || printf 'Unknown')"
```

Update `ARCHINSTALL_BACKTITLE` to include it:

```bash
ARCHINSTALL_BACKTITLE="ArchInstall | $(safe_runtime_boot_summary | tr -d '\n') | $(safe_runtime_environment_summary | tr -d '\n') | Net: $ARCHINSTALL_NETWORK_STATUS"
```

Add a pre-install warning dialog if network is not connected:

```bash
check_network_before_install() {
    local status=""
    status="$(detect_network_status 2>/dev/null || printf 'Unknown')"
    if [[ $status == "Not Connected" ]]; then
        warning_box "No Network Connection" \
            "No active network connection was detected.\n\nThe installer requires internet access to run pacstrap.\n\nCurrent status: $status\n\nConnect to the internet before continuing.\nUse: ip link, iwctl, or dhcpcd"
        return 1
    fi
    return 0
}
```

Call `check_network_before_install` in `run_install()` before `initialize_pacman_environment`, as a non-fatal warning (show warning, but do not abort — let user proceed if they want).

---

### PROBLEM 7: Logging UX Weak

**Current state:** Progress dialog shows last 5 lines of progress log. This is already implemented. The main log (`/tmp/archinstall_install.log`) has full detail.

**Required fix (minimal):**

1. In `render_install_progress_text()` in `install.sh`, change the log excerpt from 5 lines to 8 lines for better context.

2. Add a `[STAGE]` prefix to major log entries that is distinct from `[STEP]`:
   - `[STAGE] Partitioning disk`
   - `[STAGE] Running pacstrap (this may take several minutes)`
   - `[STAGE] Configuring system`
   - `[STAGE] Installing bootloader`
   
   Add these via existing `log_line` calls in `run_install()` at the stage transitions.

3. The progress log excerpt in the dialog should show `[STAGE]` lines prominently. No code change needed for this — just ensure the stage messages are written.

---

### PROBLEM 8: Menu Lag / Subshell Usage

**Current state:** Some functions use `$(...)` subshells in dialog label construction. Frequent subshell spawning in dialog loops is the main source of lag.

**Required fix:** In `install.sh:refresh_runtime_context()`, cache the results in global variables so dialog calls don't re-spawn subshells:

```bash
ARCHINSTALL_BOOT_SUMMARY=""
ARCHINSTALL_ENV_SUMMARY=""
ARCHINSTALL_GPU_LABEL_CACHED=""
ARCHINSTALL_NETWORK_STATUS=""

refresh_runtime_context() {
    # ... existing detection calls ...
    ARCHINSTALL_BOOT_SUMMARY="$(safe_runtime_boot_summary 2>/dev/null || printf 'Unknown')"
    ARCHINSTALL_ENV_SUMMARY="$(safe_runtime_environment_summary 2>/dev/null || printf 'Unknown')"
    ARCHINSTALL_GPU_LABEL_CACHED="$(state_or_default "GPU_LABEL" "Generic")"
    ARCHINSTALL_NETWORK_STATUS="$(detect_network_status 2>/dev/null || printf 'Unknown')"
    ARCHINSTALL_BACKTITLE="ArchInstall | $ARCHINSTALL_BOOT_SUMMARY | $ARCHINSTALL_ENV_SUMMARY | Net: $ARCHINSTALL_NETWORK_STATUS"
}
```

Then use these cached vars in `installer_context_header()` and `ARCHINSTALL_BACKTITLE` references — no subshell at dialog render time.

---

## IMPLEMENTATION RULES (STRICT)

1. **DO NOT break the working install flow** — test mentally by tracing `run_install()` call chain
2. **DO NOT rewrite entire files** — patch only what is needed
3. **DO NOT add new dependencies** — use only what's already in the Arch ISO
4. **KEEP bash scripts clean** — `set -uo pipefail` everywhere, proper quoting
5. **PREFER simple and robust** — no clever tricks that break under edge cases
6. **All new functions go in appropriate modules** — detection → `detect.sh` or `runtime.sh`, not inline in `install.sh`
7. **Inner heredocs in `build_chroot_script()` MUST use named terminators** — never use bare `EOF` for inner heredocs (already using `LOADERCONF`, `NMCONFIGEOF`, `EOT`, `SDDMCONF`)
8. **Pacman calls must always use `--noconfirm --needed`** — exported as `PACMAN_OPTS`
9. **Optional steps use `run_optional_step()` or `run_optional_step_with_retry()`** — they never abort the install
10. **Fatal steps use `run_step()` or `run_step_with_retry()`** — they exit on failure

---

## PHASE SCOPE (STRICT)

### PHASE 3 — IMPLEMENT NOW

All 8 problems listed above. Nothing more.

### PHASE 4 — DO NOT IMPLEMENT, ONLY PREPARE

- Snapshot rollback UI
- Boot snapshot integration (grub-btrfs live)
- CachyOS kernel support
- Postinstall modular system
- Hardware detection improvements (auto-GPU, PRIME)

Do not start Phase 4 work. If a Phase 4 concern arises, add a `# TODO(phase4):` comment only.

---

## IMPLEMENTATION ORDER (RECOMMENDED)

Work in this order to minimize risk of breaking things:

1. **`config/packages.conf`** — remove htop/tmux from user packages daily/dev (5 min, zero risk)
2. **`installer/modules/detect.sh`** — add `detect_network_status()` (new function, zero risk)
3. **`installer/install.sh`** — cache globals in `refresh_runtime_context()`, update backtitle, add `check_network_before_install()`, increase log excerpt to 8 lines (low risk)
4. **`installer/executor.sh`** — add pre-pacstrap iptables conflict removal, add reflector call, add `[STAGE]` log markers in `run_install()`, add DM disable-all before enable in chroot script (medium risk — chroot heredoc edit)
5. **`installer/install.sh`** — replace step-count progress with stage-based milestones (highest risk — test carefully)

---

## SPECIFIC CODE LOCATIONS TO EDIT

### `config/packages.conf`

```bash
# CHANGE:
ARCHINSTALL_USER_PACKAGES_daily="kate,git,curl,wget,htop,tmux,unzip,p7zip,rsync,man-db,man-pages,less,fastfetch"
ARCHINSTALL_USER_PACKAGES_dev="git,htop,tmux,curl,wget,fastfetch,ripgrep,fd,less,man-db,man-pages"

# TO:
ARCHINSTALL_USER_PACKAGES_daily="kate,git,curl,wget,unzip,p7zip,rsync,man-db,man-pages,less,fastfetch"
ARCHINSTALL_USER_PACKAGES_dev="git,curl,wget,fastfetch,ripgrep,fd,less,man-db,man-pages"
```

htop and tmux remain available as optional tools in the tool-picker UI (their TOOL definitions are already correct in packages.conf — do not remove them).

---

### `installer/modules/detect.sh` — New function to add

Add `detect_network_status()` at the end of the file (before any register call if present).

---

### `installer/install.sh` — Functions to modify

- `refresh_runtime_context()`: Add 4 cached global vars, include network status
- `installer_context_header()`: Use cached vars instead of subshells
- `install_progress_percent()` and `render_install_progress_text()`: Replace with stage-based system
- `progress_log_excerpt()`: Increase tail from 5 to 8 lines

---

### `installer/executor.sh` — Functions to modify

- `initialize_pacman_environment()`: Add reflector call (optional step with retry)
- `run_install()`: Add iptables pre-removal, add `[STAGE]` log markers, add `check_network_before_install()` call (warning only, non-fatal)
- `build_chroot_script()` heredoc: Add DM disable-all block before case statement

---

## STAGE-BASED PROGRESS SYSTEM — DESIGN

Replace the current `install_progress_percent()` (which counts `[STEP]` lines) with a system that reads a `CURRENT_STAGE` from the progress log.

### Stage markers (write to progress log in `run_install()`)

```bash
log_stage() {
    local stage_name=${1:?stage name required}
    local stage_percent=${2:?percent required}
    printf '[STAGE:%s] %s\n' "$stage_percent" "$stage_name" >> "$ARCHINSTALL_PROGRESS_LOG"
    log_line "[STAGE] $stage_name"
}
```

Call at these points in `run_install()`:

```bash
log_stage "Pre-install checks" 5
# ... after cleanup_mounts, ping, pacman-key init

log_stage "Partitioning disk" 10
# ... before/after parted commands

log_stage "Mounting filesystems" 20
# ... after mount_root_filesystem

log_stage "Downloading packages (this may take several minutes)" 30
# ... right before run_pacstrap_install

log_stage "Configuring system" 75
# ... right after pacstrap completes, before fstab/chroot

log_stage "Installing bootloader" 90
# ... inside chroot (the chroot script logs its own [STEP] lines)

log_stage "Completing installation" 95
# ... after run_chroot_configuration
```

### New `install_progress_percent()`:

```bash
install_progress_percent() {
    local progress_log=${1:?progress log is required}
    local percent=0
    local last_stage_line=""

    if [[ -f $progress_log ]]; then
        last_stage_line="$(grep -o '\[STAGE:[0-9]*\]' "$progress_log" 2>/dev/null | tail -n1 || true)"
        if [[ $last_stage_line =~ \[STAGE:([0-9]+)\] ]]; then
            percent="${BASH_REMATCH[1]}"
        fi
    fi

    # Clamp to 95 while running
    if (( percent > 95 )); then
        percent=95
    fi

    printf '%s\n' "$percent"
}
```

### New `render_install_progress_text()` current step label:

```bash
install_current_stage_label() {
    local progress_log=${1:?progress log is required}
    local last_stage=""

    if [[ -f $progress_log ]]; then
        last_stage="$(grep '^\[STAGE:[0-9]*\]' "$progress_log" 2>/dev/null | tail -n1 | sed 's/^\[STAGE:[0-9]*\] //' || true)"
    fi

    printf '%s\n' "${last_stage:-Preparing installer}"
}
```

Update `write_install_progress_dialog()` to use these new functions. The dialog update loop in `install.sh` (the spinner/heartbeat loop) must NOT be changed in its timing — only in what value it sends.

---

## NETWORK STATUS — DISPLAY ONLY (NO WIFI UI)

The installer must show network status in the header. It must NOT implement:
- WiFi selection UI
- iwd wizard
- dhcpcd invocation
- Network configuration inside the installer

If not connected: show a warning dialog before install starts. Let user dismiss it and continue if they want. The installer does not block on network.

---

## EXPECTED BEHAVIOR AFTER FIXES

1. Dialog never appears frozen — stage % advances during pacstrap
2. Backtitle shows: `ArchInstall | UEFI (Secure Boot: Off) | Baremetal | Net: Connected (Ethernet) — 192.168.1.5`
3. No pacman interactive prompts during install
4. DAILY profile: no htop/tmux by default (still selectable in tool picker)
5. If user had greetd configured before and re-installs with SDDM: no conflict
6. Mirror list refreshed automatically before pacstrap (non-fatal)
7. Progress shows meaningful stage names, not just raw step log lines

---

## IMPORTANT NOTES — DO NOT IGNORE

1. **Test flow mentally before committing**: trace `run_install()` from top to bottom after each change
2. **The chroot heredoc is critical** — a single unescaped `$` or wrong delimiter will silently produce an incorrect chroot script. Always use `\$variable` for chroot-internal variables and bare `$variable` for outer-scope variables that should be interpolated at heredoc render time.
3. **Inner heredoc terminators must not appear at column 0 in the middle of the outer heredoc** — `LOADERCONF`, `NMCONFIGEOF`, `EOT`, `SDDMCONF`, `NMCONF` are in use. Do not add any terminator that matches the outer `EOF`.
4. **`run_optional_step_with_retry` vs `run_step_with_retry`**: mirrors and iptables cleanup are OPTIONAL. pacstrap is CRITICAL.
5. **Progress log file may not exist** yet when the dialog loop starts — always guard with `[[ -f $progress_log ]]` before reading.
6. **Do not change the dialog update timing loop** — the 2-second sleep interval in the heartbeat already prevents CPU thrashing.
7. **`detect_network_status()` must be fast** — use `ip route` and `ip addr`, not `ping` or `curl`. `ping` in the header would add 1-2 seconds per refresh.
8. **Stability > features** — if any fix is uncertain, add a `|| true` to make it non-fatal rather than risking aborting the install.
9. **This is Phase 3 only** — no snapshot rollback UI, no CachyOS kernel, no postinstall modular system.
10. **The existing test showed the installer works end-to-end** — we are refining quality, not fixing broken fundamentals.

---

## WHAT THE USER ALREADY TESTED

The user has confirmed via real install tests on hardware/VM:
- End-to-end install completes successfully
- Btrfs + LUKS2 works
- KDE Plasma boots
- systemd-boot loads correctly
- Snapper runs
- NetworkManager + iwd works
- SDDM starts correctly
- The UI is functional

The 8 problems above were observed during those real tests. The fixes are targeted and surgical.

---

## OUTPUT REQUIREMENTS

- Provide clean, minimal patches to the relevant files
- Do not rewrite entire files
- Explain only when the code is non-obvious
- Focus on implementation — not documentation
- One file at a time — complete each file change fully before moving to the next
- After all changes, list what was changed and in which file/function
