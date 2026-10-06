#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

# Niveth Linux 0.1 — Snapshot ISO Builder v3
#
# Purpose:
#   Capture the CURRENT installed Ubuntu system as the source image, while
#   excluding /home and interactive accounts. Preserve system-wide packages,
#   applications, services, Niveth components and selected desktop defaults.
#
# Safe workflow:
#   1) sudo ./build-snapshot-iso-v3.sh --preflight
#   2) sudo ./build-snapshot-iso-v3.sh --build
#
# Resume an interrupted snapshot without copying the whole filesystem again:
#   sudo ./build-snapshot-iso-v3.sh --resume /absolute/path/to/snapshot-dir
#
# The builder never writes back into the source / filesystem.

SOURCE_USER="${SUDO_USER:-${USER:?USER is not set}}"
SOURCE_HOME="$(getent passwd "$SOURCE_USER" | awk -F: '{print $6}')"
[[ -n "$SOURCE_HOME" && -d "$SOURCE_HOME" ]] || {
  echo "ERROR: cannot resolve source home for $SOURCE_USER" >&2
  exit 1
}

PROJECT_ROOT="${NIVETH_PROJECT_ROOT:-$SOURCE_HOME/Niveth}"
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

VERSION="0.1.1"
PROJECT_NAME="Niveth Linux"
HOST_NAME="niveth"
ISO_DIR="$PROJECT_ROOT/iso"
BUILD_ROOT="$PROJECT_ROOT/build/snapshot"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
SNAPSHOT_DIR=""
RESUME_DIR=""
MODE="build"

for arg in "$@"; do
  case "$arg" in
    --preflight) MODE="preflight" ;;
    --build) MODE="build" ;;
    --resume) MODE="resume-next" ;;
    -h|--help)
      sed -n '1,42p' "$0"
      exit 0
      ;;
  esac
done

# Parse --resume path separately so paths can contain spaces.
if [[ "${1:-}" == "--resume" ]]; then
  [[ -n "${2:-}" ]] || { echo "ERROR: --resume requires a snapshot directory." >&2; exit 2; }
  MODE="resume"
  RESUME_DIR="$(cd "$2" && pwd)"
fi

cleanup_mounts() {
  set +e
  [[ -n "${ROOTFS:-}" && -d "${ROOTFS:-}" ]] || return 0
  mountpoint -q "$ROOTFS/sys" && umount -R "$ROOTFS/sys" 2>/dev/null || true
  mountpoint -q "$ROOTFS/proc" && umount "$ROOTFS/proc" 2>/dev/null || true
  mountpoint -q "$ROOTFS/dev/pts" && umount "$ROOTFS/dev/pts" 2>/dev/null || true
  mountpoint -q "$ROOTFS/dev" && umount "$ROOTFS/dev" 2>/dev/null || true
}
trap cleanup_mounts EXIT INT TERM

log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

preflight() {
  local fail=0
  echo "============================================================"
  echo "NIVETH 0.1 SNAPSHOT BUILDER v3 — PREFLIGHT"
  echo "============================================================"
  echo "Project      : $PROJECT_ROOT"
  echo "Source user  : $SOURCE_USER"
  echo "Source home  : $SOURCE_HOME"
  echo

  for c in rsync mksquashfs grub-mkrescue xorriso update-initramfs chroot mount dpkg-query unsquashfs; do
    if command -v "$c" >/dev/null 2>&1; then
      echo "[PASS] $c"
    else
      echo "[FAIL] missing command: $c"
      fail=1
    fi
  done

  for p in casper squashfs-tools initramfs-tools grub-common grub-pc-bin grub-efi-amd64-bin xorriso rsync; do
    if dpkg-query -W -f='${Status}\n' "$p" 2>/dev/null | grep -q 'install ok installed'; then
      echo "[PASS] package $p"
    else
      echo "[FAIL] package $p not installed"
      fail=1
    fi
  done

  [[ -f "$PROJECT_ROOT/branding/os-release" ]] \
    && echo "[PASS] Niveth branding/os-release" \
    || echo "[WARN] branding/os-release missing; generated branding will be used"

  [[ -d "$PROJECT_ROOT/desktop/defaults/dconf" ]] \
    && echo "[PASS] Niveth dconf defaults" \
    || echo "[WARN] Niveth dconf defaults directory missing"

  echo
  echo "Current OS:"
  sed -n '1,18p' /etc/os-release
  echo
  echo "Current kernel: $(uname -r)"
  echo "Installed package records: $(dpkg-query -W -f='${binary:Package}\n' | wc -l)"
  echo
  (( fail == 0 )) && echo "[RESULT] PREFLIGHT PASS" || echo "[RESULT] PREFLIGHT FAIL"
  exit "$fail"
}

