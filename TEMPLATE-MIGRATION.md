# Template migration test

Upstream: https://github.com/ublue-os/image-template/commit/e9c642029d600611009b114aad17c0a1467c52ba

This branch upgrades the template before adding the separate Virt variant.
The official NVIDIA Open stable base, /nix ownership, public signing key,
package identity and existing production deployment are unchanged.

- No automatic builds on the test branch. The candidate production workflow
  restores master-only push and schedule triggers (effective after merging),
  with no pull_request trigger.
- Manual container workflow builds locally on the runner, never pushes from
  this branch (even if publish is checked). Disk workflow is master-only.
- Rechunk is disabled by default, preserving the existing choice.
- Production tag contract: latest, latest.YYYYMMDD, YYYYMMDD, upstream.VERSION.
  Test tags are isolated; no test tags are published.
- The PowerShell detector resolves the actual Containerfile base, retains
  version detection with creation-date fallback, and compares base name,
  version and digest against the matching published tag. Date+1 guesses
  are removed. The build pins the inspected digest. Old images without
  the new labels will be rebuilt once when automatic checks resume.
- Scheduled master builds skip when the upstream and channel aliases agree,
  the base metadata matches and the source revision matches. Pushes and
  manual runs always build. Production publishing is automatic on master
  push/schedule, opt-in on master dispatch, and prohibited on other branches.
- Production checks the signing key before pushing. It pushes the versioned
  tag first, signs and verifies its digest, then promotes date aliases and
  latest last. A partial release is detected on the next scheduled run.
- Offline detector regression tests: `pwsh -NoProfile -File .github/scripts/Test-UpstreamUpdate.ps1`.
- Do not merge until the user has reviewed and validated the new workflow.
- Cosign 3.1.4 uses the upstream legacy-bundle flags for rpm-ostree.
- The existing cosign.pub and SIGNING_SECRET are reused; no new key.
- No Virt RPMs, automatic services, VFIO or kernel argument changes yet.
- The ISO workflow uses the existing KDE config rather than nonexistent
  iso.toml; the ISO kickstart points to this repository instead of the demo.

Local validation (Bazzite with just, pwsh, skopeo, podman):

```bash
just check
bash -n build_files/build.sh
pwsh -NoProfile -File .github/scripts/Check-UpstreamUpdate.ps1 -MyImage ghcr.io/bobh-official/bobh-baz-nvidia-open-nix
just build bobh-baz-nvidia-open-nix template-test
podman run --rm --entrypoint /usr/bin/stat bobh-baz-nvidia-open-nix:template-test -c '%u:%g' /nix
```

Local just build without exported metadata uses the floating Containerfile
default; the manual workflow verifies the pinned base and metadata together.
Do not merge until validation and the final production workflow are reviewed.

Local image build at e5d7075 was verified on 2026-11-27: bootc lint 14 passed,
1 skipped; Nix ownership 30000:30000, upstream metadata and both tag sets correct.
The revised workflow, signing path and regression tests still require execution.

The seven original offline detector cases passed on 2026-11-27 at 9dc942f.
Hotfix regression coverage now asserts the full version string, version-specific
registry aliases and independent virt channel checks. Run:

```bash
pwsh -NoProfile -File .github/scripts/Test-UpstreamUpdate.ps1
bash .github/scripts/Test-BuildTags.sh
```

The new tests are offline; no images are built or published. The new hotfix
cases still require execution.

At b046a8c, all 12 detector cases and all 3 tag cases passed locally.
GitHub Actions run 45961642783 also passed all 12 detector assertions, but the
built-in pwsh shell propagated the final mocked native exit code 1. Explicit
successful exit codes are now returned after the detector outputs and tests;
regression assertions also check the detector's exit code. A missing image tag
is a valid detection outcome, whereas upstream inspection errors still throw.
The remote build has not yet run; dispatch the updated branch for validation.
