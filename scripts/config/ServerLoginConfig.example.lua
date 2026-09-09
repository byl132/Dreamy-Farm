-- ============================================================
-- config/ServerLoginConfig.example.lua - 登录凭证交换配置模板
-- ============================================================
-- 用法：复制本文件为同目录下的 ServerLoginConfig.lua 并填入真实凭据。
--       ServerLoginConfig.lua 已在 .gitignore 中，不会被提交。
--
-- ⚠️ appid / secret 属于服务端密钥，严禁提交到任何版本仓库。
--    若仓库曾意外包含真实密钥，需在 TapTap 开发者中心重置密钥。
--
-- 填写说明（TapTap 开发者中心 → 小游戏 → 凭证）：
--   appid  = MiniApp ID
--   secret = 小游戏密钥
-- 客户端 tap.login() 的 code 将由服务端调
--   GET {apiBase}?appid=&secret=&js_code=&grant_type=authorization_code
-- 换取 openid/unionid（https://developer.taptap.cn/minigameapidoc/dev/server/login/code2Session/）
-- ============================================================

return {
    appid = "",
    secret = "",
    apiBase = "https://cloud-miniapp.tapapis.cn/auth/v1/jscode2session",
}
