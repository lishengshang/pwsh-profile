
# ================= 参数解析（必须放最前面）=================
param(
    [switch]$c,
    [switch]$n,
    [switch]$s,
    [switch]$strict,
    [switch]$h
)

# ================= 默认配置 =================
$API_URL = "https://t.alcy.cc/pc/"
$SAVE_DIR = Join-Path $env:USERPROFILE "Pictures\Wallpapers"
$KEEP_COUNT = 40
$UPSCALE_THRESHOLD = 3000

$ENABLE_CLEANUP = $false
$ENABLE_UPSCALE = $true
$SILENT_MODE = $false
# 默认降级：缺 waifu2x 或超分失败时用原图继续；-strict 才中止
$ENABLE_STRICT = $false

# ================= 辅助函数 =================
function Show-Usage {
    Write-Host "用法: wallpaper [-c] [-n] [-s] [-strict] [-h]"
    Write-Host "  -c  (Clean)   清理模式：自动清理旧壁纸，保留最近 $KEEP_COUNT 张"
    Write-Host "  -n  (No Up)   禁用超分：无论分辨率多少，都直接使用原图"
    Write-Host "  -s  (Silent)  静默模式：不发送任何通知"
    Write-Host "  -strict       严格模式：缺 waifu2x 或超分失败时中止（默认降级用原图）"
    Write-Host "  -h  帮助信息"
    exit 0
}

function Send-Notify {
    param(
        [string]$Title,
        [string]$Body
    )
    if ($SILENT_MODE) { return }
    # 通知是辅助功能：Toast API 不可用/失败时静默降级，不阻断壁纸主流程
    try {
        if (Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue) {
            New-BurntToastNotification -Text "$Title", "$Body"
        } else {
            [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null
            $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
                [Windows.UI.Notifications.ToastTemplateType]::ToastText02)
            $template.GetElementsByTagName("text")[0].AppendChild($template.CreateTextNode($Title)) > $null
            $template.GetElementsByTagName("text")[1].AppendChild($template.CreateTextNode($Body)) > $null
            $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("PowerShell").Show($toast)
        }
    }
    catch {
        Write-Verbose "通知发送失败: $_"
    }
}

# ================= 参数应用 =================
if ($h) { Show-Usage }
if ($c) { $ENABLE_CLEANUP = $true }
if ($n) { $ENABLE_UPSCALE = $false }
if ($s) { $SILENT_MODE = $true }
if ($strict) { $ENABLE_STRICT = $true }

# ================= 主逻辑 =================
if (-not (Test-Path $SAVE_DIR)) {
    New-Item -ItemType Directory -Path $SAVE_DIR -Force | Out-Null
}

# ✅ 修复：用兼容 Windows PS5 的方式生成时间戳
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$RAW_FILENAME = "wall_$timestamp.png"
$RAW_PATH = Join-Path $SAVE_DIR $RAW_FILENAME

# --- 1. 下载（HttpClient：超时可控 + 非成功状态码抛异常 + 临时文件原子落盘）---
Send-Notify -Title "Wallpaper" -Body "Downloading from Alcy..."

Add-Type -AssemblyName System.Net.Http
$http = New-Object System.Net.Http.HttpClient
$http.Timeout = [TimeSpan]::FromSeconds(60)
$null = $http.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")

try {
    $tmpPath = "$RAW_PATH.part"
    $bytes = $http.GetByteArrayAsync($API_URL).GetAwaiter().GetResult()
    [IO.File]::WriteAllBytes($tmpPath, $bytes)
    Move-Item -Path $tmpPath -Destination $RAW_PATH -Force
    $DOWNLOAD_SUCCESS = $true
} catch {
    $DOWNLOAD_SUCCESS = $false
    Write-Error "Download failed: $_"
    # 下载中断/写盘失败时清理残留的 .part 临时文件
    if ($tmpPath -and (Test-Path $tmpPath)) { Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue }
} finally {
    $http.Dispose()
}

if (-not $DOWNLOAD_SUCCESS -or -not (Test-Path $RAW_PATH)) {
    Send-Notify -Title "Wallpaper Error" -Body "Download failed (Network/API Error)"
    exit 1
}

$fileInfo = Get-Item $RAW_PATH
if ($fileInfo.Length -lt 20480) {
    Send-Notify -Title "Wallpaper Error" -Body "Download failed (File too small/Invalid)"
    Remove-Item $RAW_PATH -Force
    exit 1
}

# 仅在下载成功后加载 WPF（避免失败路径白白加载 assembly）
Add-Type -AssemblyName PresentationCore

