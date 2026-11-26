[CmdletBinding()]
param (
    [string]$UpstreamImage,
    [Parameter(Mandatory)]
    [string]$MyImage,
    [string]$Channel = 'latest'
)
$ErrorActionPreference = 'Stop'

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
$version = $upstream.Labels.'org.opencontainers.image.version'
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

# A failed target lookup is never evidence of a matching build.
$existingRaw = skopeo inspect --override-os linux --override-arch amd64 "docker://$target" 2>$null
if ($LASTEXITCODE -eq 0) {
    $existing = $existingRaw | ConvertFrom-Json
    $shouldBuild = ($existing.Labels.'org.opencontainers.image.base.digest' -ne $digest) -or
        ($existing.Labels.'org.opencontainers.image.base.name' -ne $UpstreamImage) -or
        ($existing.Labels.'io.bobh.upstream.version' -ne $version)
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
