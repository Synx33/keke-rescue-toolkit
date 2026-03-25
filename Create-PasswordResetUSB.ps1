# ============================================================================
# USB Rescue Toolkit Creator (UEFI + BIOS)
# ============================================================================
# Creates a fully self-contained UEFI-bootable USB using Alpine Linux.
# Includes: password reset, system info, disk management, data backup,
#           network diagnostics, boot repair — all working offline.
#
# USAGE: Right-click make-usb.bat -> Run as administrator
# ============================================================================

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

# -----------------------------------------------------------------------
# Helper functions
# -----------------------------------------------------------------------
function Write-Status($msg) { Write-Host "  [+] $msg" -ForegroundColor Green }
function Write-Warn($msg)   { Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-Err($msg)    { Write-Host "  [ERROR] $msg" -ForegroundColor Red }
function Write-Step($msg)   { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

# Write file with Unix line endings (LF) and UTF-8 no BOM
function Write-UnixFile($Path, $Content) {
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $unix = $Content.Replace("`r`n", "`n")
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $unix, $utf8)
}

# Fetch an Alpine APK package from CDN by regex pattern
function Get-AlpinePackage {
    param(
        [string]$Repo,         # "main" or "community"
        [string]$Pattern,      # regex pattern to match package filename
        [string]$DestDir,      # directory to save the .apk
        [string]$AlpineVer     # e.g. "3.21"
    )
    $baseUrl = "https://dl-cdn.alpinelinux.org/alpine/v${AlpineVer}/${Repo}/x86_64/"
    try {
        $listing = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing -ErrorAction Stop
        $matches2 = [regex]::Matches($listing.Content, 'href="([^"]+\.apk)"')
        foreach ($m in $matches2) {
            $fname = $m.Groups[1].Value
            if ($fname -match $Pattern) {
                $url = "${baseUrl}${fname}"
                $dest = Join-Path $DestDir $fname
                if (-not (Test-Path $dest)) {
                    Write-Status "  Downloading $fname"
                    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
                }
                return $dest
            }
        }
        Write-Warn "  Package matching '$Pattern' not found in $Repo"
        return $null
    } catch {
        Write-Warn "  Failed to fetch from $Repo : $_"
        return $null
    }
}

# -----------------------------------------------------------------------
# 1. Admin check
# -----------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Err "This script must be run as Administrator."
    Write-Host "  Right-click make-usb.bat and select 'Run as administrator'."
    Read-Host "`nPress Enter to exit"
    exit 1
}

Write-Host ""
Write-Host "  =============================================" -ForegroundColor Cyan
Write-Host "   USB Rescue Toolkit Creator" -ForegroundColor Cyan
Write-Host "   UEFI + BIOS  |  No Linux Required" -ForegroundColor Cyan
Write-Host "  =============================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------
# 2. Select USB drive
# -----------------------------------------------------------------------
Write-Step "Step 1: Select USB Drive"

$usbDisks = @(Get-Disk | Where-Object { $_.BusType -eq 'USB' -and $_.Size -gt 500MB })

if ($usbDisks.Count -eq 0) {
    Write-Err "No USB drives detected. Plug one in and try again."
    Read-Host "`nPress Enter to exit"
    exit 1
}

Write-Host "`n  Available USB drives:`n"
foreach ($d in $usbDisks) {
    $sz = [math]::Round($d.Size / 1GB, 1)
    Write-Host "    Disk $($d.Number):  $($d.FriendlyName)  ($sz GB)" -ForegroundColor White
}

$diskNum = [int](Read-Host "`n  Enter disk number")
$sel = $usbDisks | Where-Object { $_.Number -eq $diskNum }

if (-not $sel) {
    Write-Err "Invalid disk number."
    Read-Host "`nPress Enter to exit"
    exit 1
}

# -----------------------------------------------------------------------
# 3. Confirm wipe
# -----------------------------------------------------------------------
$sz = [math]::Round($sel.Size / 1GB, 1)
Write-Warn "ALL DATA on Disk $diskNum ($($sel.FriendlyName), $sz GB) will be ERASED!"
$confirm = Read-Host "  Type YES to continue"
if ($confirm -ne "YES") { Write-Host "  Aborted."; exit 0 }