select_kernel() {
  KVER="$(
    for f in /boot/vmlinuz-*; do
      [[ -f "$f" ]] || continue
      basename "$f" | sed 's/^vmlinuz-//'
    done |
      grep -E '^[0-9]+\.[0-9]+\.[0-9]+([-.].*)?$' |
      sort -V |
      tail -n1
  )"

  [[ -n "$KVER" ]] || {
    echo "ERROR: no real kernel version found in /boot." >&2
    ls -l /boot/vmlinuz-* 2>/dev/null || true
    exit 1
  }
  [[ -f "/boot/vmlinuz-$KVER" ]] || {
    echo "ERROR: kernel image missing: /boot/vmlinuz-$KVER" >&2
    exit 1
  }
  [[ -d "/lib/modules/$KVER" ]] || {
    echo "ERROR: kernel modules missing: /lib/modules/$KVER" >&2
    exit 1
  }

  log "Selected kernel: $KVER"
}

prepare_dirs() {
  mkdir -p "$ROOTFS" "$ISO_TREE/casper" "$ISO_TREE/boot/grub" "$LOG_DIR" "$ISO_DIR"
}

copy_rootfs() {
  log "Snapshotting / (excluding /home and virtual filesystems)..."

  rsync -aHAXS --numeric-ids --one-file-system --delete --info=progress2 \
    --exclude='/dev/***' \
    --exclude='/proc/***' \
    --exclude='/sys/***' \
    --exclude='/run/***' \
    --exclude='/tmp/***' \
    --exclude='/var/tmp/***' \
    --exclude='/var/cache/apt/archives/***' \
    --exclude='/var/lib/snapd/seed/***' \
    --exclude='/var/lib/snapd/snapshots/***' \
    --exclude='/usr/src/***' \
    --exclude='/usr/include/***' \
    --exclude='/home/***' \
    --exclude='/mnt/***' \
    --exclude='/media/***' \
    --exclude='/lost+found' \
    --exclude='/swapfile' \
    --exclude='/hiberfil.sys' \
    --exclude='/pagefile.sys' \
    / "$ROOTFS/" 2>&1 | tee "$BUILD_LOG"

  # Excluded directories must still exist because chroot/initramfs tools expect them.
  mkdir -p "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/run" \
           "$ROOTFS/tmp" "$ROOTFS/home"
  chmod 1777 "$ROOTFS/tmp"
  chmod 755 "$ROOTFS/home"
}

