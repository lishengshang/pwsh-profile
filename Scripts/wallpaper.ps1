<#
.SYNOPSIS
    下载一张随机壁纸（可选超分辨率放大）并设为 Windows 桌面背景。
.DESCRIPTION
    由 profile 的 wallpaper 函数调用，也可单独执行。下载走 HttpClient（超时可控、
    非 2xx 抛异常、先写 .part 再原子改名）；有效性用 WPF BitmapImage 实际解码验证，
    只判扩展名或字节数会放行 API 返回的 HTML 错误页。超分依赖外部 waifu2x-ncnn-vulkan，
    缺失或失败时默认降级用原图，-strict 才中止。设置壁纸用 SystemParametersInfoW，
    返回 0 时取 Win32 错误码报出。Toast 通知是辅助功能，不可用时静默跳过。
#>
#Requires -Version 5.1
# 须在帮助块之后：放在首位会让 Get-Help / -? 读不到本块
param(
    # 清理模式：按修改时间倒序只保留最近 $keepCount 张
    [switch]$c,
    # 禁用超分，直接用原图
    [switch]$n,
    # 静默模式，不发通知（定时任务用）
    [switch]$s,
    # 严格模式：缺 waifu2x 或超分失败时中止（默认降级用原图）
    [switch]$strict,
    # 显示帮助后退出
    [switch]$h
)

# ================= 默认配置 =================
$apiUrl = 'https://t.alcy.cc/pc/'
$saveDir = Join-Path $env:USERPROFILE 'Pictures\Wallpapers'
$keepCount = 40
$upscaleThreshold = 3000

$enableCleanup = $false
$enableUpscale = $true
$silentMode = $false
# 默认降级：缺 waifu2x 或超分失败时用原图继续；-strict 才中止
$enableStrict = $false

# ================= 辅助函数 =================
function Send-Notify {
    param(
        [string]$Title,
        [string]$Body
    )
    if ($silentMode) { return }
    # 通知是辅助功能：Toast API 不可用/失败时静默降级，不阻断壁纸主流程
    try {
        if (Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue) {
            New-BurntToastNotification -Text "$Title", "$Body"
        } else {
            # 显式加载 WinRT 投影类型，否则下面的 ToastNotificationManager 解析不到
            $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
            $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
                [Windows.UI.Notifications.ToastTemplateType]::ToastText02)
            $template.GetElementsByTagName('text')[0].AppendChild($template.CreateTextNode($Title)) | Out-Null
            $template.GetElementsByTagName('text')[1].AppendChild($template.CreateTextNode($Body)) | Out-Null
            $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
            [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('PowerShell').Show($toast)
        }
    }
    catch {
        Write-Verbose "通知发送失败: $_"
    }
}

# ================= 参数应用 =================
# 帮助文本单源在文件顶部的 comment-based help，不另写一份 usage 字符串
if ($h) { Get-Help $PSCommandPath -Detailed; exit 0 }
if ($c) { $enableCleanup = $true }
if ($n) { $enableUpscale = $false }
if ($s) { $silentMode = $true }
if ($strict) { $enableStrict = $true }

if (-not (Test-Path $saveDir)) {
    New-Item -ItemType Directory -Path $saveDir -Force | Out-Null
}

# 时间戳用 Get-Date -Format 而非 [DateTimeOffset]::toUnixTimeSeconds()——后者是
# PS7 的扩展成员，5.1 兼容模式取不到
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$rawFilename = "wall_$timestamp.png"
$rawPath = Join-Path $saveDir $rawFilename

# ================= 1. 下载 =================
Send-Notify -Title 'Wallpaper' -Body 'Downloading from Alcy...'

Add-Type -AssemblyName System.Net.Http
$http = New-Object System.Net.Http.HttpClient
$http.Timeout = [TimeSpan]::FromSeconds(60)
# UA 必须是完整浏览器串：部分壁纸 API 对默认 PowerShell UA 直接返回错误页
$null = $http.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')

try {
    $tmpPath = "$rawPath.part"
    $bytes = $http.GetByteArrayAsync($apiUrl).GetAwaiter().GetResult()
    [IO.File]::WriteAllBytes($tmpPath, $bytes)
    Move-Item -Path $tmpPath -Destination $rawPath -Force
    $downloadSuccess = $true
} catch {
    $downloadSuccess = $false
    Write-Error "Download failed: $_"
    # 下载中断/写盘失败时清理残留的 .part 临时文件
    if ($tmpPath -and (Test-Path $tmpPath)) { Remove-Item $tmpPath -Force -ErrorAction SilentlyContinue }
} finally {
    $http.Dispose()
}

if (-not $downloadSuccess -or -not (Test-Path $rawPath)) {
    Send-Notify -Title 'Wallpaper Error' -Body 'Download failed (Network/API Error)'
    exit 1
}

