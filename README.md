# Buildroot Builder NetSec

Independent counterpart to [buildroot-builder2](https://github.com/giacobe/buildroot-builder2). This repository keeps the familiar 01 / 02 / 03 workflow while consuming separate client/server configuration repositories. It does not change or use builder2 working directories.

## Clone and run

Use Ubuntu/Debian or WSL Ubuntu. Clone to a Linux filesystem such as your WSL home directory, not a Windows/OneDrive mount.

```sh
git clone https://github.com/giacobe/buildroot-builder-netsec.git
git clone https://github.com/giacobe/netsec-generic-web-client.git
git clone https://github.com/giacobe/netsec-generic-web-server.git
cd buildroot-builder-netsec
scripts/01-setup-buildroot.sh
scripts/02-build-baseline.sh --config ../netsec-generic-web-server --name server
scripts/02-build-baseline.sh --config ../netsec-generic-web-client --name client
```

Stage 01 installs host dependencies (sudo/apt) and downloads Buildroot **2025.02.15**, the version used to develop this baseline. Use `--skip-deps` on an already provisioned system. Override `BUILDROOT_VERSION` only when deliberately validating another release. `WORK_DIR` defaults to `$HOME/buildroot-builder-netsec-work`; the generated `.netsec-builder.env` records settings. `artifacts/` contains build outputs, never tracked in Git. Building both toolchains/desktops from scratch can take substantial time and disk space. `JOBS=4` is the default.

Stage 02 stages the selected profile on the Linux filesystem, builds its own kernel and filesystem, checks shared-library dependencies, and packages images, configurations, revisions, logs, and checksums. Each role is independent; there is no dependency on builder2 or the other role's kernel. Existing per-role Buildroot output directories support incremental builds.

## Package future payloads without compiling again

```sh
scripts/03-package-payload.sh \
  --repo https://github.com/giacobe/netsec-generic-web-client.git \
  --baseline artifacts/client-YYYYMMDD-HHMMSS \
  --output artifacts/client-updated \
  --payload-subdir payload/rootfs-overlay \
  --archive-dest / \
  --permissions-file payload/permissions.txt \
  --output-prefix client
```

Replace the repository URL with your future lab payload repository. `--ref` pins a tag/commit. Use `--archive-dest /root` (the default) for ordinary lab files; use `/` for a system overlay. The packager preserves baseline device nodes and explicit mode/owner metadata and copies the kernel unchanged. It adds/replaces files; it does not remove old files or add missing compiled packages. New dependencies require a baseline rebuild. Output is `client.bzImage`, `client.rootfs.cpio.gz`, and `manifest/`; stage 03 does not boot-test it. Existing output requires explicit `--force`.

For the [platform](https://github.com/giacobe/netsec-generic-web), rename output to `client-bzImage` / `client-rootfs.cpio.gz` (or server equivalents), then place it in `netsec/web/images/`. Distribute the image pairs and checksum manifests separately from Git. No image hosting destination is configured by these repositories.

## Provenance and licenses

See PROVENANCE.md. The setup and payload packaging scripts were adapted from builder2; its original repository identifies GPL-3.0. See LICENSE. Buildroot and guest packages have their own licenses. The numbered scripts intentionally remain distinct from builder2.

## Validation of this publication

Shell syntax and command-line help checks passed; both profiles resolved against Buildroot 2025.02.15 with their required packages and independent kernels. The payload regression test verifies preserved device nodes, executable permissions, and unchanged kernel bytes. Run `python3 tests/test_packager.py` to repeat it. A complete fresh toolchain/desktop compilation has not been repeated as part of publishing; the configurations and payloads derive from the running tested lab baseline.
