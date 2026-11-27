[CmdletBinding()]
param (
    [string]$UpstreamImage,
    [Parameter(Mandatory)]
    [string]$MyImage,
    [string]$Channel = 'latest',
    [string]$ExpectedRevision
)
$ErrorActionPreference = 'Stop'
# Handle native command failures explicitly: a missing published tag is expected.
$PSNativeCommandUseErrorActionPreference = $false

# Single source of truth: Containerfile's default BASE_IMAGE.
if (-not $UpstreamImage) {
    $containerfile = Join-Path $PSScriptRoot '../../Containerfile'
    $match = [regex]::Match((Get-Content $containerfile -Raw), '(?m)^ARG BASE_IMAGE=(\S+)\s*$')
    if (-not $match.Success) { throw 'Missing ARG BASE_IMAGE in Containerfile' }
    $UpstreamImage = $match.Groups[1].Value
}
if ($Channel -notmatch '^[a-z0-9][a-z0-9._-]*$') { throw 'Invalid channel' }

$raw = skopeo inspect --override-os linux --override-arch amd64 "docker://$UpstreamImage"
if ($LASTEXITCODE -ne 0) { throw "Could not inspect upstream: $UpstreamImage" }
$upstream = $raw | ConvertFrom-Json
# Preserve the complete version string, including hotfix suffixes (e.g. 45.20261125.1).
$version = [string]$upstream.Labels.'org.opencontainers.image.version'
if ([string]::IsNullOrWhiteSpace($version)) {
    $version = ([datetimeoffset]::Parse($upstream.Created)).UtcDateTime.ToString('yyyyMMdd')
}
$digest = $upstream.Digest
if ($digest -notmatch '^sha256:[0-9a-f]{64}$') { throw "Invalid upstream digest: $digest" }
if ($version -notmatch '^[A-Za-z0-9_][A-Za-z0-9_.-]{0,95}$') { throw "Invalid upstream version tag: $version" }
$baseRef = "$($upstream.Name)@$digest"
$prefix = if ($Channel -eq 'latest') { 'upstream.' } else { "$Channel.upstream." }
$target = "${MyImage}:$prefix$version"
$shouldBuild = $true

# Both aliases must refer to the same completed release. A failed lookup
# or a partially promoted release must never cause a scheduled skip.
$versionRaw = skopeo inspect --override-os linux --override-arch amd64 "docker://$target" 2>$null
if ($LASTEXITCODE -eq 0) {
    $existing = $versionRaw | ConvertFrom-Json
    $channelRaw = skopeo inspect --override-os linux --override-arch amd64 "docker://${MyImage}:$Channel" 2>$null
    if ($LASTEXITCODE -eq 0) {
        $current = $channelRaw | ConvertFrom-Json
        $shouldBuild = ($existing.Labels.'org.opencontainers.image.base.digest' -cne $digest) -or
            ($existing.Labels.'org.opencontainers.image.base.name' -cne $UpstreamImage) -or
            ($existing.Labels.'io.bobh.upstream.version' -cne $version) -or
            (-not $existing.Digest) -or
            ($current.Digest -cne $existing.Digest) -or
            ($ExpectedRevision -and ($existing.Labels.'org.opencontainers.image.revision' -cne $ExpectedRevision))
    }
}

$values = [ordered]@{
    upstream_image = $UpstreamImage
    upstream_version = $version
    upstream_digest = $digest
    base_image_ref = $baseRef
    should_build = $shouldBuild.ToString().ToLowerInvariant()
}
foreach ($entry in $values.GetEnumerator()) {
    $line = "$($entry.Key)=$($entry.Value)"
    Write-Host $line
    if ($env:GITHUB_OUTPUT) { Add-Content -LiteralPath $env:GITHUB_OUTPUT -Value $line }
}

# A missing published tag is a successful detection result, not a script error.
# GitHub Actions forwards LASTEXITCODE even after successful PowerShell cmdlets.
exit 0