sanitize_accounts() {
  log "Removing interactive accounts and host identity..."

  for f in etc/passwd etc/shadow etc/group etc/gshadow; do
    [[ -f "$ROOTFS/$f" ]] || continue
    awk -F: 'BEGIN{OFS=FS} ($3 < 1000 || $3 >= 60000) {print}' \
      "$ROOTFS/$f" > "$ROOTFS/$f.niveth"
    mv "$ROOTFS/$f.niveth" "$ROOTFS/$f"
  done

  for f in etc/subuid etc/subgid; do
    [[ -f "$ROOTFS/$f" ]] && sed -i "/^${SOURCE_USER}:/d" "$ROOTFS/$f" || true
  done

  sed -i "/^${SOURCE_USER}:/d" \
    "$ROOTFS/etc/passwd" "$ROOTFS/etc/shadow" \
    "$ROOTFS/etc/group" "$ROOTFS/etc/gshadow" 2>/dev/null || true

  rm -rf "$ROOTFS/home"
  mkdir -p "$ROOTFS/home"
  mkdir -p "$ROOTFS/var/tmp"
  chmod 1777 "$ROOTFS/var/tmp"
  chmod 755 "$ROOTFS/home"

  rm -rf "$ROOTFS/var/lib/AccountsService/users/"* \
         "$ROOTFS/var/lib/AccountsService/icons/"* \
         "$ROOTFS/var/lib/sudo/"* \
         "$ROOTFS/var/lib/systemd/linger/"* 2>/dev/null || true

  rm -rf "$ROOTFS/root/.ssh"
  rm -f "$ROOTFS/root/.bash_history"

  : > "$ROOTFS/etc/machine-id"
  rm -f "$ROOTFS/var/lib/dbus/machine-id"
  rm -f "$ROOTFS/var/lib/systemd/random-seed"

  rm -f "$ROOTFS/etc/ssh/ssh_host_"*
  rm -f "$ROOTFS/etc/NetworkManager/system-connections/"*
  rm -f "$ROOTFS/etc/udev/rules.d/70-persistent-net.rules"
  rm -f "$ROOTFS/etc/udev/rules.d/75-persistent-net-generator.rules"

  cat > "$ROOTFS/etc/fstab" <<'EOF'
# Niveth live system: persistent mounts intentionally not copied
EOF
  : > "$ROOTFS/etc/crypttab"

  rm -f "$ROOTFS/etc/initramfs-tools/conf.d/resume"

  if [[ -f "$ROOTFS/etc/mdadm/mdadm.conf" ]]; then
    sed -i '/^[[:space:]]*ARRAY[[:space:]]/d' "$ROOTFS/etc/mdadm/mdadm.conf"
  fi

  rm -f "$ROOTFS/var/spool/cron/crontabs/$SOURCE_USER" 2>/dev/null || true
  rm -rf "$ROOTFS/var/lib/cloud/instances/"* \
         "$ROOTFS/var/lib/cloud/instance" 2>/dev/null || true
  rm -rf "$ROOTFS/var/lib/dpkg/updates/"* 2>/dev/null || true

  printf '%s\n' "$HOST_NAME" > "$ROOTFS/etc/hostname"
  cat > "$ROOTFS/etc/hosts" <<'EOF'
127.0.0.1 localhost
127.0.1.1 niveth
::1 localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

  rm -rf "$ROOTFS/var/log/journal/"*
  rm -rf "$ROOTFS/var/tmp/"*
  rm -rf "$ROOTFS/tmp/"*
  rm -rf "$ROOTFS/var/cache/apt/archives/"*.deb 2>/dev/null || true

  find "$ROOTFS/var/log" -type f -exec truncate -s 0 {} \; 2>/dev/null || true
  rm -f "$ROOTFS/var/lib/NetworkManager/"*.state \
        "$ROOTFS/var/lib/NetworkManager/"*.json \
        "$ROOTFS/var/lib/NetworkManager/"*.xml 2>/dev/null || true
  rm -rf "$ROOTFS/var/lib/NetworkManager/seen-bssids" 2>/dev/null || true
}

