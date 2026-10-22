# lib/Common.ps1 — 公共函数：日志、WSL 探测、下载校验、路径转换
# 被 install.ps1 / doctor.ps1 / uninstall.ps1 dot-source 引用

$ErrorActionPreference = 'Stop'

$script:RepoRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $script:RepoRoot) { $script:RepoRoot = (Get-Location).Path }

function Write-Banner([string]$Text) {
    Write-Host ''
    Write-Host ('=' * 64) -ForegroundColor DarkCyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 64) -ForegroundColor DarkCyan
}

function Write-Step([string]$Text) { Write-Host "`n▶ $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text)   { Write-Host "  [ OK ] $Text" -ForegroundColor Green }
function Write-Warn([string]$Text) { Write-Host "  [WARN] $Text" -ForegroundColor Yellow }
function Write-Err([string]$Text)  { Write-Host "  [FAIL] $Text" -ForegroundColor Red }
function Write-Info([string]$Text) { Write-Host "  $Text" -ForegroundColor Gray }

function Test-Command([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

# wsl.exe 自身输出是 UTF-16，子进程输出是 UTF-8；分开处理避免乱码
function Invoke-WslNative {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $prev = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::Unicode
        return (& wsl.exe @Arguments 2>&1 | Out-String)
    } finally {
        [Console]::OutputEncoding = $prev
    }
}

# 流式执行（装配脚本用）：直接写控制台，避免管道编码问题；返回退出码
function Invoke-Stream {
    param([Parameter(Mandatory)][string]$FilePath, [string[]]$Arguments = @())
    & $FilePath @Arguments
    return $LASTEXITCODE
}

# 需要判断退出码的 wsl 调用（wsl.exe 自身输出是 UTF-16）
function Invoke-WslChecked {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $prev = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::Unicode
        $out = & wsl.exe @Arguments 2>&1 | Out-String
        $script:LastWslExit = $LASTEXITCODE
    } finally { [Console]::OutputEncoding = $prev }
    return $out
}

function Get-LastWslExit { return $script:LastWslExit }

function Get-WslDistros {
    $raw = Invoke-WslNative -Arguments @('-l', '-q')
    if (-not $raw) { return @() }
    return @($raw -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Test-WslDistro([string]$Name) {
    return (Get-WslDistros) -contains $Name
}

function ConvertTo-WslPath([string]$WindowsPath) {
    $full = (Resolve-Path -LiteralPath $WindowsPath -ErrorAction SilentlyContinue)
    $p = if ($full) { $full.Path } else { $WindowsPath }
    if ($p -match '^([A-Za-z]):(.*)$') {
        $drive = $Matches[1].ToLower()
        $rest = $Matches[2] -replace '\\', '/'
        return "/mnt/$drive$rest"
    }
    throw "无法转换为 WSL 路径: $WindowsPath"
}

function Get-FreeGB([string]$Path) {
    try {
        $root = [IO.Path]::GetPathRoot((Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue).Path)
        if (-not $root) { $root = [IO.Path]::GetPathRoot($Path) }
        $d = Get-PSDrive -PSProvider FileSystem -Name $root.Substring(0, 1) -ErrorAction Stop
        return [math]::Round($d.Free / 1GB, 1)
    } catch { return $null }
}

function Get-Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLower()
}

# 判断归档类型（wsl --import 支持 tar / tar.gz / tar.xz）
function Get-ArchiveKind([string]$Path) {
    $fs = [IO.File]::OpenRead($Path)
    try {
        $buf = New-Object byte[] 8
        $null = $fs.Read($buf, 0, 8)
    } finally { $fs.Dispose() }
    if ($buf[0] -eq 0x1F -and $buf[1] -eq 0x8B) { return 'gzip' }
    if ($buf[0] -eq 0xFD -and $buf[1] -eq 0x37 -and $buf[2] -eq 0x7A -and $buf[3] -eq 0x58) { return 'xz' }
    # tar 的 magic 在 257 偏移，这里用扩展名兜底
    if ($Path -match '\.tar$') { return 'tar' }
    return 'unknown'
}

# 下载：断点续传 + 重试；可选 sha256 校验。返回 $true/$false
function Invoke-Download {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile,
        [string]$Sha256 = '',
        [string]$Label = ''
    )
    if (Test-Path -LiteralPath $OutFile) {
        if ($Sha256 -and (Get-Sha256 $OutFile) -eq $Sha256) {
            Write-Ok "已存在且校验通过：$(Split-Path -Leaf $OutFile)"
            return $true
        }
    }
    $dir = Split-Path -Parent $OutFile
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    if (-not (Test-Command 'curl.exe')) {
        Write-Warn '未找到 curl.exe（Win10 1803+ 自带）。改用 Invoke-WebRequest。'
        try {
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -TimeoutSec 1800
        } catch {
            Write-Err "下载失败: $_"
            return $false
        }
    } else {
        $label = if ($Label) { $Label } else { Split-Path -Leaf $OutFile }
        Write-Info "下载 $label  ← $Url"
        & curl.exe -fL --retry 8 --retry-delay 3 --retry-all-errors -C - `
            --connect-timeout 20 --progress-bar -o $OutFile $Url
        if ($LASTEXITCODE -ne 0) {
            Write-Err "curl 退出码 $LASTEXITCODE"
            return $false
        }
    }

    if ($Sha256) {
        $actual = Get-Sha256 $OutFile
        if ($actual -ne $Sha256) {
            Write-Err "SHA256 不匹配！期望 $Sha256，实际 $actual"
            Write-Info '文件已删除，请重试或换镜像。'
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            return $false
        }
        Write-Ok "SHA256 校验通过"
    }
    return $true
}

function Get-DiskFreeWarning([string]$Path) {
    $free = Get-FreeGB $Path
    if ($null -eq $free) { return }
    if ($free -lt 30) { Write-Warn "目标盘剩余 ${free}GB，建议 ≥30GB（Kali 装完约 20-35GB）" }
    else { Write-Info "目标盘剩余 ${free}GB" }
}
