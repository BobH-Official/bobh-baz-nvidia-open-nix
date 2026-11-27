# Offline regression tests for the detector; no registry, signing or build.
$ErrorActionPreference = 'Stop'
$detector = Join-Path $PSScriptRoot 'Check-UpstreamUpdate.ps1'
$base = 'ghcr.io/ublue-os/bazzite-nvidia-open:stable'
$my = 'ghcr.io/example/test'
$version = '45.20261125'
$upDigest = 'sha256:' + ('a' * 64)
$ourDigest = 'sha256:' + ('b' * 64)
$revision = 'c' * 40
$up = @{ Name = 'ghcr.io/ublue-os/bazzite-nvidia-open'; Digest = $upDigest; Created = '2026-11-25T12:00:00Z'; Labels = @{ 'org.opencontainers.image.version' = $version } }
$published = @{ Digest = $ourDigest; Labels = @{
    'org.opencontainers.image.base.digest' = $upDigest
    'org.opencontainers.image.base.name' = $base
    'io.bobh.upstream.version' = $version
    'org.opencontainers.image.revision' = $revision
} }

# Child script resolves this function rather than the external skopeo binary.
function skopeo {
    $ref = $args[-1]
    if ($mock.ContainsKey($ref)) {
        $global:LASTEXITCODE = 0
        return ($mock[$ref] | ConvertTo-Json -Depth 8 -Compress)
    }
    $global:LASTEXITCODE = 1
}

function Assert-Case {
    param(
        [string]$Name, [hashtable]$MockData, [string]$Expected,
        [string]$ExpectedVersion = $version, [string]$Channel = 'latest'
    )
    $mock = $MockData
    $file = New-TemporaryFile
    $previous = $env:GITHUB_OUTPUT
    try {
        $env:GITHUB_OUTPUT = $file.FullName
        & $detector -UpstreamImage $base -MyImage $my -ExpectedRevision $revision -Channel $Channel
        if ($LASTEXITCODE -ne 0) { throw "FAIL: $Name (detector exit code $LASTEXITCODE)" }
        $out = Get-Content -LiteralPath $file.FullName
        if ($out -notcontains "should_build=$Expected" -or
            $out -notcontains "upstream_version=$ExpectedVersion" -or
            $out -notcontains "upstream_digest=$upDigest" -or
            $out -notcontains "base_image_ref=$($up.Name)@$upDigest") {
            throw "FAIL: $Name"
        }
        Write-Host "PASS: $Name"
    } finally {
        $env:GITHUB_OUTPUT = $previous
        Remove-Item -LiteralPath $file.FullName
    }
}

$upRef = "docker://$base"
$versionRef = "docker://${my}:upstream.$version"
$latestRef = "docker://${my}:latest"
Assert-Case 'missing upstream tag' @{ $upRef = $up } 'true'
Assert-Case 'matching completed release' @{ $upRef = $up; $versionRef = $published; $latestRef = $published } 'false'
Assert-Case 'version published but latest missing' @{ $upRef = $up; $versionRef = $published } 'true'
Assert-Case 'latest points elsewhere' @{ $upRef = $up; $versionRef = $published; $latestRef = @{ Digest = 'sha256:' + ('d' * 64) } } 'true'
$published.Labels.'org.opencontainers.image.base.digest' = 'sha256:' + ('e' * 64)
Assert-Case 'same version, changed base digest' @{ $upRef = $up; $versionRef = $published; $latestRef = $published } 'true'
$published.Labels.'org.opencontainers.image.base.digest' = $upDigest
$published.Labels.'org.opencontainers.image.revision' = 'f' * 40
Assert-Case 'changed repository revision' @{ $upRef = $up; $versionRef = $published; $latestRef = $published } 'true'
$published.Labels.'org.opencontainers.image.revision' = $revision
$up.Labels.Remove('org.opencontainers.image.version')
Assert-Case 'missing version label falls back to date' @{ $upRef = $up } 'true' '20261125'

# Versions are opaque strings, not decimals or dates. The full hotfix
# suffix must be used for both registry lookups and output metadata.
$hotfix = '45.20261125.1'
$hotfixRef = "docker://${my}:upstream.$hotfix"
$up.Labels.'org.opencontainers.image.version' = $hotfix
Assert-Case 'hotfix is not skipped because base release exists' @{ $upRef = $up; $versionRef = $published; $latestRef = $published } 'true' $hotfix
$published.Labels.'io.bobh.upstream.version' = $hotfix
Assert-Case 'matching hotfix skips rebuild' @{ $upRef = $up; $hotfixRef = $published; $latestRef = $published } 'false' $hotfix
Assert-Case 'hotfix alias missing but latest matches' @{ $upRef = $up; $latestRef = $published } 'true' $hotfix
$virtRef = "docker://${my}:virt.upstream.$hotfix"
$virtChannel = "docker://${my}:virt"
Assert-Case 'matching virt hotfix skips rebuild independently' @{ $upRef = $up; $virtRef = $published; $virtChannel = $published } 'false' $hotfix 'virt'
Assert-Case 'ordinary hotfix cannot satisfy virt channel' @{ $upRef = $up; $hotfixRef = $published; $latestRef = $published } 'true' $hotfix 'virt'
Write-Host 'All twelve detector cases passed.'
# Report success only after all assertions have passed.
exit 0
