# Captures the real game window exactly as it appears on screen (PrintWindow), optionally driving it with
# POCKET_AUTOPLAY steps (see hub.gd). Use this to check the look: the headless/--path screenshot script reads
# HDR frames back as linear colour and looks too dark and wrong. Example:
#   powershell -ExecutionPolicy Bypass -File scripts/window_shot.ps1 -Out shots/drop.png -WaitSec 12 -Autoplay "open,wait1,play,wait1,drop,wait1.3"
param([string]$Out, [int]$WaitSec = 8, [string]$Autoplay = "")
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
Get-Process | Where-Object { $_.ProcessName -eq 'Godot_v4.7.2-stable_win64' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 1
if ($Autoplay -ne "") { $env:POCKET_AUTOPLAY = $Autoplay }
$p = Start-Process "C:\Users\dunlo\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" -ArgumentList '--path','C:\Users\dunlo\source\catdrop-godot' -PassThru
Start-Sleep $WaitSec
$h = (Get-Process -Id $p.Id).MainWindowHandle
$r = New-Object Win+RECT
[Win]::GetWindowRect($h, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $hgt = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap $w, $hgt
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
$ok = [Win]::PrintWindow($h, $hdc, 2)
$g.ReleaseHdc($hdc)
$g.Dispose()
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
Write-Output "printwindow=$ok size=${w}x${hgt}"
Stop-Process -Id $p.Id -Force
