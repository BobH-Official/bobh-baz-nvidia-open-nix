#!/bin/bash
set -ouex pipefail

# Apply project-owned system files (none yet; ignore directory placeholders).
if find /ctx/system_files -type f ! -name .gitkeep -print -quit | grep -q .; then
    tar --exclude=.gitkeep -C /ctx/system_files -cf - . | tar --no-overwrite-dir -C / -xf -
fi

# Preserve the minimal Nix-only base. Virtualization will be a separate variant.