# -----------------------------------------------------------------------
# 4. Format: GPT + FAT32 (cap at 32 GB)
# -----------------------------------------------------------------------
Write-Step "Step 2: Formatting USB Drive"

Write-Status "Cleaning disk..."
# Remove all existing partitions
Get-Partition -DiskNumber $diskNum -ErrorAction SilentlyContinue |
    Where-Object { $_.Type -ne 'Reserved' } |
    Remove-Partition -Confirm:$false -ErrorAction SilentlyContinue

# Take disk offline/online to release locks
Set-Disk -Number $diskNum -IsOffline $true  -ErrorAction SilentlyContinue
Set-Disk -Number $diskNum -IsOffline $false -ErrorAction SilentlyContinue

# Clear and re-initialize
try {
    Clear-Disk -Number $diskNum -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
} catch {
    Write-Warn "Clear-Disk had issues, continuing..."
}

Write-Status "Creating GPT partition table..."
$disk = Get-Disk -Number $diskNum
if ($disk.PartitionStyle -ne 'RAW') {
    # Disk already initialized — try to convert, fall back to diskpart
    try {
        Set-Disk -Number $diskNum -PartitionStyle GPT -ErrorAction Stop
        Write-Status "Converted to GPT."
    } catch {
        Write-Warn "Using diskpart fallback..."
        $dpScript = "select disk $diskNum`nclean`nconvert gpt`nexit"
        $dpScript | diskpart | Out-Null
        Start-Sleep -Seconds 2
    }
} else {
    Initialize-Disk -Number $diskNum -PartitionStyle GPT -ErrorAction Stop
}

# Cap partition at 32 GB (Windows FAT32 format limit)
$maxSize = 32GB
$partSize = [math]::Min($sel.Size - 34MB, $maxSize)   # leave room for GPT headers

Write-Status "Creating FAT32 partition..."
$partition = New-Partition -DiskNumber $diskNum -Size $partSize -AssignDriveLetter
Start-Sleep -Seconds 2

$dl = $partition.DriveLetter
if (-not $dl) {
    # Sometimes the letter isn't assigned immediately
    $partition | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    $dl = (Get-Partition -DiskNumber $diskNum | Where-Object { $_.Size -eq $partition.Size }).DriveLetter
}
if (-not $dl) {
    Write-Err "Could not assign a drive letter. Please free up a letter and try again."
    Read-Host "`nPress Enter to exit"
    exit 1
}

Format-Volume -DriveLetter $dl -FileSystem FAT32 -NewFileSystemLabel "PWRESET" -Force | Out-Null
Write-Status "USB formatted as ${dl}:\ (FAT32 / GPT)"

# -----------------------------------------------------------------------
# 5. Download Alpine Linux Extended ISO
# -----------------------------------------------------------------------
Write-Step "Step 3: Downloading Alpine Linux"

$tempDir = Join-Path $env:TEMP "pwreset-usb-creator"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$versions = @(
    "3.21.3","3.21.2","3.21.1","3.21.0",
    "3.20.6","3.20.5","3.20.4","3.20.3","3.20.2","3.20.1","3.20.0",
    "3.19.4","3.19.3","3.19.2","3.19.1","3.19.0"
)

$isoPath  = $null
$isoReady = $false
$alpineVer = $null

foreach ($rel in $versions) {
    $major = ($rel -split '\.')[0..1] -join '.'
    $url = "https://dl-cdn.alpinelinux.org/alpine/v${major}/releases/x86_64/alpine-extended-${rel}-x86_64.iso"
    $dest = Join-Path $tempDir "alpine.iso"

    Write-Status "Trying Alpine v${rel}..."
    try {
        $head = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -ErrorAction Stop
        $mb = [math]::Round([long]$head.Headers['Content-Length'] / 1MB)
        Write-Status "Found! Downloading (~${mb} MB) -- please wait..."
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing -ErrorAction Stop
        $isoPath  = $dest
        $isoReady = $true
        $alpineVer = $major
        break
    } catch { continue }
}

