-- 输入法自动切换：插入模式切中文，退出插入/命令行模式切英文
-- （normal 模式下敲命令永远是英文）
-- switch_key 必须与系统输入法的中/英切换键一致：微软拼音默认是 shift；
-- 若你在系统里改过切换键，同步改这里。
return {
  "wsdjeg/smart-ime.nvim",
  event = "InsertEnter",
  opts = { switch_key = "shift" },
}
