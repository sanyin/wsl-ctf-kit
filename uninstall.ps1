#Requires -Version 5.1
<#
.SYNOPSIS
    卸载 wsl-ctf-kit 装出来的发行版（会删除对应的 ext4.vhdx，不可恢复）
.EXAMPLE
    .\uninstall.ps1 -Distro Kali
    .\uninstall.ps1 -Distro all -Yes
#>
[CmdletBinding()]
param(
    # 发行版真实名字（如 Kali / Ubuntu-CTF）；留空或 all = 所有本工具装的发行版
    [string]$Distro = '',
    [string]$Location = '',
    [switch]$KeepFiles,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $RepoRoot 'lib\Common.ps1')
. (Join-Path $RepoRoot 'lib\Launcher.ps1')

Write-Banner 'wsl-ctf-kit 卸载'

$all = Get-WslDistros
if (-not $all -or $all.Count -eq 0) { Write-Warn '没有已安装的发行版'; exit 0 }

# 默认只挑本 kit 的命名
$targets = if ($Distro -and $Distro -ne 'all') {
    @($all | Where-Object { $_ -eq $Distro -or $_ -like "$Distro*" })
} else {
    @($all | Where-Object { $_ -match '^(Kali|Ubuntu)' })
}
if ($targets.Count -eq 0) { Write-Warn "没找到匹配的发行版。当前：$($all -join ', ')"; exit 0 }

if (-not $Location) { $Location = Join-Path $env:SystemDrive 'WSL' }

Write-Host ''
Write-Host '将要删除：' -ForegroundColor Yellow
foreach ($t in $targets) {
    $dir = Join-Path $Location $t
    Write-Host "  发行版 $t" -ForegroundColor Yellow
    if (Test-Path -LiteralPath $dir) { Write-Host "    磁盘目录 $dir" -ForegroundColor DarkYellow }
}
Write-Host ''

if (-not $Yes) {
    $ans = Read-Host '确认卸载？输入 yes 继续（其他任意键取消）'
    if ($ans -ne 'yes') { Write-Info '已取消'; exit 0 }
}

$guidMap = @{
    'Kali'   = '{7e3a9c1d-2b4f-4a86-9c15-6d0f2a8b4e71}'
    'Ubuntu' = '{4c1f2b3d-5e6a-4b7c-8d9e-0f1a2b3c4d5e}'
}

foreach ($t in $targets) {
    Write-Step "卸载 $t"
    [void](Invoke-WslChecked -Arguments @('--terminate', $t))
    $out = Invoke-WslChecked -Arguments @('--unregister', $t)
    if ((Get-LastWslExit) -ne 0) { Write-Err "注销失败：$out"; continue }
    Write-Ok "已注销 $t"

    if (-not $KeepFiles) {
        $dir = Join-Path $Location $t
        if (Test-Path -LiteralPath $dir) {
            $resolved = (Resolve-Path -LiteralPath $dir).Path
            if ($resolved -like "$Location*") {
                Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
                Write-Ok "已删除目录 $resolved"
            } else {
                Write-Warn "路径校验未通过，未删除：$resolved"
            }
        }
    }

    # 清理启动器与桌面快捷方式
    $cmd = Join-Path $script:KitHome "Open-$t.cmd"
    if (Test-Path -LiteralPath $cmd) { Remove-Item -LiteralPath $cmd -Force; Write-Ok "已删除 $cmd" }
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) "Open-$t.lnk"
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force; Write-Ok "已删除桌面快捷方式" }

    # 移除 Terminal profile
    $key = if ($t -match '^Kali') { 'Kali' } else { 'Ubuntu' }
    $guid = $guidMap[$key]
    $settings = Get-TerminalSettingsPath
    if ($settings -and $guid) {
        try {
            $json = Get-Content -LiteralPath $settings -Raw -Encoding UTF8 | ConvertFrom-Json
            $before = @($json.profiles.list).Count
            $json.profiles.list = @($json.profiles.list | Where-Object { $_.guid -ne $guid })
            if (@($json.profiles.list).Count -ne $before) {
                Copy-Item -LiteralPath $settings -Destination "$settings.bak-" -Force -ErrorAction SilentlyContinue
                $json | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $settings -Encoding UTF8
                Write-Ok '已移除 Windows Terminal profile'
            }
        } catch { Write-Warn "清理 Terminal profile 失败: $_" }
    }
}

Write-Banner '完成'
Write-Info '缓存镜像仍保留在 <Location>\_cache，可手动删除。'