$fileInfo = Get-Item $rawPath
if ($fileInfo.Length -lt 20480) {
    Send-Notify -Title 'Wallpaper Error' -Body 'Download failed (File too small/Invalid)'
    Remove-Item $rawPath -Force
    exit 1
}

# 仅在下载成功后加载 WPF（避免失败路径白白加载 assembly）
Add-Type -AssemblyName PresentationCore

try {
    $bi = New-Object System.Windows.Media.Imaging.BitmapImage
    $bi.BeginInit()
    $bi.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bi.UriSource = [Uri]('file:///' + $rawPath.Replace('\', '/'))
    $bi.EndInit()
    # 触发解码，若文件损坏这里会抛异常
    $null = $bi.PixelWidth
} catch {
    Send-Notify -Title 'Wallpaper Error' -Body 'Not a valid image file'
    Remove-Item $rawPath -Force
    exit 1
}

# ================= 2. 超分 =================
$finalPath = $rawPath
$msgExtra = ''

if ($enableUpscale) {
    $imgWidth = $bi.PixelWidth

    if ($imgWidth -lt $upscaleThreshold) {
        # 需要超分，检查工具是否存在
        $waifu2xExists = Get-Command waifu2x-ncnn-vulkan -ErrorAction SilentlyContinue
        if (-not $waifu2xExists) {
            if ($enableStrict) {
                Send-Notify -Title 'Wallpaper Error' -Body 'waifu2x not found, upscale aborted'
                Remove-Item $rawPath -Force
                exit 1
            }
            # 默认降级：没有 waifu2x 时直接用原图（与 profile 的"缺工具自动回退"哲学一致）
            Send-Notify -Title 'Wallpaper' -Body "waifu2x not found, using original (${imgWidth}px)"
            $msgExtra = "(waifu2x missing, original ${imgWidth}px)"
        }
        else {
            Send-Notify -Title 'Wallpaper' -Body "Upscaling ${imgWidth}px image..."
            # 用 .upscaled.png 后缀而非 ChangeExtension(.png)：源文件本来就是 .png 时
            # ChangeExtension 返回原路径，会让 waifu2x 读写同一个文件
            $upscaledPath = [System.IO.Path]::ChangeExtension($rawPath, '.upscaled.png')

            try {
                & waifu2x-ncnn-vulkan -i $rawPath -o $upscaledPath -n 1 -s 2
                if ($LASTEXITCODE -ne 0) { throw "waifu2x exited with code $LASTEXITCODE" }
                # 返回 0 但没生成输出文件时不能当成功（否则删原图后 finalPath 指向空）
                if (-not (Test-Path $upscaledPath)) { throw 'waifu2x produced no output file' }
                $finalPath = $upscaledPath
                $msgExtra = "(Upscaled 2x from ${imgWidth}px)"
                Remove-Item $rawPath -Force
            }
            catch {
                if ($enableStrict) {
                    Send-Notify -Title 'Wallpaper Error' -Body "Upscale failed: $_"
                    Remove-Item $rawPath -Force
                    Remove-Item $upscaledPath -Force -ErrorAction SilentlyContinue
                    exit 1
                }
                Send-Notify -Title 'Wallpaper' -Body "Upscale failed, using original: $_"
                $msgExtra = "(upscale failed, original ${imgWidth}px)"
                Remove-Item $upscaledPath -Force -ErrorAction SilentlyContinue
            }
        }
    } else {
        $msgExtra = "(Original ${imgWidth}px, High-Res)"
    }
} else {
    $msgExtra = '(Upscale Disabled)'
}


# ================= 3. 设置壁纸 =================
# Add-Type 重复定义同名类型会报错，先探测类型是否已存在（同一会话内多次调用 wallpaper）
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

$spiSetDesktopWallpaper = 0x0014
$spifUpdateIniFile = 0x01
$spifSendChange = 0x02
$setOk = [Wallpaper]::SystemParametersInfo($spiSetDesktopWallpaper, 0, $finalPath, $spifUpdateIniFile -bor $spifSendChange)
if ($setOk -eq 0) {
    # 返回 0 = 失败；取 Win32 错误码定位原因（文件路径无效/被占用等）
    $win32err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    Send-Notify -Title 'Wallpaper Error' -Body "Set wallpaper failed (Win32Error=$win32err)"
    Write-Error "SystemParametersInfo failed: Win32Error=$win32err, path=$finalPath"
    exit 1
}

# ================= 4. 清理 =================
if ($enableCleanup) {
    $files = Get-ChildItem -Path $saveDir -Filter 'wall_*' | Sort-Object LastWriteTime -Descending
    if ($files.Count -gt $keepCount) {
        $files | Select-Object -Skip $keepCount | ForEach-Object {
            Remove-Item $_.FullName -Force
        }
    }
}

Send-Notify -Title 'Wallpaper Updated' -Body "Enjoy! $msgExtra"
