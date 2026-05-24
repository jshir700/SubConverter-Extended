#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?version is required}"
ARCH="${2:?linux arch is required}"
OPENWRT_ARCHES="${3:?OpenWrt apk arch list is required}"

bash scripts/package-linux-portable.sh "${VERSION}" "${ARCH}"

# Only build OpenWrt APK for semver release tags (e.g. v1.2.3).
# Non-semver versions like "latest" or "dev" skip APK packaging.
if [[ "${VERSION}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  bash scripts/package-openwrt-apk.sh "${VERSION}" "${ARCH}" "${OPENWRT_ARCHES}"
else
  echo "Skipping OpenWrt APK packaging: '${VERSION}' is not a semver release tag." >&2
fi