if (-not $isoReady) {
    Write-Err "Could not download Alpine Linux. Check your internet connection."
    Read-Host "`nPress Enter to exit"
    exit 1
}
Write-Status "Download complete! (Alpine v$alpineVer)"

# -----------------------------------------------------------------------
# 6. Mount ISO, copy contents to USB with robocopy
# -----------------------------------------------------------------------
Write-Step "Step 4: Extracting Alpine Linux to USB"

Write-Status "Mounting ISO..."
$mountImg = Mount-DiskImage -ImagePath $isoPath -PassThru
Start-Sleep -Seconds 2
$isoDL = ($mountImg | Get-Volume).DriveLetter

if (-not $isoDL) {
    Write-Err "Could not mount the ISO image."
    Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
    Read-Host "`nPress Enter to exit"
    exit 1
}

Write-Status "Copying files from ${isoDL}:\ to ${dl}:\ ..."
$roboArgs = @("${isoDL}:\", "${dl}:\", "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NP", "/NS", "/NC")
& robocopy @roboArgs | Out-Null
if ($LASTEXITCODE -gt 7) {
    Write-Err "File copy failed (robocopy exit $LASTEXITCODE)."
}

Write-Status "Unmounting ISO..."
Dismount-DiskImage -ImagePath $isoPath | Out-Null

# -----------------------------------------------------------------------
# 7. Download APK packages
# -----------------------------------------------------------------------
Write-Step "Step 5: Downloading APK Packages"

$pkgDir = "${dl}:\packages"
New-Item -ItemType Directory -Path $pkgDir -Force | Out-Null

# Community repo packages
$communityPkgs = @(
    "^chntpw-\d"
)

# Main repo packages
$mainPkgs = @(
    "^ntfs-3g-\d",
    "^ntfs-3g-libs-\d",
    "^ntfs-3g-progs-\d",
    "^fuse-common-\d",
    "^fuse3-libs-\d",
    "^libgcrypt-\d",
    "^libgpg-error-\d",
    "^libblkid-\d",
    "^libintl-\d",
    "^kmod-\d",
    "^linux-firmware-other-\d",
    "^linux-firmware-intel-\d",
    "^linux-firmware-mediatek-\d",
    "^linux-firmware-rtlwifi-\d",
    "^linux-firmware-rtw88-\d",
    "^linux-firmware-rtw89-\d",
    "^linux-firmware-qca-\d",
    "^linux-firmware-qcom-\d",
    "^linux-firmware-ath10k-\d",
    "^linux-firmware-ath11k-\d",
    "^linux-firmware-brcm-\d"
)

Write-Status "Downloading community packages..."
foreach ($pat in $communityPkgs) {
    Get-AlpinePackage -Repo "community" -Pattern $pat -DestDir $pkgDir -AlpineVer $alpineVer
}

Write-Status "Downloading main packages..."
$ntfs3gApk = $null
$fwOtherApk = $null
foreach ($pat in $mainPkgs) {
    $result = Get-AlpinePackage -Repo "main" -Pattern $pat -DestDir $pkgDir -AlpineVer $alpineVer
    if ($pat -eq "^ntfs-3g-\d" -and $result) { $ntfs3gApk = $result }
    if ($pat -eq "^linux-firmware-other-\d" -and $result) { $fwOtherApk = $result }
}

# -----------------------------------------------------------------------
# 8. Extract ntfs-3g binary from the APK
# -----------------------------------------------------------------------
Write-Step "Step 6: Extracting ntfs-3g Binaries"

$ntfs3gBinDir = "${dl}:\ntfs3g_bin"
New-Item -ItemType Directory -Path $ntfs3gBinDir -Force | Out-Null

if ($ntfs3gApk -and (Test-Path $ntfs3gApk)) {
    $ntfs3gExtract = Join-Path $tempDir "ntfs3g_extract"
    New-Item -ItemType Directory -Path $ntfs3gExtract -Force | Out-Null

    Write-Status "Extracting ntfs-3g APK..."
    # APK files are gzip-compressed tarballs
    Push-Location $ntfs3gExtract
    & cmd /c "gzip -dc `"$ntfs3gApk`" | tar -x" 2>$null
    Pop-Location

    # Copy binaries
    $binFiles = @(
        @{ Src = "usr/bin/ntfs-3g";    Dst = "ntfs-3g" },
        @{ Src = "usr/bin/lowntfs-3g"; Dst = "lowntfs-3g" },
        @{ Src = "usr/sbin/ntfs-3g";   Dst = "ntfs-3g" },
        @{ Src = "usr/sbin/lowntfs-3g"; Dst = "lowntfs-3g" },
        @{ Src = "sbin/ntfs-3g";       Dst = "ntfs-3g" },
        @{ Src = "sbin/lowntfs-3g";    Dst = "lowntfs-3g" }
    )
    foreach ($bf in $binFiles) {
        $src = Join-Path $ntfs3gExtract $bf.Src
        if (Test-Path $src) {
            Copy-Item $src (Join-Path $ntfs3gBinDir $bf.Dst) -Force
            Write-Status "  Copied $($bf.Dst)"
        }
    }

    # Also extract from ntfs-3g-libs APK for the shared libraries
    $ntfs3gLibsApks = Get-ChildItem $pkgDir -Filter "ntfs-3g-libs-*.apk" -ErrorAction SilentlyContinue
    foreach ($libApk in $ntfs3gLibsApks) {
        $libExtract = Join-Path $tempDir "ntfs3g_libs_extract"
        New-Item -ItemType Directory -Path $libExtract -Force | Out-Null
        Push-Location $libExtract
        & cmd /c "gzip -dc `"$($libApk.FullName)`" | tar -x" 2>$null
        Pop-Location

        # Find and copy .so files
        $soFiles = Get-ChildItem $libExtract -Recurse -Filter "libntfs-3g.so*" -ErrorAction SilentlyContinue
        foreach ($so in $soFiles) {
            Copy-Item $so.FullName (Join-Path $ntfs3gBinDir $so.Name) -Force
            Write-Status "  Copied $($so.Name)"
        }
        Remove-Item $libExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Warn "ntfs-3g APK not found, skipping binary extraction."
}

# -----------------------------------------------------------------------
# 9. Extract and decompress iwlwifi firmware
# -----------------------------------------------------------------------
Write-Step "Step 7: Extracting WiFi Firmware"

$firmwareDir = "${dl}:\firmware"
New-Item -ItemType Directory -Path $firmwareDir -Force | Out-Null

if ($fwOtherApk -and (Test-Path $fwOtherApk)) {
    $fwExtract = Join-Path $tempDir "fw_extract"
    New-Item -ItemType Directory -Path $fwExtract -Force | Out-Null

    Write-Status "Extracting linux-firmware-other APK..."
    Push-Location $fwExtract
    & cmd /c "gzip -dc `"$fwOtherApk`" | tar -x" 2>$null
    Pop-Location

    # Download zstd for decompressing .ucode.zst files
    Write-Status "Downloading zstd decompressor..."
    $zstdZip = Join-Path $tempDir "zstd.zip"
    $zstdDir = Join-Path $tempDir "zstd"
    try {
        Invoke-WebRequest -Uri "https://github.com/facebook/zstd/releases/download/v1.5.6/zstd-v1.5.6-win64.zip" `
            -OutFile $zstdZip -UseBasicParsing -ErrorAction Stop
        Expand-Archive -Path $zstdZip -DestinationPath $zstdDir -Force
        $zstdExe = Get-ChildItem $zstdDir -Recurse -Filter "zstd.exe" | Select-Object -First 1
    } catch {
        Write-Warn "Could not download zstd: $_"
        $zstdExe = $null
    }

    # Find iwlwifi firmware files (.ucode and .ucode.zst)
    # Common firmware patterns for Intel WiFi
    $iwlPatterns = @(
        "iwlwifi-3168-*",
        "iwlwifi-7260-*",
        "iwlwifi-7265-*",
        "iwlwifi-8000C-*",
        "iwlwifi-8265-*",
        "iwlwifi-9000-*",
        "iwlwifi-9260-*",
        "iwlwifi-cc-a0-*",
        "iwlwifi-so-a0-*",
        "iwlwifi-ty-a0-*",
        "iwlwifi-QuZ-*",
        "iwlwifi-Qu-*"
    )

    $ucodeFiles = Get-ChildItem $fwExtract -Recurse -Filter "iwlwifi-*.ucode*" -ErrorAction SilentlyContinue
    $copied = 0

    foreach ($uf in $ucodeFiles) {
        if ($uf.Name -match '\.zst$') {
            # Decompress .zst file
            if ($zstdExe) {
                $outName = $uf.Name -replace '\.zst$', ''
                $outPath = Join-Path $firmwareDir $outName
                & $zstdExe.FullName -d $uf.FullName -o $outPath --force 2>$null
                if (Test-Path $outPath) {
                    $copied++
                }
            }
        } elseif ($uf.Name -match '\.ucode$') {
            # Already uncompressed
            Copy-Item $uf.FullName (Join-Path $firmwareDir $uf.Name) -Force
            $copied++
        }
    }

    Write-Status "Copied $copied iwlwifi firmware files to E:\firmware\"

    # Clean up firmware extract
    Remove-Item $fwExtract -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Warn "linux-firmware-other APK not found, skipping firmware extraction."
}