apply_niveth_final_fixes() {
  log "Applying final Niveth Live fixes..."

  #
  # SNAP SEED CLEANUP
  #
  # Do not copy Ubuntu's one-time preseed payloads into the ISO.
  # Keep current snapd support and current snap payloads.
  #
  rm -rf "$ROOTFS/var/lib/snapd/seed"
  rm -rf "$ROOTFS/var/lib/snapd/snapshots"

  #
  # CALAMARES / INSTALL NIVETH
  #
  local cal_src="$PROJECT_ROOT/installer"
  local cal_conf="$ROOTFS/etc/calamares"
  local cal_brand="$ROOTFS/usr/share/calamares/branding/niveth"

  [[ -f "$cal_src/settings.conf" ]] || {
    echo "ERROR: missing $cal_src/settings.conf" >&2
    exit 1
  }

  mkdir -p \
    "$cal_conf/modules" \
    "$cal_brand" \
    "$ROOTFS/usr/share/applications"

  install -m 0644 \
    "$cal_src/settings.conf" \
    "$cal_conf/settings.conf"

  for f in "$cal_src/modules/"*.conf; do
    [[ -f "$f" ]] || continue
    install -m 0644 \
      "$f" \
      "$cal_conf/modules/$(basename "$f")"
  done

  if [[ -f "$cal_src/branding/niveth/branding.desc" ]]; then
    install -m 0644 \
      "$cal_src/branding/niveth/branding.desc" \
      "$cal_brand/branding.desc"
  fi

  if [[ -f "$cal_src/branding/niveth/boot-splash.png" ]]; then
    install -m 0644 \
      "$cal_src/branding/niveth/boot-splash.png" \
      "$cal_brand/boot-splash.png"
  elif [[ -f "$PROJECT_ROOT/desktop/plymouth/niveth/boot-splash.png" ]]; then
    install -m 0644 \
      "$PROJECT_ROOT/desktop/plymouth/niveth/boot-splash.png" \
      "$cal_brand/boot-splash.png"
  fi

  rm -f \
    "$ROOTFS/usr/share/applications/calamares-install-debian.desktop" \
    "$ROOTFS/etc/xdg/autostart/calamares-desktop-icon.desktop" \
    "$ROOTFS/usr/share/applications/calamares.desktop"

  cat > "$ROOTFS/usr/share/applications/niveth-installer.desktop" <<'EOF_INSTALLER'
[Desktop Entry]
Type=Application
Name=Install Niveth Linux
GenericName=System Installer
Comment=Install Niveth Linux to your disk
Exec=calamares
TryExec=calamares
Icon=calamares
Terminal=false
Categories=System;Settings;
StartupNotify=true
EOF_INSTALLER

  #
  # LIVE COMPATIBILITY
  #
  mkdir -p "$ROOTFS/etc/systemd/system/multi-user.target.wants"

  cat > "$ROOTFS/etc/systemd/system/niveth-live-compat.service" <<'EOF_COMPAT'
[Unit]
Description=Niveth Live compatibility settings
ConditionKernelCommandLine=niveth-live=1
Before=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF_COMPAT

  ln -sfn \
    ../niveth-live-compat.service \
    "$ROOTFS/etc/systemd/system/multi-user.target.wants/niveth-live-compat.service"

  #
  # VALIDATION
  #
  [[ -x "$ROOTFS/usr/bin/calamares" ]] || {
    echo "ERROR: Calamares executable missing from rootfs." >&2
    exit 1
  }

  [[ -f "$ROOTFS/usr/share/applications/niveth-installer.desktop" ]] || {
    echo "ERROR: Install Niveth launcher missing." >&2
    exit 1
  }

  [[ -f "$ROOTFS/etc/systemd/system/niveth-live-compat.service" ]] || {
    echo "ERROR: Niveth Live compatibility service missing." >&2
    exit 1
  }

  log "Final Niveth Live fixes applied."
}

generate_branding() {
  log "Applying Niveth identity..."
  if [[ -f "$PROJECT_ROOT/branding/os-release" ]]; then
    install -m 0644 "$PROJECT_ROOT/branding/os-release" "$ROOTFS/etc/os-release"
  else
    cat > "$ROOTFS/etc/os-release" <<'EOF'
NAME="Niveth Linux"
PRETTY_NAME="Niveth Linux 0.1.1"
VERSION="0.1.1"
VERSION_ID="0.1.1"
ID=niveth
ID_LIKE=ubuntu
EOF
  fi
  ln -snf /etc/os-release "$ROOTFS/usr/lib/os-release"
}

