Tamam, bunu tek seferde temizleyecek **net ve uygulanabilir Copilot promptu** hazırladım. Bu prompt hem senin install fail’i hem de SS’teki audit bulgularını birlikte çözecek.

Aşağıyı direkt Copilot Pro’ya ver 👇

---

You are working on a Bash-based Arch Linux installer framework.

Apply the following fixes and improvements carefully. Do NOT break existing flow. Keep changes minimal, consistent, and production-safe.

---

## 1. CRITICAL: Fix chroot syntax error (INSTALL FAIL)

There is a runtime error:

```
/bin/bash: line 88: syntax error near unexpected token `else'
```

Search in all installer scripts (especially `installer/executor.sh` and any script executed inside chroot).

Fix invalid Bash syntax:

* Replace `else;` → `else`
* Replace `elif ...;` → `elif ...`
* Ensure correct structure:
  if condition; then
  ...
  else
  ...
  fi

Do NOT introduce semicolons after `else` or `elif`.

---

## 2. DEAD CODE CLEANUP

### remove unused function

* `show_install_menu()` is no longer used after menu refactor
  → DELETE the entire function safely

### remove unused tool picker functions

* `visible_tool_ids_csv()`
* `visible_tool_packages_csv()`

These are replaced by checklist logic.
→ DELETE both functions and any references

---

## 3. REMOVE UNUSED STUB

File:

```
postinstall.sh
```

Status: placeholder, never executed

→ Either:

* DELETE the file completely
  OR
* integrate it into install flow (preferred: DELETE for now)

---

## 4. FIX: arch-chroot HANG RISK

Problem:
`arch-chroot` can hang indefinitely

Wrap ALL arch-chroot calls with timeout:

Replace:

```
arch-chroot /mnt <command>
```

With:

```
timeout 300 arch-chroot /mnt <command>
```

Also:

* If timeout fails, log error and continue cleanup
* Do NOT let installer freeze

---

## 5. FIX: state.sh DUPLICATION

Problem:
Dual state.sh wrapper redundancy

Ensure:

* Only ONE source of truth for state handling
* Remove duplicate wrapper calls
* Standardize usage:
  source "./state.sh"

Remove any nested or duplicated invocation patterns.

---

## 6. FIX: DISK TYPE EMPTY

Problem:
UI shows:

```
Disk type: auto
```

After detection:

```
disk_type="$(detect_disk_type "$disk")"
```

Add fallback:

```
[ -z "$disk_type" ] && disk_type="unknown"
```

Update UI labels:

* ssd → "SATA SSD"
* nvme → "NVMe SSD"
* hdd → "HDD"

---

## 7. UX IMPROVEMENT: MENU FLOW

After disk selection completes:

Instead of returning to disk menu again:
→ Automatically go to MAIN MENU with cursor on "config"

Implement:

* set menu state variable (e.g. CURRENT_MENU="config")
* ensure next screen highlights config

---

## 8. FIX: LOW ISO SPACE MESSAGE (READABILITY)

Current output is unclear:

```
airootfs 256M 122M 135M 48%
```

Replace with readable format:

```
Total: X
Used: X
Free: X
Usage: X%
```

Implementation:

```
df -h / | awk 'NR==2 {printf "Total: %s\nUsed: %s\nFree: %s\nUsage: %s\n",$2,$3,$4,$5}'
```

---

## 9. TTY MODE FIX (BROKEN INPUT)

Problem:

* Enter not working
* layout broken

Fix:

* Reset terminal state before input:
  stty sane

* Replace all raw reads with:
  read -r var

Optional improvement:
If dialog is missing:
→ auto-install it:

```
pacman -Sy --noconfirm dialog
```

Prefer dialog UI over tty fallback.

---

## 10. VALIDATION

After changes:

* No syntax errors (bash -n)
* Installer must:
  ✔ start
  ✔ complete disk flow
  ✔ enter chroot
  ✔ NOT fail on syntax
  ✔ NOT hang

---

Keep code clean, minimal, and consistent with existing style.
Do not introduce unnecessary abstractions.

---

# 🎯 Bu prompt neyi çözer?

* 🔴 install fail (else syntax)
* 🧹 dead code cleanup
* 🧠 state sistemi sadeleşir
* 🧱 chroot hang fix
* 💽 disk type düzgün görünür
* 🧭 flow hızlanır (config’e atlama)
* 🖥 tty usable hale gelir
* 📊 ISO usage okunur olur

---

Bunu çalıştır → çıkan diff’i at
İstersen next step’te direkt refactor + feature (hardware-aware) geçeriz.
