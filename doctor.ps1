#Requires -Version 5.1
<#
.SYNOPSIS
    体检已安装的 CTF 环境
.EXAMPLE
    .\doctor.ps1
    .\doctor.ps1 -Distro Kali -UserName ctf
#>
[CmdletBinding()]
param(
    [string]$Distro = '',
    [string]$UserName = 'ctf'
)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $RepoRoot 'lib\Common.ps1')
. (Join-Path $RepoRoot 'lib\Launcher.ps1')

Write-Banner 'wsl-ctf-kit 体检'

if (-not (Test-Command 'wsl.exe')) { Write-Err '找不到 wsl.exe'; exit 1 }

$all = Get-WslDistros
if (-not $all -or $all.Count -eq 0) { Write-Err '没有任何 WSL 发行版，先运行 install.ps1'; exit 1 }

if ($Distro) {
    $targets = @($Distro)
} else {
    $targets = $all | Where-Object { $_ -match '^(Kali|Ubuntu)' }
}
if (-not $targets -or $targets.Count -eq 0) {
    Write-Warn "没找到 Kali/Ubuntu 发行版。当前：$($all -join ', ')"
    exit 1
}

$doctor = Join-Path $RepoRoot 'provision\doctor.sh'
if (-not (Test-Path -LiteralPath $doctor)) { Write-Err "缺少 $doctor"; exit 1 }
$wslDoctor = ConvertTo-WslPath $doctor

$results = @()
foreach ($d in $targets) {
    Write-Banner "体检：$d"
    $code = Invoke-Stream -FilePath 'wsl.exe' -Arguments @(
        '-d', $d, '-u', $UserName, '--', 'bash', $wslDoctor
    )
    if ($code -ne 0) {
        Write-Warn "以 $UserName 身份运行失败，改用发行版默认用户重试"
        $code = Invoke-Stream -FilePath 'wsl.exe' -Arguments @('-d', $d, '--', 'bash', $wslDoctor)
    }
    $results += [pscustomobject]@{ Distro = $d; ExitCode = $code }
}

Write-Banner '汇总'
foreach ($r in $results) {
    $state = if ($r.ExitCode -eq 0) { '正常' } else { "退出码 $($r.ExitCode)" }
    Write-Host ("  {0,-16} {1}" -f $r.Distro, $state)
}
Write-Host ''
Write-Info '若某项为 WARN/FAIL：重跑 install.ps1 补装，或进系统手动查看。'