copy_desktop_defaults() {
  local skel="$ROOTFS/etc/skel"
  local runtime source_uid source_runtime dconf_file
  local rel

  log "Copying selected clean desktop configuration from $SOURCE_USER..."

  rm -rf "$skel"
  mkdir -p "$skel/.config" "$skel/.local/share"

  for f in .bashrc .profile .bash_logout; do
    [[ -f "$SOURCE_HOME/$f" ]] && install -m0644 "$SOURCE_HOME/$f" "$skel/$f"
  done

  # Niveth/user desktop configuration only.
  local cfgs=(
    .config/gtk-3.0
    .config/gtk-4.0
    .config/niveth
    .config/kitty
    .config/systemd/user
    .config/autostart
    .config/mimeapps.list
    .local/share/gnome-shell
    .local/share/niveth
    .local/share/themes
    .local/share/icons
  )

  for rel in "${cfgs[@]}"; do
    [[ -e "$SOURCE_HOME/$rel" ]] || continue
    mkdir -p "$skel/$(dirname "$rel")"
    rsync -aHAX --numeric-ids \
      --exclude='bookmarks' \
      --exclude='history*' \
      --exclude='recently-used.xbel' \
      --exclude='*.sqlite' \
      --exclude='*.sqlite-wal' \
      --exclude='*.sqlite-shm' \
      --exclude='*.db' \
      --exclude='sessions/' \
      --exclude='cache/' \
      --exclude='Cache/' \
      "$SOURCE_HOME/$rel" "$skel/$(dirname "$rel")/"
  done

  if [[ -d "$SOURCE_HOME/.local/share/applications" ]]; then
    mkdir -p "$skel/.local/share/applications"
    find "$SOURCE_HOME/.local/share/applications" -maxdepth 1 -type f \
      \( -iname '*niveth*.desktop' -o -iname 'org.niveth.*.desktop' -o -iname 'com.niveth.*.desktop' \) \
      -exec cp -a {} "$skel/.local/share/applications/" \;
  fi

  if [[ -d "$SOURCE_HOME/.local/bin" ]]; then
    mkdir -p "$skel/.local/bin"
    find "$SOURCE_HOME/.local/bin" -maxdepth 1 -type f \
      -iname 'niveth-*' -exec cp -a {} "$skel/.local/bin/" \;
  fi

  rm -rf "$skel/.config/google-chrome"
  rm -rf "$skel/.config/chromium"
  rm -rf "$skel/.config/BraveSoftware"
  rm -rf "$skel/.config/Code"
  rm -rf "$skel/.config/discord"
  rm -rf "$skel/.config/variety"
  rm -rf "$skel/.cache"
  rm -rf "$skel/.local/share/Trash"
  rm -rf "$skel/.local/share/keyrings"
  rm -rf "$skel/.ssh"
  rm -rf "$skel/.gnupg"

  rm -f "$skel/.config/gtk-3.0/bookmarks"
  rm -f "$skel/.config/gtk-3.0/recently-used.xbel"
  rm -f "$skel/.config/user-dirs.dirs"
  rm -f "$skel/.config/user-dirs.locale"

  # Capture the current GNOME dconf state as text, not the binary DB.
  source_uid="$(id -u "$SOURCE_USER")"
  source_runtime="/run/user/$source_uid"
  dconf_file="$skel/.config/niveth-user-settings.dconf"

  if [[ -S "$source_runtime/bus" ]] && command -v dconf >/dev/null 2>&1; then
    if runuser -u "$SOURCE_USER" -- env \
      XDG_RUNTIME_DIR="$source_runtime" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=$source_runtime/bus" \
      dconf dump / > "$dconf_file" 2>/dev/null
    then
      sed -i "s#${SOURCE_HOME}#/home/niveth#g" "$dconf_file" || true
    else
      rm -f "$dconf_file"
      echo "[WARN] user dconf dump unavailable; system dconf defaults remain."
    fi
  fi

  if [[ -f "$dconf_file" ]]; then
    install -d "$ROOTFS/usr/local/bin"
    cat > "$ROOTFS/usr/local/bin/niveth-restore-dconf" <<'EOF'
#!/usr/bin/env sh
set -eu
FILE="$HOME/.config/niveth-user-settings.dconf"
if [ -f "$FILE" ]; then
    /usr/bin/dconf load / < "$FILE"
    rm -f "$FILE"
fi
exit 0
EOF
    chmod 755 "$ROOTFS/usr/local/bin/niveth-restore-dconf"

    mkdir -p "$skel/.config/autostart"
    cat > "$skel/.config/autostart/niveth-restore-dconf.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Niveth Desktop Defaults
Comment=Restore captured Niveth desktop configuration
Exec=/usr/local/bin/niveth-restore-dconf
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
  fi

  grep -RIlF "$SOURCE_HOME" "$skel" 2>/dev/null |
    while read -r f; do
      sed -i "s#${SOURCE_HOME}#/home/niveth#g" "$f" || true
    done

  chown -R root:root "$skel"
  find "$skel" -type d -exec chmod 755 {} +
  find "$skel" -type f -exec chmod 644 {} +
}

