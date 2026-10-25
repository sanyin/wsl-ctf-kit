#Requires -Version 5.1
<#
.SYNOPSIS
    wsl-ctf-kit —— Windows 上的 CTF 一键环境（WSL2 Kali + Ubuntu）

.DESCRIPTION
    自动完成：下载官方镜像 → 导入 WSL2 → 建用户 → 换国内源 → 装 CTF 工具链 →
    配 zsh/pwntools/pwndbg → 生成一键启动器（Windows Terminal profile + 桌面快捷方式）。

    镜像只在安装时从官方/国内镜像站下载，仓库本身不含镜像。

.PARAMETER Distro
    both（默认）/ kali / ubuntu

.PARAMETER Location
    发行版存放目录，默认 C:\WSL

.PARAMETER UserName
    Linux 用户名，默认 ctf

.PARAMETER Password
    Linux 用户密码（同时是 sudo 密码），默认 ctf

.EXAMPLE
    .\install.ps1
    装 Kali + Ubuntu，全部默认。

.EXAMPLE
    .\install.ps1 -Distro kali -WithDesktop
    只装 Kali，并带 Win-KeX 图形桌面。

.EXAMPLE
    .\install.ps1 -DryRun
    只检查环境并解析下载地址，不下载不安装。
#>
[CmdletBinding()]
param(
    [ValidateSet('both', 'kali', 'ubuntu')][string]$Distro = 'both',
    [string]$Location = '',
    [string]$UserName = 'ctf',
    [string]$Password = 'ctf',
    [switch]$WithDesktop,
    [switch]$WithDocker,
    [switch]$NoLauncher,
    [switch]$SkipProvision,
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$KitVersion = '1.0.0'

# 让子进程（bash/apt）的 UTF-8 中文在日志里正常显示
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $RepoRoot 'lib\Common.ps1')
. (Join-Path $RepoRoot 'lib\Launcher.ps1')

# ---------------------------------------------------------------- 镜像地址
# Kali：官方 WSL rootfs（版本目录长期保留；升级只需改这两行）
$KaliUrl = 'https://kali.download/wsl-images/kali-2026.2/kali-linux-2026.2-wsl-rootfs-amd64.wsl'
$KaliSha = '1b172389e9109e9bb0c3d1fa18eda078271484dbcef8dbee4aab8b1f369466c6'
$KaliFallbacks = @(
    'https://kali.download/wsl-images/kali-2026.2/kali-linux-2026.2-wsl-rootfs-amd64.wsl'
)

# Ubuntu：官方 ubuntu-base rootfs（国内镜像站有同步，比整包 .wsl 小很多也快很多）
$UbuntuMirrors = @(
    'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu-base/releases/24.04/release/',
    'https://mirrors.ustc.edu.cn/ubuntu-cdimage/ubuntu-base/releases/24.04/release/',
    'https://mirrors.aliyun.com/ubuntu-cdimage/ubuntu-base/releases/24.04/release/',
    'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/'
)

# ---------------------------------------------------------------- 环境检查
function Test-Preflight {
    Write-Step '检查 Windows / WSL2 环境'

    $build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
    if ($build -lt 19041) {
        Write-Err "Windows 版本过低（Build $build）。WSL2 需要 Win10 2004 (19041) 以上。"
        return $false
    }
    Write-Ok "Windows Build $build"

    if (-not (Test-Command 'wsl.exe')) {
        Write-Err '找不到 wsl.exe。请先启用「适用于 Linux 的 Windows 子系统」功能。'
        Write-Info '管理员 PowerShell 执行： wsl --install --no-distribution'
        return $false
    }

    $ver = Invoke-WslNative -Arguments @('--version')
    if ($ver -match 'WSL') {
        $line = ($ver -split "`r?`n" | Where-Object { $_ -match '\d+\.\d+' } | Select-Object -First 1)
        Write-Ok "WSL 已安装：$($line.Trim())"
    } else {
        Write-Warn '未取到 WSL 版本，可能是较旧的 inbox 版本；建议先运行 wsl --update'
    }

    $vm = (Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).HypervisorPresent
    if ($vm) { Write-Ok '虚拟化已就绪（Hyper-V 平台可用）' }
    else {
        Write-Warn '未检测到 Hypervisor。若 WSL 启动失败，请在 BIOS 打开 VT-x/AMD-V，'
        Write-Info '并以管理员身份运行： wsl --install --no-distribution'
    }
    return $true
}