try {
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bi.UriSource = [Uri]("file:///" + $RAW_PATH.Replace("\", "/"))
    $bi.EndInit()
    # 触发解码，若文件损坏这里会抛异常
    $null = $bi.PixelWidth
} catch {
    Send-Notify -Title "Wallpaper Error" -Body "Not a valid image file"
    Remove-Item $RAW_PATH -Force
    exit 1
}

# --- 2. 超分 ---
$FINAL_PATH = $RAW_PATH
$MSG_EXTRA = ""

if ($ENABLE_UPSCALE) {
    $IMG_WIDTH = $bi.PixelWidth

    if ($IMG_WIDTH -lt $UPSCALE_THRESHOLD) {
        # 需要超分，检查工具是否存在
        $waifu2xExists = Get-Command waifu2x-ncnn-vulkan -ErrorAction SilentlyContinue
        if (-not $waifu2xExists) {
            if ($ENABLE_STRICT) {
                Send-Notify -Title "Wallpaper Error" -Body "waifu2x not found, upscale aborted"
                Remove-Item $RAW_PATH -Force
                exit 1
            }
            # 默认降级：没有 waifu2x 时直接用原图（与 profile 的"缺工具自动回退"哲学一致）
            Send-Notify -Title "Wallpaper" -Body "waifu2x not found, using original (${IMG_WIDTH}px)"
            $MSG_EXTRA = "(waifu2x missing, original ${IMG_WIDTH}px)"
        }
        else {
            Send-Notify -Title "Wallpaper" -Body "Upscaling ${IMG_WIDTH}px image..."
            # ponytail: 用后缀避免 ChangeExtension 在已经是 .png 时返回原路径导致 waifu2x 读写同一文件
            $UPSCALED_PATH = [System.IO.Path]::ChangeExtension($RAW_PATH, ".upscaled.png")

            try {
                & waifu2x-ncnn-vulkan -i $RAW_PATH -o $UPSCALED_PATH -n 1 -s 2
                if ($LASTEXITCODE -ne 0) { throw "waifu2x exited with code $LASTEXITCODE" }
                # 返回 0 但没生成输出文件时不能当成功（否则删原图后 FINAL_PATH 指向空）
                if (-not (Test-Path $UPSCALED_PATH)) { throw "waifu2x produced no output file" }
                $FINAL_PATH = $UPSCALED_PATH
                $MSG_EXTRA = "(Upscaled 2x from ${IMG_WIDTH}px)"
                Remove-Item $RAW_PATH -Force
            }
            catch {
                if ($ENABLE_STRICT) {
                    Send-Notify -Title "Wallpaper Error" -Body "Upscale failed: $_"
                    Remove-Item $RAW_PATH -Force
                    Remove-Item $UPSCALED_PATH -Force -ErrorAction SilentlyContinue
                    exit 1
                }
                Send-Notify -Title "Wallpaper" -Body "Upscale failed, using original: $_"
                $MSG_EXTRA = "(upscale failed, original ${IMG_WIDTH}px)"
                Remove-Item $UPSCALED_PATH -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        $MSG_EXTRA = "(Original ${IMG_WIDTH}px, High-Res)"
    }
} else {
    $MSG_EXTRA = "(Upscale Disabled)"
}


# --- 3. 设置壁纸 ---
# ✅ 修复：避免重复 Add-Type 报错
if (-not ([System.Management.Automation.PSTypeName]'Wallpaper').Type) {
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Wallpaper {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@
}

$SPI_SETDESKWALLPAPER = 0x0014
$SPIF_UPDATEINIFILE = 0x01
$SPIF_SENDCHANGE = 0x02
$setOk = [Wallpaper]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $FINAL_PATH, $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE)
if ($setOk -eq 0) {
    # 返回 0 = 失败；取 Win32 错误码定位原因（文件路径无效/被占用等）
    $win32err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Send-Notify -Title "Wallpaper Error" -Body "Set wallpaper failed (Win32Error=$win32err)"
    Write-Error "SystemParametersInfo failed: Win32Error=$win32err, path=$FINAL_PATH"
    exit 1
}

# --- 4. 清理 ---
if ($ENABLE_CLEANUP) {
    $files = Get-ChildItem -Path $SAVE_DIR -Filter "wall_*" | Sort-Object LastWriteTime -Descending
    if ($files.Count -gt $KEEP_COUNT) {
        $files | Select-Object -Skip $KEEP_COUNT | ForEach-Object {
            Remove-Item $_.FullName -Force
        }
    }
}

Send-Notify -Title "Wallpaper Updated" -Body "Enjoy! $MSG_EXTRA"