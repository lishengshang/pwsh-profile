-- 输入法自动切换：插入模式切中文，普通/命令行模式切英文。
-- switch_key 必须与系统输入法的中/英切换键一致：微软拼音默认是 shift；
-- 若你在系统里改过切换键，同步改这里。
return {
  "wsdjeg/smart-ime.nvim",
  -- 不能使用 InsertEnter 懒加载：插件在该事件触发后才注册自己的
  -- InsertEnter autocmd，导致启动后的第一次进入插入模式完全不会处理。
  lazy = false,
  opts = { switch_key = "shift" },
  config = function(_, opts)
    require("smart-ime").setup(opts)

    -- smart-ime.nvim 的默认行为是“恢复上次保存的状态”。新 buffer 没有
    -- 保存状态时，它不会主动切中文；这里补上第一次进入插入模式的初始化。
    if vim.fn.has("win32") ~= 1 or vim.fn.executable("powershell.exe") ~= 1 then
      return
    end

    local vk_map = {
      ctrl = 0x11,
      shift = 0x10,
      alt = 0x12,
      space = 0x20,
      win = 0x5B,
    }
    local keys = {}
    for _, part in ipairs(vim.split(opts.switch_key or "", "+")) do
      part = vim.trim(part):lower()
      local vk = vk_map[part]
      if not vk and part:match("^0x[0-9a-f]+$") then
        vk = tonumber(part:sub(3), 16)
      end
      if vk then
        table.insert(keys, vk)
      end
    end
    if #keys == 0 then
      return
    end

    local key_events = {}
    for _, vk in ipairs(keys) do
      table.insert(
        key_events,
        string.format("[SmartIME.Init]::keybd_event(0x%02X, 0, 0, [System.UIntPtr]::Zero)", vk)
      )
    end
    for i = #keys, 1, -1 do
      table.insert(
        key_events,
        string.format("[SmartIME.Init]::keybd_event(0x%02X, 0, 2, [System.UIntPtr]::Zero)", keys[i])
      )
    end
    key_events = table.concat(key_events, "; ")

    local function switch_to(target)
      local script = string.format(
        [[
$target = '%s'
try {
    $sig = '[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam); [DllImport("imm32.dll")] public static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd); [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, System.UIntPtr dwExtraInfo);'
    Add-Type -MemberDefinition $sig -Name 'Init' -Namespace 'SmartIME'
    $hwnd = [SmartIME.Init]::GetForegroundWindow()
    $hIme = [SmartIME.Init]::ImmGetDefaultIMEWnd($hwnd)
    if ($hIme -ne [IntPtr]::Zero) {
        $mode = [int][SmartIME.Init]::SendMessage($hIme, 0x0283, [IntPtr]1, [IntPtr]0)
        if (($target -eq 'chinese' -and -not ($mode -band 1)) -or ($target -eq 'english' -and ($mode -band 1))) {
            %s
        }
    }
} catch { }
]],
        target,
        key_events
      )
      -- powershell.exe spawn + Add-Type 实测 ~350ms；必须异步执行，
      -- 否则每次进入/离开命令行都会同步阻塞 Neovim。
      vim.system({ "powershell.exe", "-NoProfile", "-Command", script }, {}, function() end)
    end

    local initialized = {}
    local group = vim.api.nvim_create_augroup("profile-ime-init", { clear = true })
    vim.api.nvim_create_autocmd("InsertEnter", {
      group = group,
      pattern = "*",
      callback = function(ev)
        if not initialized[ev.buf] then
          initialized[ev.buf] = true
          switch_to("chinese")
        end
      end,
    })

    -- 命令行始终使用英文，避免从插入模式退出时的异步切换延迟造成中文命令。
    vim.api.nvim_create_autocmd({ "CmdlineEnter", "CmdlineLeave" }, {
      group = group,
      pattern = "*",
      callback = function()
        switch_to("english")
      end,
    })
  end,
}
