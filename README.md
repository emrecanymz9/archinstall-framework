Tamam, şimdi sana **full yazıyı** hazırladım. İçine TUI görünüm stili, disk menüsü, yön tuşları, Enter, Space ve Backspace desteği gibi tüm detayları ekledim. Bu haliyle README’ye veya başka yapay zekâ asistana direkt kopyalayabilirsin.  

---

# 📂 Arch Linux Installer Framework

## Directory Structure

```
installer/
├── modules/
│   ├── gpu.sh          # NVIDIA/AMD/Intel, Vulkan, VM GPU sürücüleri
│   ├── audio.sh        # PipeWire, WirePlumber, Pavucontrol
│   ├── network.sh      # NetworkManager, nss-mdns
│   ├── bluetooth.sh    # BlueZ, auto-enable
├── installer.sh        # Ana kurulum scripti (dialog tabanlı)
├── postinstall.sh      # Kullanıcı ayarları, ek paketler
├── README.md           # Kurulum ve Secure Boot açıklamaları
├── Makefile            # Installer için kısa komutlar
└── configs/
    ├── zsh/            # Zsh + eklentiler + Starship
    ├── tui/            # Dialog/Ncurses menü temaları
    └── fonts/          # setfont ayarları (terminus-font)
```

---

## 🚀 How to Run (from Arch ISO)

```bash
# 1. Boot the Arch Linux ISO and get a terminal

# 2. Install dependencies
pacman -Sy --needed dialog jq git parted cryptsetup dosfstools btrfs-progs \
    e2fsprogs efibootmgr arch-install-scripts

# 3. Clone this repository
git clone https://github.com/emrecanymz9/archinstall-framework.git
cd archinstall-framework

# 4. Run Phase 1 (Installer)
./installer/install.sh
```

📌 Not: Scriptler otomatik olarak çalıştırılabilir (`chmod +x`) gelir çünkü izinler repo’da commit sırasında saklanır. `.gitattributes` satır sonlarını normalize eder, çalıştırılabilirlik ise Git tarafından korunur.  

---

## 📌 Script İzinleri

- Bir kere `chmod +x` verip commit ettiğinde Git bu izinleri repo’da saklar.  
- Repo’yu klonlayan herkes scriptleri otomatik çalıştırılabilir alır.  
- `.gitattributes` sadece satır sonlarını normalize eder, izinleri yönetmez.  

Örnek `.gitattributes`:
```text
* text=auto
*.sh text eol=lf
*.md text eol=lf
```

---

## 📌 Makefile Mantığı

```Makefile
# Makefile

clone:
	cd .. && rm -rf archinstall && \
	git clone https://github.com/emrecanymz9/archinstall-framework.git archinstall

run:
	cd archinstall && ./installer/install.sh
```

📌 Kullanım:  
- `make clone` → Repo’yu sıfırdan indirir (önce üst dizine çıkar, eski klasörü siler, yeniden klonlar).  
- `make run` → Installer’ı çalıştırır.  

Avantaj: VM içinde sürekli test yaparken `cd`, `rm -rf`, `git clone` yazmana gerek kalmaz. Tek satırda otomatikleşir.  

---

## 📌 TUI Görünümü ve Stil

- **Dialog/Ncurses tabanlı menüler** kullanılacak.  
- **Renkli başlıklar**: Menülerin üst kısmında ASCII süslemeler veya renkli başlıklar.  
- **Tutarlı ikonlar/simge kullanımı**: `[✓]`, `[✗]`, `[>]` gibi basit semboller.  
- **Scale fit**: TTY çözünürlüğüne göre dialog otomatik uyum sağlar.  

### Klavye Kontrolleri
- ↑ ↓ → Menü seçenekleri arasında gezinme  
- Enter → Seçilen menüyü onaylama  
- Space → Çoklu seçim menülerinde işaretleme  
- Tab → Butonlar arasında geçiş (OK, Cancel)  
- Esc → Menüden çıkış  
- Backspace → Bir önceki menüye geri dönme (installer scriptinde `exit_status=255` kontrolü ile)  

---

## 📌 Disk Seçim Menüsü Örneği

```bash
choice=$(dialog --title "Disk Selection" \
       --menu "Use ↑ ↓ to navigate, Enter to select, Backspace to go back:" 15 60 5 \
       "sda" "Samsung SSD 500GB" \
       "sdb" "WD Blue HDD 1TB" \
       "nvme0n1" "Kingston NVMe 256GB" \
       "quit" "Exit installer" \
       3>&1 1>&2 2>&3)

exit_status=$?
if [ $exit_status -eq 255 ]; then
    echo "Backspace pressed → returning to previous menu"
    # Burada önceki menüye dönülür
fi
```

---

## 📌 Partition Seçim Menüsü Örneği

```bash
choice=$(dialog --title "Partition Options" \
       --radiolist "Select partitioning method (Space to mark, Enter to confirm, Backspace to go back):" 15 60 5 \
       "auto" "Use entire disk (automatic)" on \
       "manual" "Manual partition setup" off \
       "existing" "Reuse existing Linux partitions" off \
       3>&1 1>&2 2>&3)

exit_status=$?
if [ $exit_status -eq 255 ]; then
    echo "Backspace pressed → returning to previous menu"
    # Burada disk seçim menüsüne dönülür
fi
```

---

## 📌 Kurulum Akışı (Detaylı)

- Disk Yönetimi → Marka, model, label, boyut MiB/GiB listelenir.  
- Bootloader Seçimi → UEFI (systemd-boot/Limine + UKI + Secure Boot), BIOS (GRUB).  
- Filesystem → btrfs + zstd sıkıştırma, zram swap.  
- Post-Install → Kullanıcı ekleme, hostname, locale, timezone, NTP, NetworkManager enable.  
- Grafik Ortam → KDE Plasma + KWin + Wayland, greetd + qtgreet login manager, SDDM disable.  
- Donanım Modülleri → GPU sürücüleri, PipeWire audio, NetworkManager, BlueZ bluetooth.  
- Çözünürlük → Kernel parametreleri (`video=1920x1080`, `vga=ask`), `setfont`, VMware için open-vm-tools.  

---

## 📌 Devtools

- nano → Basit, kullanıcı dostu  
- micro → Nano’ya benzer, modern  
- VS Code → Gelişmiş IDE  

---

## 📌 README Notları

- Secure Boot: UEFI’de UKI imzalama ile çalışır. BIOS’ta Secure Boot yoktur.  
- Zsh + Starship + dialog: Renkli TUI menüler, ASCII süslemeler, Bash fallback bırakılmalı.  
- Wayland/XWayland: Plasma Wayland oturumu, X11 uygulamaları XWayland üzerinden çalışır.  
- Debug/Test: ISO içinde log alınamaz, VM’de test + screenshot yöntemi kullanılmalı.  

---

## 📂 GitHub Entegrasyonu

- `.gitignore` → geçici dosyaları hariç tutar.  
- `.gitattributes` → satır sonlarını normalize eder.  
- `LICENSE` → MIT veya GPLv3.  
- `CONTRIBUTING.md` → katkı kuralları.  
- `Makefile` → installer için kısa komutlar.  

---

✅ Bu haliyle yazı tam profesyonel oldu:  
- Script izinleri otomatik commit ile korunuyor.  
- `.gitattributes` satır sonlarını normalize ediyor.  
- Makefile ile test/debug süreci hızlanıyor.  
- TUI menüler yön tuşları, Enter, Space, Tab, Esc ve Backspace desteği ile tam kullanıcı dostu hale geldi.  
- README tüm kurulum akışını ve entegrasyonu açıklıyor.  

---
