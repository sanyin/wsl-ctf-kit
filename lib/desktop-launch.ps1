# lib/desktop-launch.ps1 — 由 Open-<distro>-Desktop.cmd 调用
#
# 为什么需要这个脚本：
#   1) Win-KeX 的 viewer 是 Windows PE，必须从 Windows 侧启动，否则会随 wsl.exe 退出被杀
#   2) 由隐藏/最小化的父进程启动 GUI 时，Windows 会把窗口也带成最小化
#      （表现为「任务栏有图标但看不到桌面」），start / Start-Process 都压不住
#   3) 所以这里：起服务端 → 启动 viewer → 等窗口 → SW_RESTORE + 按屏幕摆位
#   4) 启动器进程退出的一瞬间窗口可能又被最小化，故再起一个延迟 3 秒的「恢复子进程」兜底
param(
    [string]$Distro = 'Kali',
    [string]$Kuser = 'ctf',
    [string]$Viewer = '',
    [string]$VnPass = '',
    [int]$Display = 1,
    [switch]$RestoreOnly
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -Namespace Dsk -Name W -MemberDefinition @'
public delegate bool EnumProc(IntPtr h, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
public struct RECT { public int L,T,R,B; }
'@

function Get-ViewerWindow([int]$TargetPid) {
    $hits = New-Object System.Collections.ArrayList
    $cb = [Dsk.W+EnumProc]{
        param($h, $l)
        $wpid = 0
        [void][Dsk.W]::GetWindowThreadProcessId($h, [ref]$wpid)
        if (($TargetPid -le 0) -or ($wpid -eq $TargetPid)) {
            $sb = New-Object System.Text.StringBuilder 512
            [void][Dsk.W]::GetWindowTextW($h, $sb, 512)
            if ($sb.ToString() -match 'TigerVNC') {
                $r = New-Object Dsk.W+RECT
                [void][Dsk.W]::GetWindowRect($h, [ref]$r)
                [void]$hits.Add([pscustomobject]@{
                    Handle = $h
                    Area   = [math]::Abs(($r.R - $r.L) * ($r.B - $r.T))
                })
            }
        }
        return $true
    }
    [void][Dsk.W]::EnumWindows($cb, [IntPtr]::Zero)
    if ($hits.Count -eq 0) { return [IntPtr]::Zero }
    return ($hits | Sort-Object Area -Descending | Select-Object -First 1).Handle
}

# 摆到屏幕中央，80% 大小（上限 1600x1000）
function Set-ViewerPlacement([IntPtr]$Handle) {
    [void][Dsk.W]::ShowWindow($Handle, 9)      # SW_RESTORE
    Start-Sleep -Milliseconds 300
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $wantW = [int]($wa.Width * 0.8);  if ($wantW -gt 1600) { $wantW = 1600 }; if ($wantW -lt 800) { $wantW = 800 }
    $wantH = [int]($wa.Height * 0.8); if ($wantH -gt 1000) { $wantH = 1000 }; if ($wantH -lt 600) { $wantH = 600 }
    $x = $wa.X + [int](($wa.Width - $wantW) / 2)
    $y = $wa.Y + [int](($wa.Height - $wantH) / 2)
    [void][Dsk.W]::SetWindowPos($Handle, [IntPtr]::Zero, $x, $y, $wantW, $wantH, 0x0004)  # SWP_NOZORDER
    [void][Dsk.W]::ShowWindow($Handle, 9)
    [void][Dsk.W]::SetForegroundWindow($Handle)
}

# ---------- 兜底模式：稍后把窗口恢复到正常状态 ----------
if ($RestoreOnly) {
    Start-Sleep -Seconds 3
    $h = Get-ViewerWindow -TargetPid 0
    if ($h -ne [IntPtr]::Zero) { Set-ViewerPlacement $h }
    exit 0
}

if (-not $Viewer -or -not (Test-Path -LiteralPath $Viewer)) {
    [Console]::Error.WriteLine("找不到 viewer: $Viewer")
    exit 1
}

# 1) 确保 Win-KeX 服务端在 WSL 里跑起来
try { & wsl.exe -d $Distro -u $Kuser -- kex --win --start *> $null } catch { }

# 2) 启动 viewer
$launchArgs = @('-SecurityTypes', 'VeNCrypt,TLSvnc', '-passwd', $VnPass, "localhost:$Display")
$proc = Start-Process -FilePath $Viewer -ArgumentList $launchArgs -PassThru

# 3) 等窗口出现（最多 20 秒）
$hwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Milliseconds 500
    $hwnd = Get-ViewerWindow -TargetPid $proc.Id
    if ($hwnd -ne [IntPtr]::Zero) { break }
}
if ($hwnd -eq [IntPtr]::Zero) {
    [Console]::Error.WriteLine("viewer 窗口没等到（进程 $($proc.Id)）")
    exit 1
}

# 4) 摆位
Set-ViewerPlacement $hwnd

# 5) 延迟兜底：本进程退出后窗口可能被再次最小化
try {
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-RestoreOnly'
    ) | Out-Null
} catch { }

exit 0
