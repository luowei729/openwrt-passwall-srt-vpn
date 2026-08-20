-- ============================================================
-- util_srt-vpn.lua — SRT-VPN 客户端配置生成
--
-- SRT-VPN 客户端是 SOCKS5/HTTP/HTTPS 三合一代理入口（本地监听），
-- 通过 SRT 加密隧道连到 SRT-VPN 服务端。
-- 本模块把 passwall 节点配置转成 srt-vpn 的 client.json 配置 schema，
-- 由 app.sh 的 ln_run 以 `srt-vpn -c <config>` 方式启动。
--
-- 启动链路（与 naiveproxy 等核心一致）：
--   app.sh run_socks -> lua util_srt-vpn.lua gen_config "$(json_dump)" > $config_file
--                    -> ln_run "$(first_type <srt_vpn_file> srt-vpn)" srt-vpn $log_file -c "$config_file"
--
-- 重要：srt-vpn 客户端在【同一个监听端口】提供 SOCKS5+HTTP+HTTPS 三合一
--       （首字节嗅探：0x05=SOCKS5，HTTP 方法=HTTP 代理），因此：
--       * 不需要独立 http 配置字段（passwall 的 http_port 对 srt-vpn 无意义，
--         app.sh srtvpn 分支不传 local_http_* 即可）
--       * 只需要 socks5.listen（含认证）
--
-- 字段来源：
--   * var["server_host"/"server_port"]：app.sh run_socks 注入（节点 address/port）
--   * var["local_socks_address"/"local_socks_port"]：passwall 分配的本地 SOCKS5 监听
--   * node.srtvpn_*：节点类型 7_srt-vpn.lua 保存的私有字段（带 srtvpn_ 前缀）
--
-- srt-vpn 配置字段说明（2026-08-20 重构后更新）：
--   mode:       固定 "client"
--   server:     服务端 IP:端口（必填）
--   passphrase: SRT 隧道加密密码（必填，两端一致，由其派生 AES-128-CTR 密钥）
--   pool_size:  多连接池大小（1..=16，默认 4，B 方案多连接多带宽）
--   socks5:     本地监听（三合一入口，可带用户名密码）
--   reconnect:  自动重连（默认 5s 间隔、10 次）
--   heartbeat_secs: 心跳间隔（默认 5s）
-- 已废弃字段（保留 uci 向后兼容但不写入 config）：
--   crypto:   重构后加密统一 AES-128-CTR 由 passphrase 派生（不再分 128/192/256）
--   streamid: 重构后静态令牌已删（认证用 SRT 特征握手密钥派生）
-- ============================================================
module("luci.passwall.util_srt-vpn", package.seeall)
local api = require "luci.passwall.api"
local jsonc = api.jsonc

function gen_config(var)
	local node_id = var["node"]
	if not node_id then
		print("node 不能为空")
		return
	end
	local node = api.uci_get_c(node_id)

	local server_host = var["server_host"] or (node.address or ""):lower()
	local server_port = var["server_port"] or node.port
	local local_socks_address = var["local_socks_address"] or "127.0.0.1"
	local local_socks_port = var["local_socks_port"]
	local local_socks_username = var["local_socks_username"] or node.srtvpn_socks_username
	local local_socks_password = var["local_socks_password"] or node.srtvpn_socks_password

	-- IPv6 服务器地址需要中括号包裹（srt-vpn server 字段要求 ip:port 格式）
	if api.is_ipv6(server_host) then
		server_host = api.get_ipv6_full(server_host)
		server_host = "[" .. server_host .. "]"
	end

	-- srt-vpn 客户端三合一：socks5.listen 即 HTTP/HTTPS 入口，无需再传 http 端口
	-- 2026-08-20 适配重构后新内核：
	--   * crypto/streamid 已废弃（重构后加密统一 AES-128-CTR 由 passphrase 派生，
	--     streamid 静态令牌已删）。保留 uci 字段向后兼容但不写入 config。
	local config = {
		mode = "client",
		server = server_host .. ":" .. (server_port or "9000"),
		passphrase = node.srtvpn_passphrase,
		-- pool_size: 多连接池大小（默认 4，可改 SRT_POOL_SIZE env；P1.5 配置化）
		pool_size = tonumber(node.srtvpn_pool_size) or nil,
		socks5 = {
			listen = local_socks_address .. ":" .. (local_socks_port or "1080"),
			username = (local_socks_username and local_socks_username ~= "") and local_socks_username or nil,
			password = (local_socks_password and local_socks_password ~= "") and local_socks_password or nil
		},
		reconnect = {
			interval_secs = tonumber(node.srtvpn_reconnect_interval) or 5,
			max_retries = tonumber(node.srtvpn_reconnect_max) or 10
		},
		heartbeat_secs = tonumber(node.srtvpn_heartbeat) or 5
	}

	return jsonc.stringify(config, 1)
end

_G.gen_config = gen_config

if arg[1] then
	local func = _G[arg[1]]
	if func then
		local var = nil
		if arg[2] then
			var = jsonc.parse(arg[2])
		end
		print(func(var))
	end
end