prepare_live_env() {
  log "Preparing live environment..."

  mkdir -p "$ROOTFS/etc/initramfs-tools/conf.d"
  cat > "$ROOTFS/etc/initramfs-tools/conf.d/zz-niveth-casper" <<'EOF'
BOOT=casper
CASPER_GENERATE_UUID=1
EOF

  rm -f "$ROOTFS/etc/initramfs-tools/conf.d/resume"

  if [[ -x "$ROOTFS/usr/bin/dconf" ]]; then
    chroot "$ROOTFS" /usr/bin/dconf update >> "$BUILD_LOG" 2>&1 || true
  fi

  # App Center helper: permit ONLY this Niveth helper for members of sudo.
  mkdir -p "$ROOTFS/etc/polkit-1/rules.d"
  cat > "$ROOTFS/etc/polkit-1/rules.d/20-niveth-app-center.rules" <<'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.policykit.exec" &&
        action.lookup("program") == "/usr/local/bin/niveth-package-helper" &&
        subject.isInGroup("sudo")) {
        return polkit.Result.YES;
    }
});
EOF

  rm -f "$ROOTFS/etc/machine-id"
  : > "$ROOTFS/etc/machine-id"
  rm -f "$ROOTFS/var/lib/dbus/machine-id"
  rm -f "$ROOTFS/var/lib/systemd/random-seed"

  rm -f "$ROOTFS/etc/resolv.conf"
  ln -s /run/systemd/resolve/stub-resolv.conf "$ROOTFS/etc/resolv.conf"
}

generate_live_initrd() {
  log "Generating casper initramfs..."

  local tmpboot="/tmp/niveth-live-initrd"
  mkdir -p "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/run" "$ROOTFS/tmp"

  mkdir -p "$ROOTFS$tmpboot"
  rm -rf "$ROOTFS$tmpboot"
  mkdir -p "$ROOTFS$tmpboot"

  mount --bind /dev "$ROOTFS/dev"
  mkdir -p "$ROOTFS/dev/pts"
  mount --bind /dev/pts "$ROOTFS/dev/pts" 2>/dev/null || true
  mount -t proc /proc "$ROOTFS/proc"
  mount --rbind /sys "$ROOTFS/sys"
  mount --make-rslave "$ROOTFS/sys"

  local rc=0
  chroot "$ROOTFS" update-initramfs -c -k "$KVER" -b "$tmpboot" \
    >> "$BUILD_LOG" 2>&1 || rc=$?

  umount -R "$ROOTFS/sys" 2>/dev/null || true
  umount "$ROOTFS/proc" 2>/dev/null || true
  umount "$ROOTFS/dev/pts" 2>/dev/null || true
  umount "$ROOTFS/dev" 2>/dev/null || true

  (( rc == 0 )) || {
    echo "ERROR: update-initramfs failed; see $BUILD_LOG" >&2
    exit "$rc"
  }

  local generated="$ROOTFS$tmpboot/initrd.img-$KVER"
  [[ -f "$generated" ]] || {
    echo "ERROR: generated initrd missing: $generated" >&2
    exit 1
  }

  cp -a "/boot/vmlinuz-$KVER" "$ISO_TREE/casper/vmlinuz"
  cp -a "$generated" "$ISO_TREE/casper/initrd"
  rm -rf "$ROOTFS$tmpboot"
}

write_grub() {
  log "Writing GRUB configuration..."
  cat > "$ISO_TREE/boot/grub/grub.cfg" <<'EOF'
set default=0
set timeout=8

menuentry "Niveth Linux 0.1 — Try Niveth" {
    linux /casper/vmlinuz boot=casper quiet splash ignore_uuid niveth-live=1 username=niveth userfullname="Niveth Live Session" hostname=niveth user-default-groups=audio,video,plugdev,netdev,sudo,input ---
    initrd /casper/initrd
}

menuentry "Niveth Linux 0.1 — Safe graphics" {
    linux /casper/vmlinuz boot=casper quiet splash nomodeset ignore_uuid niveth-live=1 username=niveth userfullname="Niveth Live Session" hostname=niveth user-default-groups=audio,video,plugdev,netdev,sudo,input ---
    initrd /casper/initrd
}
EOF
}

