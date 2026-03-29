param (
    [Parameter(Mandatory = $true)]
    [string]$UpstreamImage,

    [Parameter(Mandatory = $true)]
    [string]$MyImage,

    [Parameter(Mandatory = $true)]
    [string]$GithubActor,

    [Parameter(Mandatory = $true)]
    [string]$GithubToken
)

Write-Host "=> 正在检查上游镜像: $UpstreamImage"

# 1. 使用 skopeo 获取上游镜像的元数据并转换为 PowerShell 对象
$inspectOutput = skopeo inspect "docker://$UpstreamImage" | ConvertFrom-Json

# 尝试获取 version label
$upstreamVersion = $inspectOutput.Labels.'org.opencontainers.image.version'

# 如果 version 为空，则降级使用创建日期 (格式化为 YYYYMMDD)
if ([string]::IsNullOrWhiteSpace($upstreamVersion)) {
    Write-Host "=> 未找到明确的 version label，将使用镜像创建日期..."
    $created = $inspectOutput.Created
    $upstreamVersion = [datetime]::Parse($created).ToUniversalTime().ToString("yyyyMMdd")
}

Write-Host "=> 探测到的上游版本号: $upstreamVersion"

# 2. 检查我们自己的仓库是否已经有该标签
$expectedLocalTag = "upstream.$upstreamVersion"
$myFullImage = "docker://$($MyImage):$expectedLocalTag"

Write-Host "=> 正在比对本地仓库首选镜像 (Upstream 锚点): $myFullImage"

# 隐藏 skopeo 的错误输出，通过 $LASTEXITCODE 判断是否存在
$null = skopeo inspect --creds "$($GithubActor):$($GithubToken)" $myFullImage 2>$null

$shouldBuild = $false
if ($LASTEXITCODE -eq 0) {
    Write-Host "=>  我们的仓库中已存在首选版本 $expectedLocalTag，跳过构建。"
    $shouldBuild = "false"
} else {
    Write-Host "=>  未找到首选版本 $expectedLocalTag，开始检查 Backup (日期+1) 版本..."
    
    # 提取上游镜像的精确创建时间，加上 1 天，并格式化为 YYYYMMDD
    $createdDateString = $inspectOutput.Created
    $upstreamDate = [datetime]::Parse($createdDateString).ToUniversalTime()
    $backupDateTag = $upstreamDate.AddDays(1).ToString("yyyyMMdd")
    
    $myBackupImage = "docker://$($MyImage):$backupDateTag"
    Write-Host "=> 正在比对本地仓库 Backup 镜像: $myBackupImage"
    
    $null = skopeo inspect --creds "$($GithubActor):$($GithubToken)" $myBackupImage 2>$null
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "=>  我们的仓库中已存在 Backup 版本 $backupDateTag，跳过构建。"
        $shouldBuild = "false"
    } else {
        Write-Host "=>  首选版本和 Backup 版本均未找到，准备触发构建！"
        $shouldBuild = "true"
    }
}

# 3. 将结果输出给 GitHub Actions 环境
# 判断是否在 GitHub Actions 环境中运行
if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "upstream_version=$upstreamVersion"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "should_build=$shouldBuild"
    Write-Host "=> 已将变量写入 GITHUB_OUTPUT"
}
else {
    Write-Host "=> (本地测试环境) 输出变量: should_build=$shouldBuild, upstream_version=$upstreamVersion"
}