function Resolve-InstallTarget {
    if ($Location) {
        $target = $Location
    } else {
        $target = Join-Path $env:SystemDrive 'WSL'
    }
    if (-not (Test-Path -LiteralPath $target)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $target | Out-Null }
    }
    return $target
}

function Resolve-DistroName([string]$Base) {
    if (-not (Test-WslDistro $Base)) { return $Base }
    $alt = "$Base-CTF"
    if (-not (Test-WslDistro $alt)) {
        Write-Warn "已存在名为 $Base 的发行版，本次安装改用 $alt"
        return $alt
    }
    $i = 2
    while (Test-WslDistro "$alt$i") { $i++ }
    $name = "$alt$i"
    Write-Warn "已存在 $Base 与 $alt，本次安装改用 $name"
    return $name
}

# 判断某个发行版是不是本工具装的（看 /etc/wsl.conf 里的标记），避免重跑时重复安装
function Get-KitDistro([string]$Base) {
    $cands = Get-WslDistros | Where-Object { $_ -match "^$Base" }
    foreach ($c in $cands) {
        $out = Invoke-WslChecked -Arguments @(
            '-d', $c, '-u', 'root', '--', 'bash', '-c',
            '(test -f /etc/wsl-ctf-kit || grep -q wsl-ctf-kit /etc/wsl.conf) && echo KIT'
        )
        if ($out -match 'KIT') { return $c }
    }
    return $null
}

# ---------------------------------------------------------------- 镜像解析
function Resolve-UbuntuImage {
    $mirror = $null
    $files = $null
    foreach ($m in $UbuntuMirrors) {
        try {
            Write-Info "查询镜像目录: $m"
            $html = (Invoke-WebRequest -Uri $m -UseBasicParsing -TimeoutSec 25).Content
            $names = [regex]::Matches($html, 'ubuntu-base-[0-9.]+-base-amd64\.tar\.gz') |
                ForEach-Object { $_.Value } | Sort-Object -Unique
            if ($names) { $mirror = $m; $files = $names; break }
        } catch {
            Write-Info "  不可用，换下一个"
        }
    }
    if (-not $mirror) { return $null }

    $latest = $files |
        Sort-Object { [version](($_ -replace '^ubuntu-base-', '') -replace '-base-amd64\.tar\.gz$', '') } |
        Select-Object -Last 1

    $sha = ''
    $tmpSums = Join-Path $env:TEMP ('ubuntu-SHA256SUMS-' + [guid]::NewGuid().ToString('N'))
    try {
        Invoke-WebRequest -Uri ($mirror + 'SHA256SUMS') -OutFile $tmpSums -UseBasicParsing -TimeoutSec 25
        $lines = Get-Content -LiteralPath $tmpSums -Encoding UTF8
        $hit = $lines | Where-Object { $_ -match [regex]::Escape($latest) } | Select-Object -First 1
        if ($hit -and $hit -match '^([a-f0-9]{64})') { $sha = $Matches[1] }
    } catch {
        Write-Info '  未取到 SHA256SUMS（跳过校验）'
    } finally {
        if (Test-Path -LiteralPath $tmpSums) { Remove-Item -LiteralPath $tmpSums -Force -ErrorAction SilentlyContinue }
    }

    return [pscustomobject]@{ Url = $mirror + $latest; File = $latest; Sha256 = $sha }
}

# ---------------------------------------------------------------- 装配
function Invoke-Provision {
    param([string]$DistroName)

    $setup = Join-Path $RepoRoot 'provision\setup.sh'
    if (-not (Test-Path -LiteralPath $setup)) { Write-Err "缺少装配脚本: $setup"; return $false }

    # 兜底：仓库若被 Git(autocrlf) 或编辑器转成 CRLF，bash 会报 $'\r': command not found。
    # .gitattributes 已经强制 LF，这里再就地清一遍，保证从任何来源拷来的仓库都能跑。
    $provDir = ConvertTo-WslPath (Join-Path $RepoRoot 'provision')
    $sedCmd = "sed -i 's/\r`$//' $provDir/*.sh $provDir/*.tpl 2>/dev/null || true"
    & wsl.exe -d $DistroName -u root -- bash -c $sedCmd | Out-Null

    $wslSetup = ConvertTo-WslPath $setup
    $logDir = Join-Path $Location 'logs'
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
    $wslLog = (ConvertTo-WslPath $logDir) + "/provision-$DistroName.log"

    $flavor = if ($DistroName -match '^[Kk]ali') { 'kali' } else { 'ubuntu' }
    $desktopFlag = if ($WithDesktop -and $flavor -eq 'kali') { '1' } else { '0' }
    $dockerFlag = if ($WithDocker) { '1' } else { '0' }

    Write-Step "装配 $DistroName （日志：$logDir\provision-$DistroName.log）"
    Write-Info '包含：换源、基础工具、CTF 工具链、zsh、pwntools/pwndbg。首次约 10-30 分钟。'

    $args = @(
        '-d', $DistroName, '-u', 'root', '--',
        'env', "CTF_USER=$UserName", "CTF_PASS=$Password", "CTF_FLAVOR=$flavor",
        "CTF_WITH_DESKTOP=$desktopFlag", "CTF_WITH_DOCKER=$dockerFlag", "CTF_LOG=$wslLog",
        'bash', $wslSetup
    )
    $code = Invoke-Stream -FilePath 'wsl.exe' -Arguments $args
    if ($code -ne 0) {
        Write-Err "装配脚本退出码 $code，可查看日志后重跑："
        Write-Info "wsl -d $DistroName -u root -- env CTF_USER=$UserName CTF_FLAVOR=$flavor bash $wslSetup"
        return $false
    }
    return $true
}

