# lib/Launcher.ps1 — 生成一键启动器：.cmd + Windows Terminal profile + 桌面快捷方式
# 设计要点：
#  * .cmd 只写 ASCII：.cmd 里的中文在 GBK 代码页下会把命令行拆碎（实测踩过）
#  * Terminal profile 用固定 GUID，重跑不会产生重复项
#  * 自动生成的同名 profile（source=Microsoft.WSL）会被隐藏，避免 `-p Kali` 选错

$script:KitHome = Join-Path $env:USERPROFILE '.wsl-ctf-kit'

function Get-TerminalSettingsPaths {
    $found = @()
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { $found += $c } }

    # 便携版：wt.exe 旁边的 settings/settings.json（可能同时装了 Store 版和便携版）
    $wt = Get-Command wt.exe -ErrorAction SilentlyContinue
    if ($wt) {
        $dir = Split-Path -Parent $wt.Source
        $parent = Split-Path -Parent $dir
        foreach ($p in @(
            (Join-Path $dir 'settings\settings.json'),
            (Join-Path $parent 'settings\settings.json'),
            (Join-Path $dir '..\settings\settings.json')
        )) {
            if (Test-Path -LiteralPath $p) {
                $full = (Resolve-Path $p).Path
                if ($found -notcontains $full) { $found += $full }
            }
        }
    }
    # 手动指定（便携版没在 PATH 里时可用）：分号分隔的 settings.json 路径
    if ($env:WSL_CTF_KIT_TERMINAL_SETTINGS) {
        foreach ($p in ($env:WSL_CTF_KIT_TERMINAL_SETTINGS -split ';')) {
            $t = $p.Trim()
            if ($t -and (Test-Path -LiteralPath $t) -and ($found -notcontains $t)) { $found += $t }
        }
    }
    return $found
}

# 兼容旧调用：返回第一个
function Get-TerminalSettingsPath {
    return (Get-TerminalSettingsPaths | Select-Object -First 1)
}

function Update-OneTerminalSettings {
    param(
        [Parameter(Mandatory)][string]$Settings,
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$UserName,
        [string]$TabColor = '#268BEE',
        [string]$Guid = ''
    )

    $backup = "$Settings.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item -LiteralPath $Settings -Destination $backup -Force

    try {
        $json = Get-Content -LiteralPath $Settings -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warn "  $Settings 无法解析（可能含注释），跳过"
        return $false
    }

    if (-not $json.profiles) { $json | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) -Force }
    if (-not $json.profiles.list) {
        $json.profiles | Add-Member -NotePropertyName list -NotePropertyValue @() -Force
    }
    $list = @($json.profiles.list)

    $cmdline = "wsl.exe -d $Distro -u $UserName --cd ~"

    # Terminal 会给已注册的 WSL 发行版自动生成一个同名 profile（source=Microsoft.WSL）。
    # 如果只是新建一个，`wt -p <名字>` 就可能命中那个自动项（没有 -u/--cd），体验不一致。
    # 所以策略是「就地改造」：优先按 guid 找，其次按同名找，改 commandline 并去掉 source。
    $target = $list | Where-Object { $_.guid -eq $Guid } | Select-Object -First 1
    if (-not $target) {
        $target = $list | Where-Object { $_.name -eq $Distro } | Select-Object -First 1
    }

    if ($target) {
        $target | Add-Member -NotePropertyName commandline -NotePropertyValue $cmdline -Force
        $target | Add-Member -NotePropertyName hidden -NotePropertyValue $false -Force
        $target | Add-Member -NotePropertyName tabColor -NotePropertyValue $TabColor -Force
        # 有 source 字段时 Terminal 会忽略 commandline，必须去掉
        if ($target.PSObject.Properties.Name -contains 'source') {
            $target.PSObject.Properties.Remove('source')
        }
        Write-Ok "已更新 profile：$($target.name)"
    } else {
        $list += [pscustomobject]@{
            commandline = $cmdline
            guid        = $Guid
            hidden      = $false
            name        = $Distro
            tabColor    = $TabColor
        }
        Write-Ok "已添加 profile：$Distro"
    }

    # 兜底：把其它残留的同名自动生成项隐藏，避免 `wt -p <名字>` 命中歧义
    foreach ($p in $list) {
        if ($p.source -eq 'Microsoft.WSL' -and $p.name -eq $Distro) {
            $p.hidden = $true
            if ($p.name -notmatch '\(自动生成') { $p.name = "$Distro (自动生成的重复项)" }
        }
    }

    $json.profiles.list = $list
    try {
        $json | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $Settings -Encoding UTF8
        return $true
    } catch {
        Write-Warn "写回失败（已用备份还原）: $_"
        Copy-Item -LiteralPath $backup -Destination $Settings -Force
        return $false
    }
}