write_metadata() {
  mkdir -p "$ISO_TREE/.disk"
  echo "Niveth Linux 0.1 amd64" > "$ISO_TREE/.disk/info"

  dpkg-query -W -f='${binary:Package}\t${Version}\n' | sort > "$MANIFEST"
  install -d "$ROOTFS/usr/share/niveth"
  install -m0644 "$MANIFEST" "$ROOTFS/usr/share/niveth/installed-packages.tsv"

  cat > "$ISO_TREE/NIVETH-BUILD.txt" <<EOF
Niveth Linux 0.1
Build: $TIMESTAMP
Kernel: $KVER
Source account: excluded
Source /home: excluded
Snapshot model: current system filesystem
EOF
}

build_squashfs() {
  log "Building single SquashFS (XZ)..."
  rm -f "$ISO_TREE/casper/filesystem.squashfs"
  mksquashfs "$ROOTFS" "$ISO_TREE/casper/filesystem.squashfs" \
    -comp xz -b 1M -noappend >> "$BUILD_LOG" 2>&1
}

build_iso() {
  log "Building BIOS+UEFI ISO..."
  rm -f "$ISO"
  grub-mkrescue \
    -o "$ISO" \
    "$ISO_TREE" \
    --product-name="$PROJECT_NAME" \
    --product-version="$VERSION" \
    --compress=xz \
    -iso-level 3 \
    >> "$BUILD_LOG" 2>&1

  [[ -s "$ISO" ]] || {
    echo "ERROR: ISO was not created." >&2
    exit 1
  }

  echo "[BUILD] Final ISO uses fixed filename: $(basename "$ISO")"
}

verify_iso() {
  log "Verifying ISO..."

  {
    echo "ISO: $ISO"
    stat -c 'SIZE_BYTES: %s' "$ISO"
    sha256sum "$ISO"
    echo
    echo "[EL TORITO]"
    xorriso -indev "$ISO" -report_el_torito plain -report_system_area plain 2>&1 || true
    echo
    echo "[CASPER]"
    xorriso -indev "$ISO" -ls /casper 2>&1
    echo
    echo "[OS RELEASE]"
    unsquashfs -cat "$ISO_TREE/casper/filesystem.squashfs" etc/os-release
    echo
    echo "[ACCOUNT CHECK]"
    if unsquashfs -cat "$ISO_TREE/casper/filesystem.squashfs" etc/passwd |
      grep -qE "^${SOURCE_USER}:"; then
      echo "FAIL: source account present"
      return 10
    else
      echo "PASS: source account absent"
    fi

    if unsquashfs -l "$ISO_TREE/casper/filesystem.squashfs" |
      grep -E "(^|/)home/${SOURCE_USER}(/|$)" >/dev/null; then
      echo "FAIL: source home present"
      return 11
    else
      echo "PASS: source home absent"
    fi

    echo "[HOST SECRET PATHS]"
    if unsquashfs -l "$ISO_TREE/casper/filesystem.squashfs" |
      grep -E '(^|/)(etc/ssh/ssh_host_|etc/NetworkManager/system-connections/|root/\.ssh/)' >/dev/null; then
      echo "FAIL: host-secret paths present"
      return 12
    else
      echo "PASS: host-secret paths absent"
    fi

    echo "[NIVETH]"
    for p in \
      usr/lib/niveth \
      usr/share/niveth \
      usr/local/bin/niveth-app-center \
      usr/local/bin/niveth-files
    do
      if unsquashfs -l "$ISO_TREE/casper/filesystem.squashfs" |
        sed 's#^squashfs-root/##' |
        grep -xF "$p" >/dev/null; then
        echo "PASS: $p"
      else
        echo "WARN: $p not found"
      fi
    done

    echo "[LIVE USER DEFAULTS]"
    for p in \
      etc/skel/.local/share/gnome-shell \
      etc/skel/.config/niveth \
      etc/skel/.config/kitty
    do
      if unsquashfs -l "$ISO_TREE/casper/filesystem.squashfs" |
        sed 's#^squashfs-root/##' |
        grep -xF "$p" >/dev/null; then
        echo "PASS: $p"
      else
        echo "WARN: $p not found"
      fi
    done

    echo
    echo "[RESULT] ISO verification completed"
  } | tee "$VERIFY_LOG"
}