# -----------------------------------------------------------------------
# 10. Write custom GRUB config
# -----------------------------------------------------------------------
Write-Step "Step 8: Writing GRUB Configuration"

$grubCfgPath = "${dl}:\boot\grub\grub.cfg"
if (Test-Path $grubCfgPath) {
    # Remove read-only attribute
    $grubFile = Get-Item $grubCfgPath -Force
    if ($grubFile.Attributes -band [System.IO.FileAttributes]::ReadOnly) {
        $grubFile.Attributes = $grubFile.Attributes -bxor [System.IO.FileAttributes]::ReadOnly
        Write-Status "Removed read-only attribute from grub.cfg"
    }
}

$grubContent = @'
set timeout=3

menuentry "USB Rescue Toolkit" {
    linux /boot/vmlinuz-lts modules=loop,squashfs,sd-mod,usb-storage quiet
    initrd /boot/intel-ucode.img /boot/amd-ucode.img /boot/initramfs-lts
}

menuentry "USB Rescue Toolkit (Safe Graphics)" {
    linux /boot/vmlinuz-lts modules=loop,squashfs,sd-mod,usb-storage quiet nomodeset
    initrd /boot/intel-ucode.img /boot/amd-ucode.img /boot/initramfs-lts
}

menuentry "USB Rescue Toolkit (Verbose Boot)" {
    linux /boot/vmlinuz-lts modules=loop,squashfs,sd-mod,usb-storage
    initrd /boot/intel-ucode.img /boot/amd-ucode.img /boot/initramfs-lts
}
'@

