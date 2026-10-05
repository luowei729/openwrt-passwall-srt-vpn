-- ============================================================
-- 7_srt-vpn.lua — SRT-VPN 节点类型（passwall 客户端节点新增类型）
--
-- 用途：passwall「节点列表 -> 添加」时多出 "SRT-VPN" 类型，配置
--       服务端地址/端口/passphrase 等参数，保存后由 app.sh 的
--       srtvpn 分支通过 util_srt-vpn.lua 生成 client.json 启动。
--
-- 编码约定（与 5_hysteria2.lua / 6_naive.lua 完全一致）：
--   * address / port：节点通用字段（不设 rewrite_option，存 uci 无前缀，
--     app.sh 用 config_n_get $node address / port 读取）
--   * 其余 srt-vpn 私有字段：o.rewrite_option = _n(o.option)，存 uci 带
--     "srtvpn_" 前缀，util_srt-vpn.lua 用 node.srtvpn_xxx 读取
--   * api.luci_types(s1, s) 统一处理前缀写回与类型依赖
--
-- 参数说明：
--   address/port：SRT 服务端地址与端口（必填）
--   passphrase：隧道加密密码（必填，两端一致）
--   crypto：加密强度（aes-128/192/256，默认 aes-128）
--   streamid：可选伪装令牌（默认内置格式）
--   socks_username/password：本地 SOCKS5 认证（可空=无认证）
--   reconnect_interval/max：自动重连（默认 5s/10 次）
--   heartbeat：心跳间隔（默认 5s）
-- ============================================================
if not api.finded_com("srt-vpn") then
    return
end

-- [[ SRT-VPN ]]
local m, s1 = ...
-- 注意：节点 type 值存 uci，app.sh 中 `tr 'A-Z' 'a-z'` 小写化后作为 case 分支名，
--       因此这里不能用带连字符的 "Srt-Vpn"（会变 srt-vpn -> shell 大小写处理不一致），
--       用 "Srtvpn" 使其小写化为 "srtvpn"，与 app.sh 的 srtvpn) 分支严格对应。
local type_name = "Srtvpn"

s1.fields["type"]:value(type_name, "SRT-VPN")

if s1.val["type"] ~= type_name then
    return
end

local s = NamedSection(m, arg[1], "server")
s.type_name = type_name
s.option_prefix = "srtvpn_"

local function _n(name)
    return s.option_prefix .. name
end

-- 始终隐藏，用于删除 protocol（srt-vpn 无协议概念，避免遗留干扰分流逻辑）
-- 与 3_ss-rust.lua 的 del_protocol 模式一致
o = s:option(ListValue, "del_protocol", "　")
o:depends({ __hide = "1" })
o.rewrite_option = "protocol"

-- * 服务器基础配置（必填，节点通用字段无前缀）
o = s:option(Value, "address", translate("SRT Server Address (Support Domain Name)"))
o.description = translate("必填。SRT-VPN 服务端地址，如 vpn.example.com 或 1.2.3.4")

o = s:option(Value, "port", translate("SRT Server Port"))
o.datatype = "port"
o.default = "9000"
o.description = translate("必填。SRT-VPN 服务端端口（默认 9000，须与服务端 listen 一致）")

-- * 隧道安全参数（单密码兼容：日常只填 Passphrase 即可开箱）
o = s:option(Value, "passphrase", translate("SRT Passphrase (Encryption Key)"))
o.password = true
o.rewrite_option = _n(o.option)
o.description = translate("必填。线路加密与认证共用密码（单密码模式：password 默认同此值；多用户需各配独立 UUID/Password 隔离）")

-- * 身份标识（单密码兼容：UUID 必填有默认值，Password 为空自动 fallback 到 Passphrase）
o = s:option(Value, "uuid", translate("UUID (User Identity)"))
o.datatype = "uuid"
o.default = "00000000-0000-0000-0000-000000000001"
o.rmempty = false
o.rewrite_option = _n(o.option)
o.description = translate("必填。用户身份标识（默认与新加坡服务端 users[0] 一致，多设备复用同一身份不踢人；多用户隔离需各配独立 UUID）")

o = s:option(Value, "password", translate("Password (Auth, default = Passphrase)"))
o.password = true
o.rewrite_option = _n(o.option)
o.placeholder = "默认同 Passphrase"
o.rmempty = true
o.description = translate("可选。认证密码（TUIC 认证用，留空则自动使用上方 Passphrase；需独立认证再填）")

o = s:option(ListValue, "crypto", translate("Crypto (Deprecated)"))
o:value("", translate("Keep default"))
o:value("aes-128", "AES-128")
o:value("aes-192", "AES-192")
o:value("aes-256", "AES-256")
o.default = ""
o.rewrite_option = _n(o.option)
o.description = translate("已废弃（重构后加密统一 AES-128-CTR 由 passphrase 派生）。保留该选项仅为向后兼容，实际不生效")

o = s:option(Value, "streamid", translate("Streamid (Deprecated)"))
o.rewrite_option = _n(o.option)
o.description = translate("已废弃（重构后静态令牌已删，认证用 SRT 特征握手密钥派生）。保留仅为向后兼容，实际不生效")

-- * 本地 SOCKS5 入口认证（可空=无认证）
o = s:option(Value, "socks_username", translate("Local SOCKS5 Username"))
o.rewrite_option = _n(o.option)
o.description = translate("可选。本地 SOCKS5 代理认证用户名，留空则不认证")

o = s:option(Value, "socks_password", translate("Local SOCKS5 Password"))
o.password = true
o.rewrite_option = _n(o.option)
o.description = translate("可选。本地 SOCKS5 代理认证密码")

-- 已废弃：pool_size（v0.4.0 单 QUIC 连接多路复用，无连接池）
o = s:option(Value, "pool_size", translate("Pool Size (Deprecated)"))
o.datatype = "uinteger"
o.default = ""
o.rmempty = true
o.rewrite_option = _n(o.option)
o.description = translate("已废弃（v0.4.0 单 QUIC 连接多路复用，无连接池）。保留仅为向后兼容，实际不生效")

-- * 自动重连与心跳（不填保持默认）
o = s:option(Value, "reconnect_interval", translate("Reconnect Interval (seconds)"))
o.datatype = "uinteger"
o.default = "5"
o.rmempty = false
o.rewrite_option = _n(o.option)
o.description = translate("可选。断线自动重连间隔（秒），默认 5")

o = s:option(Value, "reconnect_max", translate("Reconnect Max Retries"))
o.datatype = "integer"
o.default = "10"
o.rmempty = false
o.rewrite_option = _n(o.option)
o.description = translate("可选。最大重连次数，默认 10（-1 为无限重连）")

o = s:option(Value, "heartbeat", translate("Heartbeat Interval (seconds)"))
o.datatype = "uinteger"
o.default = "5"
o.rmempty = false
o.rewrite_option = _n(o.option)
o.description = translate("可选。心跳间隔（秒），默认 5")

api.luci_types(s1, s)