function Install-FromImage {
    param(
        [string]$DistroName,
        [string]$ImagePath
    )
    $dest = Join-Path $Location $DistroName
    if (Test-Path -LiteralPath $dest) {
        if (-not $Force) { Write-Err "$dest 已存在，跳过（想覆盖请加 -Force）"; return $false }
        Remove-Item -LiteralPath $dest -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null

    $kind = Get-ArchiveKind $ImagePath
    if ($kind -eq 'unknown') {
        Write-Err "无法识别的镜像格式：$ImagePath"
        Write-Info 'wsl --import 支持 tar / tar.gz / tar.xz'
        return $false
    }

    Write-Step "导入 $DistroName → $dest"
    $out = Invoke-WslChecked -Arguments @('--import', $DistroName, $dest, $ImagePath, '--version', '2')
    if ((Get-LastWslExit) -ne 0) {
        Write-Err "导入失败：$out"
        return $false
    }
    Write-Ok "$DistroName 已注册"
    return $true
}

function Install-Kali {
    $existing = Get-KitDistro 'Kali'
    if ($existing -and -not $Force) {
        Write-Warn "检测到已安装的 $existing（wsl-ctf-kit 标记），跳过。-Force 可重装"
        return $existing
    }
    if ($existing -and $Force) {
        Write-Warn "强制重装：先注销 $existing"
        [void](Invoke-WslChecked -Arguments @('--unregister', $existing))
    }
    $name = Resolve-DistroName 'Kali'
    $img = Join-Path $Location '_cache\kali-rootfs.wsl'
    if ($DryRun) {
        Write-Info "[DryRun] Kali 镜像：$KaliUrl"
        Write-Info "[DryRun] 校验：$KaliSha"
        return $null
    }
    Write-Step '下载 Kali WSL rootfs（约 236MB，官方源；无国内镜像，慢时可中断重跑续传）'
    $ok = $false
    foreach ($u in $KaliFallbacks) {
        if (Invoke-Download -Url $u -OutFile $img -Sha256 $KaliSha -Label 'Kali rootfs') { $ok = $true; break }
    }
    if (-not $ok) { Write-Err 'Kali 镜像下载失败'; return $null }

    if (-not (Install-FromImage -DistroName $name -ImagePath $img)) { return $null }
    return $name
}

function Install-Ubuntu {
    $existing = Get-KitDistro 'Ubuntu'
    if ($existing -and -not $Force) {
        Write-Warn "检测到已安装的 $existing（wsl-ctf-kit 标记），跳过。-Force 可重装"
        return $existing
    }
    if ($existing -and $Force) {
        Write-Warn "强制重装：先注销 $existing"
        [void](Invoke-WslChecked -Arguments @('--unregister', $existing))
    }
    $name = Resolve-DistroName 'Ubuntu'
    $imgInfo = Resolve-UbuntuImage
    if (-not $imgInfo) {
        Write-Err '未能解析 Ubuntu 镜像地址（网络不通？）'
        return $null
    }

    if ($DryRun) {
        Write-Info "[DryRun] Ubuntu 镜像：$($imgInfo.Url)"
        if ($imgInfo.Sha256) { Write-Info "[DryRun] 校验：$($imgInfo.Sha256)" }
        return $null
    }

    $img = Join-Path $Location ('_cache\' + $imgInfo.File)
    Write-Step "下载 Ubuntu Base（$(($imgInfo.File -split '-')[2])，约 30MB）"
    if (-not (Invoke-Download -Url $imgInfo.Url -OutFile $img -Sha256 $imgInfo.Sha256 -Label 'Ubuntu Base')) {
        Write-Err 'Ubuntu 镜像下载失败'; return $null
    }

    if (-not (Install-FromImage -DistroName $name -ImagePath $img)) { return $null }
    return $name
}

# ---------------------------------------------------------------- 收尾
function New-Launchers([string[]]$Distros) {
    if ($NoLauncher) { return }
    Write-Step '生成一键启动器'

    $map = @(
        @{ Name = 'Kali';   Color = '#268BEE'; Guid = '{7e3a9c1d-2b4f-4a86-9c15-6d0f2a8b4e71}' },
        @{ Name = 'Ubuntu'; Color = '#E95420'; Guid = '{4c1f2b3d-5e6a-4b7c-8d9e-0f1a2b3c4d5e}' }
    )
    foreach ($d in $Distros) {
        if (-not $d) { continue }
        $key = if ($d -match '^[Kk]ali') { 'Kali' } else { 'Ubuntu' }
        $m = $map | Where-Object { $_.Name -eq $key }
        $cmd = New-LauncherCmd -Distro $d -UserName $UserName
        [void](Add-TerminalProfile -Distro $d -UserName $UserName -TabColor $m.Color -Guid $m.Guid)

        $icon = Join-Path $Location "$d\shortcut.ico"
        [void](New-DesktopShortcut -TargetCmd $cmd -Name "Open-$d" -IconPath $icon)

        # 装了桌面（-WithDesktop）就额外给一个「打开 Kali 桌面」的快捷方式
        if ($WithDesktop -and $d -match '^[Kk]ali') {
            [void](New-DesktopLauncher -Distro $d -UserName $UserName -IconPath $icon)
        }
    }
}

function Write-Summary([string[]]$Installed) {
    Write-Banner '安装完成'
    if (-not $Installed -or $Installed.Count -eq 0) {
        Write-Warn '本次没有新装发行版。'
        return
    }
    foreach ($d in $Installed) {
        if (-not $d) { continue }
        Write-Host "  $d" -ForegroundColor Green
        Write-Host "    启动: wsl -d $d    （或桌面快捷方式 Open-$d）" -ForegroundColor Gray
        Write-Host "    用户: $UserName   密码: $Password  → 进去后建议 passwd 改掉" -ForegroundColor Gray
    }
    Write-Host ''
    Write-Info "体检: .\doctor.ps1"
    Write-Info "卸载: .\uninstall.ps1 -Distro <名字>"
}

# ---------------------------------------------------------------- 主流程
Write-Banner "wsl-ctf-kit v$KitVersion  ·  Windows CTF 一键环境"

if (-not (Test-Preflight)) { exit 1 }

$Location = Resolve-InstallTarget
Write-Info "安装目录: $Location"
Get-DiskFreeWarning $Location
$plan = switch ($Distro) {
    'both'   { @('Kali', 'Ubuntu') }
    'kali'   { @('Kali') }
    'ubuntu' { @('Ubuntu') }
}
Write-Info "计划安装: $($plan -join ' + ')"

if ($DryRun) {
    Write-Step 'DryRun：只解析地址，不下载不安装'
    if ($plan -contains 'Kali') {
        Write-Info "Kali   → $KaliUrl"
        Write-Info "         sha256 = $KaliSha（固定校验）"
    }
    if ($plan -contains 'Ubuntu') {
        $u = Resolve-UbuntuImage
        if ($u) {
            Write-Info "Ubuntu → $($u.Url)"
            if ($u.Sha256) { Write-Info "         sha256 = $($u.Sha256)" }
            else { Write-Info '         未取到 SHA256SUMS（将跳过校验）' }
        } else {
            Write-Err 'Ubuntu 镜像地址解析失败（网络不通？）'
        }
    }
    Write-Info "目标目录 → $Location"
    exit 0
}

$installed = @()
foreach ($p in $plan) {
    if ($p -eq 'Kali') {
        $n = Install-Kali
        if ($n) {
            $installed += $n
            if (-not $SkipProvision) { [void](Invoke-Provision -DistroName $n) }
        }
    } else {
        $n = Install-Ubuntu
        if ($n) {
            $installed += $n
            if (-not $SkipProvision) { [void](Invoke-Provision -DistroName $n) }
        }
    }
}

# wsl.conf 里的默认用户/systemd 需要重启发行版才生效
foreach ($d in $installed) {
    if (-not $d) { continue }
    [void](Invoke-WslChecked -Arguments @('--terminate', $d))
}

New-Launchers $installed
Write-Summary $installed
