## :mega:公告
自 2026 年 6 月 1 日起，Xray Core 内部定时器已自动弃用 `allowInsecure`（跳过证书验证），并要求自签证书必须配置 `pinnedPeerCertSha256`（`pcs` 参数）。

若机场使用自签证书且未提供 `pcs` 参数，节点将无法正常连接。

**解决方法：**

* 向机场获取 `pinnedPeerCertSha256`（`pcs` 参数）；
* 或切换至 Sing-box Core。  

## � 新增核心：SRT-VPN（本仓库扩展）

本仓库在官方 passwall 基础上**最小侵入**集成 [luowei729/srt-vpn](https://github.com/luowei729/srt-vpn) 作为新核心：

- **组件更新**：`PassWall -> 组件更新` 页新增 **SRT-VPN** 条目，点击可检查/下载最新核心（`srt-vpn-linux-amd64/arm64` 纯静态二进制，自动匹配架构）
- **节点类型**：`节点列表 -> 添加` 新增 **SRT-VPN** 类型，配置 SRT 服务器地址/端口/passphrase 等参数
- **使用前提**：需有一台 SRT-VPN 服务端（见 srt-vpn 仓库部署文档）
- **接入原理**：srt-vpn 客户端是本地 SOCKS5/HTTP/HTTPS 三合一入口，passwall 通过 socks → ipt2socks 链路做透明代理

```shell
# 组件更新页下载核心后，服务端配置示例（SRT-VPN 服务端侧）
SRT_MODE=server SRT_PASSPHRASE=你的强密码 SRT_LISTEN=0.0.0.0:9000
```

### 同步官方上游

本扩展全部改动集中在以下文件（sync fork 官方 openwrt-passwall 时冲突极小）：

```
luci-app-passwall/luasrc/passwall/com.lua                 # +srt-vpn 组件条目
luci-app-passwall/luasrc/passwall/util_srt-vpn.lua        # 新增：生成 client.json
luci-app-passwall/luasrc/model/cbi/passwall/client/type/7_srt-vpn.lua  # 新增：节点类型
luci-app-passwall/root/usr/share/passwall/app.sh          # +srtvpn 分支
luci-app-passwall/po/zh_Hans/passwall.po                  # 新增翻译
luci-app-passwall/po/zh-cn/passwall.po                    # 新增翻译
.github/workflows/Auto compile with openwrt sdk.yml       # +25.12 apk 编译矩阵 + push tag/release 自动发版编译
```

### 发布新版本（自动编译产出）

打 tag 即自动编译并挂到该版本 Release（无需手动操作）：

```shell
git tag -a 26.8.21 -m "PassWall 26.8.21"
git push origin 26.8.21
```

- 触发方式：`push tag` / 网页发布 Release / 手动 workflow_dispatch（可选版本号）
- 自动编译 4 个目标：22.03-（ipk）、23.05-24.10（ipk）、25.12+（apk）、25.12-apk-（apk）
- 产物自动挂到 `https://github.com/luowei729/openwrt-passwall-srt-vpn/releases/tag/<版本号>`

## �📌如何能编译到最新代码？

### 方法1：

执行 `./scripts/feeds update -a` 操作前，在 `feeds.conf.default` **顶部**插入如下代码：

```
src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main
src-git passwall_luci https://github.com/Openwrt-Passwall/openwrt-passwall.git;main
```

### 方法2：

在 `./scripts/feeds install -a` 操作完成后，执行以下命令：

```shell
# 移除 openwrt feeds 自带的核心库
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,v2ray-plugin,xray-plugin,geoview,shadow-tls}
git clone https://github.com/Openwrt-Passwall/openwrt-passwall-packages package/passwall-packages

# 移除 openwrt feeds 过时的luci版本
rm -rf feeds/luci/applications/luci-app-passwall
git clone https://github.com/Openwrt-Passwall/openwrt-passwall package/passwall-luci
```