Write-UnixFile $grubCfgPath $grubContent
Write-Status "GRUB config written."

# -----------------------------------------------------------------------
# 11. Build the overlay tarball (pwreset.apkovl.tar.gz)
# -----------------------------------------------------------------------
Write-Step "Step 9: Building Overlay (apkovl)"

$ovDir = Join-Path $tempDir "overlay"
if (Test-Path $ovDir) { Remove-Item $ovDir -Recurse -Force }
New-Item -ItemType Directory -Path "$ovDir/etc/profile.d"    -Force | Out-Null
New-Item -ItemType Directory -Path "$ovDir/usr/local/bin"     -Force | Out-Null

# Source script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# Map of overlay paths to source files on disk
$overlayFiles = @{
    "etc/profile.d/wizard.sh"         = Join-Path $scriptDir "wizard.sh"
    "usr/local/bin/auto-setup"        = Join-Path $scriptDir "auto-setup"
    "usr/local/bin/reset-windows-password" = Join-Path $scriptDir "reset-windows-password"
    "usr/local/bin/toolkit-menu"      = Join-Path $scriptDir "toolkit-menu"
    "usr/local/bin/system-info"       = Join-Path $scriptDir "system-info"
    "usr/local/bin/disk-manager"      = Join-Path $scriptDir "disk-manager"
    "usr/local/bin/data-backup"       = Join-Path $scriptDir "data-backup"
    "usr/local/bin/network-diag"      = Join-Path $scriptDir "network-diag"
    "usr/local/bin/boot-repair"       = Join-Path $scriptDir "boot-repair"
}

