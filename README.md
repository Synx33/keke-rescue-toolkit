# KEKE Rescue Toolkit

A bootable USB toolkit for Windows PC repair and recovery. Works offline, boots on any UEFI PC.

![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Windows Password Reset** - Clear passwords, PINs, unlock accounts (local + Microsoft)
- **NUKE Mode** - Wipe all accounts and create fresh admin via Utilman trick
- **Win11 Microsoft Account Bypass** - Skip forced Microsoft login during setup
- **Lock Screen Quick-Boot** - Set up one-click reboot to USB from lock screen
- **System Information** - CPU, RAM, disks, network, BIOS, battery details
- **Disk Management** - Health check with % score, SMART data, speed test, repair
- **Disk Clone / Imaging** - Clone disks, create/restore partition images
- **Data Backup / File Recovery** - Browse files, backup Windows user folders
- **Network Diagnostics** - Ping, DNS, traceroute, speed test, LAN scan
- **Hardware Tests** - RAM test, CPU stress, battery health, keyboard test, display test
- **Boot Repair** - Check/fix EFI bootloader, partition tables
- **WiFi Support** - Intel, Realtek, Atheros, Broadcom, MediaTek drivers included

## Quick Start

### Requirements
- Windows 10/11 PC to create the USB
- USB drive (8GB minimum, will be wiped)
- Internet connection (only for initial USB creation)

### Create the USB

1. Download or clone this repo
2. Plug in your USB drive
3. Right-click **`make-usb.bat`** → **Run as administrator**
4. Select your USB drive and type YES
5. Wait for the script to finish (~10 minutes depending on internet speed)

### Use the USB

1. Plug USB into the target PC
2. Boot from USB:
   - **If PC is unlocked:** Double-click `BOOT INTO TOOLKIT.bat` on the USB drive
   - **If PC is locked:** Hold power button (5s) → Press F12 → Select USB
   - **After first setup:** Click accessibility icon → type `r`
3. The KEKE animation plays and toolkit menu loads automatically
4. Pick a tool and follow the prompts

### Boot Menu Keys by Brand

| Brand | Key |
|-------|-----|
| Acer | F12 |
| HP | F9 |
| Dell | F12 |
| Lenovo | F12 |
| Asus | F8 / Esc |
| MSI | F11 |

## How It Works

The toolkit runs Alpine Linux from the USB. All tools are pre-loaded — no internet needed on the target PC. The USB boots via UEFI with auto-login directly into the toolkit menu.

### File Structure
```
make-usb.bat                  # One-click launcher (Run as Admin)
Create-PasswordResetUSB.ps1   # Master builder script
auto-setup                    # Boot-time binary loader
wizard.sh                     # Auto-login trigger
toolkit-menu                  # Main menu
reset-windows-password        # Password reset wizard
win11-bypass                  # Microsoft account bypass
lockscreen-reboot             # Lock screen quick-boot setup
system-info                   # Hardware info viewer
disk-manager                  # Disk health and management
disk-clone                    # Disk cloning and imaging
data-backup                   # File browser and backup
network-diag                  # Network diagnostics
hardware-test                 # Hardware testing suite
boot-repair                   # EFI boot repair
boot-animation                # KEKE startup animation
shutdown-animation            # USB removal fade-out
usb-watchdog                  # Auto-reboot on USB removal
grub.cfg                      # Custom GRUB config
inittab                       # Auto-login config
```

## Supported Hardware

### WiFi Chipsets (firmware included)
- Intel (iwlwifi) - 3168, 7260, 7265, 8000, 8265, 9000, 9260, AX200/201/210/211
- Realtek - RTL8192, RTL8723, RTL8821, RTW88, RTW89
- Atheros/Qualcomm - ATH9K, ATH10K, ATH11K, QCA
- Broadcom - brcmfmac
- MediaTek - MT7921, MT76x0

### Storage
- SATA (AHCI)
- NVMe
- USB 3.0
- SD/MMC cards
- Thunderbolt

## Disclaimer

This tool is intended for legitimate system administration, IT repair, and recovery of your own computers. Always ensure you have authorization before using on any system.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

Built by **KEKE**
