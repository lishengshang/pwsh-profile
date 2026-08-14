# Windows Terminal 主题（Solarized Dark）

与 `profile/psreadline.ps1` 的 PSReadLine 配色（同一 Solarized 色板）配套的
Windows Terminal 配色方案，外加字体与键位建议（面向 `eza --icons` + PSFzf）。

## 安装配色

1. Windows Terminal → 设置（`Ctrl+,`）→ 左下角「打开 JSON 文件」，编辑
   `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`
   （WT 的 settings.json 支持注释，可直接粘贴）。
   非商店版（GitHub Release 安装）的路径为 `%LOCALAPPDATA%\Microsoft\Windows Terminal\settings.json`。
2. 把 `solarized-dark.json` 里的整个对象（含 `name`）追加到 `"schemes": []` 数组中：

   ```jsonc
   "schemes": [
       // ...已有的方案...
       { "name": "Solarized Dark", "background": "#002B36", /* 粘贴 solarized-dark.json 全部内容 */ }
   ]
   ```

3. 在你要应用的 profile（通常是 PowerShell）上设置配色与字体：

   ```jsonc
   {
       "colorScheme": "Solarized Dark",
       "font": { "face": "CaskaydiaCove NF", "size": 11 }
   }
   ```

## 字体

`eza --icons` 的文件图标需要 Nerd Font 才能正确显示（自带的 Cascadia Code 没有图标字形）：

```powershell
winget install -e --id nerd-fonts.CaskaydiaCove --source winget
```

装完后在 WT 设置里把字体换成 `CaskaydiaCove NF` 并重开终端。
若该 ID 在你的 winget 源里搜不到，用 `winget search CaskaydiaCove` 或到
[Nerd Fonts 官网](https://www.nerdfonts.com/font-downloads) 下载。

## 注意：Ctrl+t 键位冲突

profile 中 PSFzf 用 `Ctrl+t` 触发文件补全，但 Windows Terminal 默认把 `Ctrl+t`
绑定为「打开标签页下拉菜单」（openTab），按键到不了 PowerShell。二选一：

- 在 WT 设置的 `"actions"` 里搜索 `"openTab"`，删除或改绑 `ctrl+t`；
- 或给 PSFzf 换一个键位：修改 `profile/modules.ps1` 里
  `-PSReadlineChordProvider` 的值（例如改成 `Ctrl+g`）。

## 相关

- 想微调配色？PSReadLine 的前景色在 `profile/psreadline.ps1` 的 `-Colors` 中定义，
  与本文件 16 色保持同一 Solarized 色板即可。