foreach ($entry in $overlayFiles.GetEnumerator()) {
    $destPath = Join-Path $ovDir $entry.Key
    $srcPath  = $entry.Value

    if (-not (Test-Path $srcPath)) {
        Write-Warn "Source file not found: $srcPath"
        continue
    }

    $content = [System.IO.File]::ReadAllText($srcPath)
    Write-UnixFile $destPath $content
    Write-Status "  Added $($entry.Key)"
}

# Build the apkovl tarball
Write-Status "Creating overlay tarball..."
$apkovl = Join-Path $tempDir "pwreset.apkovl.tar.gz"

Push-Location $ovDir
& tar -czf $apkovl -C $ovDir *
Pop-Location

if (-not (Test-Path $apkovl)) {
    Write-Err "Failed to create overlay tarball."
    Read-Host "`nPress Enter to exit"
    exit 1
}

Copy-Item $apkovl "${dl}:\" -Force
Write-Status "Overlay installed on USB."

# -----------------------------------------------------------------------
# 12. Verify all critical files exist on USB
# -----------------------------------------------------------------------
Write-Step "Step 10: Verifying USB Contents"

$criticalFiles = @(
    "${dl}:\boot\vmlinuz-lts",
    "${dl}:\boot\initramfs-lts",
    "${dl}:\boot\grub\grub.cfg",
    "${dl}:\EFI\BOOT\BOOTX64.EFI",
    "${dl}:\pwreset.apkovl.tar.gz",
    "${dl}:\packages",
    "${dl}:\ntfs3g_bin",
    "${dl}:\firmware"
)

$allOk = $true
foreach ($f in $criticalFiles) {
    if (Test-Path $f) {
        Write-Status "$($f.Replace("${dl}:\", ''))"
    } else {
        Write-Warn "MISSING: $($f.Replace("${dl}:\", ''))"
        $allOk = $false
    }
}

if ($allOk) {
    Write-Status "All critical files verified!"
} else {
    Write-Warn "Some files are missing. The USB may still work but with reduced functionality."
}

# -----------------------------------------------------------------------
# 13. Cleanup temp files
# -----------------------------------------------------------------------
Write-Step "Cleanup"
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Status "Temporary files removed."

# -----------------------------------------------------------------------
# 14. Success message with usage instructions
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "  =============================================" -ForegroundColor Green
Write-Host "   USB Rescue Toolkit Created!" -ForegroundColor Green
Write-Host "   Drive: ${dl}:\" -ForegroundColor Green
Write-Host "  =============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  How to use:" -ForegroundColor White
Write-Host "    1. Plug the USB into the target PC"
Write-Host "    2. Enter BIOS (F2/Del at startup) and DISABLE Secure Boot"
Write-Host "    3. Boot from USB (F12/F2/Del for boot menu)"
Write-Host "    4. At the login prompt type:  root   (no password)"
Write-Host "    5. Tools auto-setup and toolkit menu launches automatically"
Write-Host "    6. Available tools:"
Write-Host "       - Password Reset (local + Microsoft accounts)"
Write-Host "       - System Information"
Write-Host "       - Disk Management"
Write-Host "       - Data Backup / File Recovery"
Write-Host "       - Network Diagnostics"
Write-Host "       - Boot Repair"
Write-Host "       - SSH remote access (password: reset)"
Write-Host "    7. Remove USB and reboot when done"
Write-Host ""
Write-Host "  Requirements on target PC:" -ForegroundColor Yellow
Write-Host "    - Secure Boot must be DISABLED"
Write-Host "    - BitLocker drives need the recovery key first"
Write-Host "    - WiFi auto-connects from saved Windows profiles"
Write-Host ""
Write-Host "  To rebuild this USB later, run:" -ForegroundColor Cyan
Write-Host "    Right-click make-usb.bat -> Run as administrator" -ForegroundColor Cyan
Write-Host ""

Read-Host "Press Enter to exit"
