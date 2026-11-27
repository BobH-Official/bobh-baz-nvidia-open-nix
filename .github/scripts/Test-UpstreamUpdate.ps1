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
    param([string]$Name, [hashtable]$MockData, [string]$Expected)
    $mock = $MockData
    $file = New-TemporaryFile
    $previous = $env:GITHUB_OUTPUT
    try {
        $env:GITHUB_OUTPUT = $file.FullName
        & $detector -UpstreamImage $base -MyImage $my -ExpectedRevision $revision
        $out = Get-Content -LiteralPath $file.FullName
        if ($out -notcontains "should_build=$Expected" -or
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
Assert-Case 'missing version label falls back to date' @{ $upRef = $up } 'true'
Write-Host 'All seven detector cases passed.'