function Add-TerminalProfile {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$UserName,
        [string]$TabColor = '#268BEE',
        [string]$Guid = ''
    )
    # 机器上可能同时装了 Store 版和便携版 Terminal，两个配置都要写，否则用户从
    # 另一个入口打开时就看不到 profile（表现为「快捷方式能开、下拉菜单里没有」）。
    $paths = @(Get-TerminalSettingsPaths)
    if ($paths.Count -eq 0) {
        Write-Warn '未找到 Windows Terminal 配置，跳过 profile 注入（.cmd 启动器仍可用）'
        return $false
    }

    $okCount = 0
    foreach ($p in $paths) {
        Write-Info "Terminal 配置：$p"
        if (Update-OneTerminalSettings -Settings $p -Distro $Distro -UserName $UserName -TabColor $TabColor -Guid $Guid) {
            $okCount++
        }
    }
    if ($okCount -gt 0) { Write-Ok "Terminal profile 已写入 $okCount 个配置" }
    return ($okCount -gt 0)
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

function New-DesktopLauncher {
    <#
      生成「打开 Kali 桌面」的启动器。
      Win-KeX 的 viewer 是 Windows PE，放在 WSL 的 /usr/lib/win-kex 里；
      如果由 kex 从 WSL 侧拉起，wsl.exe 一退出 viewer 就被杀。
      所以这里把 viewer 和 VNC 密码文件复制到 Windows 侧，由 .cmd 直接启动。
    #>
    param(
        [Parameter(Mandatory)][string]$Distro,
        [Parameter(Mandatory)][string]$UserName,
        [string]$IconPath = '',
        [string]$DisplayNumber = '1'
    )
    $tv = Join-Path $script:KitHome 'TigerVNC'
    if (-not (Test-Path $tv)) { New-Item -ItemType Directory -Force -Path $tv | Out-Null }

    $viewer = Join-Path $tv 'win-kex-win-x64.exe'
    if (-not (Test-Path $viewer)) {
        $src = "\\wsl.localhost\$Distro\usr\lib\win-kex\TigerVNC\win-kex-win-x64"
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Warn "未找到 Win-KeX viewer（$src），跳过桌面启动器"
            return $null
        }
        try { Copy-Item -LiteralPath $src -Destination $viewer -Force }
        catch { Write-Warn "复制 Win-KeX viewer 失败: $_"; return $null }
    }

    $pwSrc = "\\wsl.localhost\$Distro\home\$UserName\.config\tigervnc\passwd"
    $pwDst = Join-Path $tv "passwd-$Distro"
    if (Test-Path -LiteralPath $pwSrc) {
        Copy-Item -LiteralPath $pwSrc -Destination $pwDst -Force
    } else {
        Write-Warn "未找到 VNC 密码文件；先在 $Distro 里跑一次 kex --win --start"
    }

    $cmd = Join-Path $script:KitHome "Open-$Distro-Desktop.cmd"
    $lines = @(
        '@echo off',
        "rem wsl-ctf-kit: open the $Distro desktop (Win-KeX). Keep this file ASCII-only.",
        'setlocal',
        "set `"DISTRO=$Distro`"",
        "set `"KUSER=$UserName`"",
        'set "VIEWER=%~dp0TigerVNC\win-kex-win-x64.exe"',
        "set `"VNPASS=%~dp0TigerVNC\passwd-$Distro`"",
        '',
        'if not exist "%VIEWER%" (',
        '  echo Missing %VIEWER%',
        '  echo Re-run: install.ps1 -WithDesktop',
        '  pause',
        '  exit /b 1',
        ')',
        '',
        'rem 1) make sure the Win-KeX server runs inside WSL (returns quickly)',
        'wsl.exe -d %DISTRO% -u %KUSER% -- kex --win --start >nul 2>&1',
        "rem 2) open the viewer on the Windows side so it survives wsl.exe exit",
        "start `"`" `"%VIEWER%`" -SecurityTypes VeNCrypt,TLSvnc -passwd `"%VNPASS%`" -FullScreen localhost:$DisplayNumber",
        'exit /b 0'
    )
    Set-Content -LiteralPath $cmd -Value ($lines -join "`r`n") -Encoding ASCII
    Write-Ok "桌面启动器：$cmd"
    [void](New-DesktopShortcut -TargetCmd $cmd -Name "Open-$Distro-Desktop" -IconPath $IconPath)
    return $cmd
}
