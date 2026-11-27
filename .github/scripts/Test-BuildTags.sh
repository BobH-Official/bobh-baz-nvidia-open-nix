#!/usr/bin/env bash
# Offline integration test of the actual Justfile tag generator.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
export UPSTREAM_VERSION=45.20261125.1
image=bobh-baz-nvidia-open-nix
for channel in latest template-test virt; do
    output="$(just generate-build-tags "$image" "$channel")"
    read -r -a tags <<< "$output"
    if [[ "$channel" == latest ]]; then
        [[ "${#tags[@]}" == 4 && "${tags[0]}" == latest &&
           "${tags[1]}" =~ ^latest\.[0-9]{8}$ &&
           "${tags[2]}" == "${tags[1]#latest.}" &&
           "${tags[3]}" == "upstream.$UPSTREAM_VERSION" ]]
    else
        [[ "${#tags[@]}" == 3 && "${tags[0]}" == "$channel" &&
           "${tags[1]%.*}" == "$channel" &&
           "${tags[1]##*.}" =~ ^[0-9]{8}$ &&
           "${tags[2]}" == "$channel.upstream.$UPSTREAM_VERSION" ]]
    fi
    printf 'PASS: %s -> %s\n' "$channel" "$output"
done
printf 'All three hotfix tag cases passed.\n'
