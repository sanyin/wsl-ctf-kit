# lib/Launcher.ps1 — 生成一键启动器：.cmd + Windows Terminal profile + 桌面快捷方式
# 设计要点：
#  * .cmd 只写 ASCII：.cmd 里的中文在 GBK 代码页下会把命令行拆碎（实测踩过）
#  * Terminal profile 用固定 GUID，重跑不会产生重复项
#  * 自动生成的同名 profile（source=Microsoft.WSL）会被隐藏，避免 `-p Kali` 选错

$script:KitHome = Join-Path $env:USERPROFILE '.wsl-ctf-kit'

function Get-TerminalSettingsPath {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }

    # 便携版：wt.exe 所在目录的 settings/settings.json
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wt) {
        $dir = Split-Path -Parent $wt.Source
        foreach ($rel in @('settings\settings.json', '..\settings\settings.json')) {
            $p = Join-Path $dir $rel
            if (Test-Path -LiteralPath $p) { return (Resolve-Path $p).Path }
        }
        # 便携版常见布局：<root>\terminal-x.y\WindowsTerminal.exe + <root>\settings
        $parent = Split-Path -Parent $dir
        $p = Join-Path $parent 'settings\settings.json'
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Add-TerminalProfile {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$UserName,
        [string]$TabColor = '#268BEE',
        [string]$Guid = ''
    )
    $settings = Get-TerminalSettingsPath
    if (-not $settings) {
        Write-Warn '未找到 Windows Terminal 配置，跳过 profile 注入（.cmd 启动器仍可用）'
        return $false
    }

    $backup = "$settings.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item -LiteralPath $settings -Destination $backup -Force
    Write-Info "已备份 Terminal 配置：$(Split-Path -Leaf $backup)"

    try {
        $json = Get-Content -LiteralPath $settings -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warn "Terminal 配置无法解析（可能含注释），跳过注入: $_"
        return $false
    }

    if (-not $json.profiles) { $json | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) -Force }
    if (-not $json.profiles.list) {
        $json.profiles | Add-Member -NotePropertyName list -NotePropertyValue @() -Force
    }
    $list = @($json.profiles.list)

    $cmdline = "wsl.exe -d $Distro -u $UserName --cd ~"
    $existing = $list | Where-Object { $_.guid -eq $Guid }
    if ($existing) {
        Write-Ok "Terminal profile 已存在：$Distro"
    } else {
        $name = $Distro
        if ($list | Where-Object { $_.name -eq $name }) { $name = "$Distro (CTF Kit)" }
        $list += [pscustomobject]@{
            commandline = $cmdline
            guid        = $Guid
            hidden      = $false
            name        = $name
            tabColor    = $TabColor
        }
        Write-Ok "已添加 Terminal profile：$name"
    }

    # 隐藏 Windows Terminal 自动生成的同名项，避免 `wt -p Kali` 命中歧义
    foreach ($p in $list) {
        if ($p.source -eq 'Microsoft.WSL' -and $p.name -eq $Distro -and $p.guid -ne $Guid) {
            $p.hidden = $true
            if ($p.name -notmatch '\(自动生成') { $p.name = "$Distro (自动生成的重复项)" }
        }
    }

    $json.profiles.list = $list
    try {
        $json | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $settings -Encoding UTF8
        Write-Ok 'Terminal 配置已保存'
        return $true
    } catch {
        Write-Warn "写回 Terminal 配置失败（用备份还原）: $_"
        Copy-Item -LiteralPath $backup -Destination $settings -Force
        return $false
    }
}

function New-LauncherCmd {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$UserName
    )
    if (-not (Test-Path $script:KitHome)) { New-Item -ItemType Directory -Force -Path $script:KitHome | Out-Null }
    $cmd = Join-Path $script:KitHome "Open-$Distro.cmd"
    $lines = @(
        '@echo off',
        "rem wsl-ctf-kit launcher for $Distro (keep this file ASCII-only)",
        'setlocal',
        'where wt.exe >nul 2>nul',
        'if %errorlevel%==0 (',
        "  start """" wt.exe -p $Distro",
        '  exit /b 0',
        ')',
        "wsl.exe -d $Distro -u $UserName --cd ~"
    )
    Set-Content -LiteralPath $cmd -Value ($lines -join "`r`n") -Encoding ASCII
    Write-Ok "启动器：$cmd"
    return $cmd
}

function New-DesktopShortcut {
    param(
        [Parameter(Mandatory)][string]$TargetCmd,
        [Parameter(Mandatory)][string]$Name,
        [string]$IconPath = ''
    )
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $lnk = Join-Path $desktop "$Name.lnk"
        $sh = New-Object -ComObject WScript.Shell
        $s = $sh.CreateShortcut($lnk)
        $s.TargetPath = $TargetCmd
        $s.WorkingDirectory = Split-Path -Parent $TargetCmd
        if ($IconPath -and (Test-Path -LiteralPath $IconPath)) { $s.IconLocation = "$IconPath,0" }
        $s.Description = "wsl-ctf-kit: 一键启动 $Name"
        $s.Save()
        Write-Ok "桌面快捷方式：$lnk"
        return $lnk
    } catch {
        Write-Warn "创建桌面快捷方式失败: $_"
        return $null
    }
}
