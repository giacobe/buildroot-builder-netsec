#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUILDER_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
usage() {
  echo 'Usage: 02-build-baseline.sh --config PATH [--name client|server]'
  echo 'PATH is a checked-out profile repository containing config/ and payload/.'
  echo 'Run 01 first. JOBS controls parallelism; NETSEC_HOST_CMAKE may select a compatible host CMake.'
}
CONFIG_DIR= NAME=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --config) CONFIG_DIR=${2:?missing config path}; shift 2 ;;
    --name) NAME=${2:?missing name}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[ -n "$CONFIG_DIR" ] || { usage >&2; exit 2; }
CONFIG_DIR=$(realpath "$CONFIG_DIR")
NAME=${NAME:-$(basename "$CONFIG_DIR")}
[[ "$NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || { echo 'Invalid build name' >&2; exit 2; }
[ -f "$BUILDER_DIR/.netsec-builder.env" ] || { echo 'Run 01-setup-buildroot.sh first.' >&2; exit 1; }
. "$BUILDER_DIR/.netsec-builder.env"
[ -f "$CONFIG_DIR/config/defconfig" ] && [ -f "$CONFIG_DIR/config/linux.config" ] || { echo 'Missing profile config files' >&2; exit 1; }
BUILD_OUTPUT="$BUILD_DIR/$NAME"
STAGE="$WORK_DIR/profiles/$NAME"
# Buildroot must operate on a Linux filesystem, including its staged overlay.
case "$BUILD_OUTPUT" in /mnt/[a-z]/*) echo 'Choose WORK_DIR on the Linux filesystem, not a Windows drive.' >&2; exit 1;; esac
mkdir -p "$STAGE/overlay" "$STAGE/external" "$BUILD_OUTPUT"
# Recreate only this dedicated staging directory to remove stale source files.
rsync -a --delete "$CONFIG_DIR/payload/rootfs-overlay/" "$STAGE/overlay/"
rsync -a --delete "$CONFIG_DIR/config/external/" "$STAGE/external/"
cp "$CONFIG_DIR/config/linux.config" "$STAGE/linux.config"
if [ -d "$STAGE/overlay/etc/init.d" ]; then find "$STAGE/overlay/etc/init.d" -type f -name 'S[0-9]*' -exec chmod 755 {} +; fi
if [ -d "$STAGE/overlay/usr/bin" ]; then find "$STAGE/overlay/usr/bin" -type f -name 'web-client-*' -exec chmod 755 {} +; fi
export BR2_EXTERNAL="$STAGE/external"
[ -z "${NETSEC_HOST_CMAKE:-}" ] || export BR2_CMAKE_CANDIDATES="$NETSEC_HOST_CMAKE"
sed "s|^BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE=.*|BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE=\"$STAGE/linux.config\"|" "$CONFIG_DIR/config/defconfig" > "$STAGE/defconfig"
printf '\nBR2_ROOTFS_OVERLAY="%s"\n' "$STAGE/overlay" >> "$STAGE/defconfig"
if [ -f "$CONFIG_DIR/payload/permissions.txt" ]; then
  cp "$CONFIG_DIR/payload/permissions.txt" "$STAGE/permissions.txt"
  printf 'BR2_ROOTFS_DEVICE_TABLE="system/device_table.txt %s"\n' "$STAGE/permissions.txt" >> "$STAGE/defconfig"
fi
PACKAGE_DIR="$ARTIFACT_DIR/$NAME-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$PACKAGE_DIR/images" "$PACKAGE_DIR/configs" "$PACKAGE_DIR/logs" "$PACKAGE_DIR/manifest"
make -C "$BUILDROOT_SRC" O="$BUILD_OUTPUT" BR2_DEFCONFIG="$STAGE/defconfig" defconfig 2>&1 | tee "$PACKAGE_DIR/logs/defconfig.log"
make -C "$BUILDROOT_SRC" O="$BUILD_OUTPUT" olddefconfig 2>&1 | tee "$PACKAGE_DIR/logs/olddefconfig.log"
make -C "$BUILDROOT_SRC" O="$BUILD_OUTPUT" -j"${JOBS:-4}" 2>&1 | tee "$PACKAGE_DIR/logs/build.log"
if [ -f "$CONFIG_DIR/tests/check_elf.py" ]; then python3 "$CONFIG_DIR/tests/check_elf.py" "$BUILD_OUTPUT/target"; fi
cp "$BUILD_OUTPUT/images/bzImage" "$PACKAGE_DIR/images/bzImage"
cp "$BUILD_OUTPUT/images/rootfs.cpio.gz" "$PACKAGE_DIR/images/rootfs.cpio.gz"
cp "$BUILD_OUTPUT/.config" "$PACKAGE_DIR/configs/final-buildroot.config"
cp "$CONFIG_DIR/config/defconfig" "$PACKAGE_DIR/configs/starting.defconfig"
cp "$CONFIG_DIR/config/linux.config" "$PACKAGE_DIR/configs/linux.config"
git -C "$CONFIG_DIR" rev-parse HEAD > "$PACKAGE_DIR/manifest/profile-git-commit.txt"
git -C "$BUILDER_DIR" rev-parse HEAD > "$PACKAGE_DIR/manifest/builder-git-commit.txt"
(cd "$PACKAGE_DIR/images" && sha256sum bzImage rootfs.cpio.gz) > "$PACKAGE_DIR/manifest/SHA256SUMS"
printf 'Buildroot: %s\nProfile: %s\nBoot validation: not run; test in v86 before distribution.\n' "$BUILDROOT_VERSION" "$NAME" > "$PACKAGE_DIR/manifest/validation-notes.txt"
echo "Baseline package: $PACKAGE_DIR"