start_new_build() {
  SNAPSHOT_DIR="$BUILD_ROOT/$TIMESTAMP"
  ROOTFS="$SNAPSHOT_DIR/rootfs"
  ISO_TREE="$SNAPSHOT_DIR/iso-tree"
  LOG_DIR="$SNAPSHOT_DIR/logs"
  MANIFEST="$SNAPSHOT_DIR/installed-packages.txt"
  BUILD_LOG="$LOG_DIR/build.log"
  VERIFY_LOG="$LOG_DIR/verify.log"
  ISO="$ISO_DIR/Niveth-0.1.1-amd64.iso"

  mkdir -p "$SNAPSHOT_DIR" "$LOG_DIR"
  : > "$BUILD_LOG"

  select_kernel
  prepare_dirs
  copy_rootfs
  sanitize_accounts
  apply_niveth_final_fixes
  generate_branding
  copy_desktop_defaults
  "$PROJECT_ROOT/scripts/apply-niveth-final-fixes.sh"     "$ROOTFS"     "$SOURCE_HOME"     "$PROJECT_ROOT"
  "$PROJECT_ROOT/scripts/install-niveth-sound-final.sh" \
    "$ROOTFS" \
    "$PROJECT_ROOT"
  prepare_live_env
  generate_live_initrd
  write_metadata
  write_grub
  build_squashfs
  build_iso

  sha256sum "$ISO" | tee "$SNAPSHOT_DIR/SHA256SUMS"
  verify_iso

  echo
  echo "============================================================"
  echo "NIVETH 0.1.1 SNAPSHOT BUILD COMPLETE"
  echo "============================================================"
  echo "ISO      : $ISO"
  echo "Snapshot : $SNAPSHOT_DIR"
  echo "SHA256   : $(sha256sum "$ISO" | awk '{print $1}')"
  echo "============================================================"
}

resume_build() {
  SNAPSHOT_DIR="$RESUME_DIR"
  ROOTFS="$SNAPSHOT_DIR/rootfs"
  ISO_TREE="$SNAPSHOT_DIR/iso-tree"
  LOG_DIR="$SNAPSHOT_DIR/logs"
  MANIFEST="$SNAPSHOT_DIR/installed-packages.txt"
  BUILD_LOG="$LOG_DIR/build.log"
  VERIFY_LOG="$LOG_DIR/verify.log"
  TIMESTAMP="$(basename "$SNAPSHOT_DIR")"
  ISO="$ISO_DIR/Niveth-0.1.1-amd64.iso"

  [[ -d "$ROOTFS" ]] || { echo "ERROR: rootfs not found in $SNAPSHOT_DIR" >&2; exit 1; }
  [[ -d "$ISO_TREE" ]] || { echo "ERROR: iso-tree not found in $SNAPSHOT_DIR" >&2; exit 1; }
  mkdir -p "$LOG_DIR"
  touch "$BUILD_LOG"

  log "Resuming existing snapshot: $SNAPSHOT_DIR"
  select_kernel
  mkdir -p "$ROOTFS/dev" "$ROOTFS/proc" "$ROOTFS/sys" "$ROOTFS/run" "$ROOTFS/tmp"
  chmod 1777 "$ROOTFS/tmp"

  # Re-apply the live-only bits safely, then create initramfs/ISO.
  generate_branding
  copy_desktop_defaults
  "$PROJECT_ROOT/scripts/apply-niveth-final-fixes.sh"     "$ROOTFS"     "$SOURCE_HOME"     "$PROJECT_ROOT"
  "$PROJECT_ROOT/scripts/install-niveth-sound-final.sh" \
    "$ROOTFS" \
    "$PROJECT_ROOT"
  prepare_live_env
  generate_live_initrd
  write_metadata
  write_grub
  build_squashfs
  build_iso

  sha256sum "$ISO" | tee "$SNAPSHOT_DIR/SHA256SUMS"
  verify_iso

  echo
  echo "============================================================"
  echo "NIVETH 0.1.1 SNAPSHOT RESUME COMPLETE"
  echo "============================================================"
  echo "ISO      : $ISO"
  echo "Snapshot : $SNAPSHOT_DIR"
  echo "SHA256   : $(sha256sum "$ISO" | awk '{print $1}')"
  echo "============================================================"
}

if [[ "$EUID" -ne 0 ]]; then
  echo "ERROR: run with sudo." >&2
  exit 1
fi

case "$MODE" in
  preflight) preflight ;;
  build) start_new_build ;;
  resume) resume_build ;;
esac
