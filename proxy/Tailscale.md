# Tailscale 服务级代理

## 结论

此机器所在网络无法稳定直连 Tailscale 的控制面：对真实服务器地址的 TCP 443
连接会超时。因此让 `tailscaled` **单独**经本机 Mihomo 的 mixed port 访问控制面和
DERP。不要设置全局 `HTTP_PROXY`，也不要给登录 shell 常驻代理变量。

这只为 Tailscale 的 HTTPS 控制和 DERP 回退流量提供出口；节点之间仍会优先尝试
WireGuard UDP 直连，失败时由 Tailscale 自动经 DERP 转发。

## 当前配置

### systemd drop-in

文件：`/etc/systemd/system/tailscaled.service.d/10-clash-proxy.conf`

```ini
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:<MIXED_PORT>"
Environment="HTTPS_PROXY=http://127.0.0.1:<MIXED_PORT>"
Environment="NO_PROXY=localhost,127.0.0.1"
```

当前 `<MIXED_PORT>` 为 `7897`。修改后生效：

```bash
sudo systemctl daemon-reload
sudo systemctl restart tailscaled
```

### Mihomo 规则

不要让下列域名命中 `DIRECT`。当 `tailscaled` 使用本机 HTTP 代理时，Mihomo 收到
CONNECT 后还会继续按规则选择出口；若仍强制 `DIRECT`，表现为 CONNECT 返回 200，
但随后 TLS 握手超时。

在 Clash Verge Rev 的全局扩展脚本中，将下面规则放在订阅规则之前：

```javascript
"DOMAIN-SUFFIX,tailscale.com,<PROXY_GROUP>",
"DOMAIN-SUFFIX,tailscale.io,<PROXY_GROUP>",
```

同时把 `tailscale.com`、`*.tailscale.com`、`tailscale.io`、`*.tailscale.io` 保留在
Mihomo DNS 的 `fake-ip-filter` 中，避免 TUN Fake-IP 参与这些服务域名的解析。

### 规则顺序与配置漂移

如果还有 `PROCESS-NAME,tailscaled,DIRECT` 或 `PROCESS-NAME,tailscale,DIRECT`，
上面的控制面域名代理规则必须位于它们之前，否则先命中进程规则仍会直连。
Tailnet 的 `100.64.0.0/10`、`fd7a:115c:a1e0::/48` 数据面保留直连策略；
服务级 HTTP 代理、Mihomo 路由规则和 DNS 必须按同一方案核验。

`fake-ip-filter` 也可使用 `+.tailscale.com`、`+.tailscale.io` 的域名通配语法。
这不等于配置 MagicDNS；内部 Tailnet 域名应由系统分域 DNS 或专门的 DNS policy 处理。
不要为解决局部 DNS 问题将整个 Mihomo 出口固定到 Tailscale 网卡。

2026-09-15 核验发现一台机器仍使用早期的控制面 DIRECT 规则，且最终配置没有
对应 Fake-IP 排除。已通过持久化扩展脚本补齐并核验内核规则。
这是配置一致性修复，不是 Codex 重连根因的证明；参见
[connection-diagnostics.md](connection-diagnostics.md)。

本机持久化位置：

- `~/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/Script.js`
- `~/.local/share/io.github.clash-verge-rev.clash-verge-rev/dns_config.yaml`

最终的 `clash-verge.yaml` 是客户端生成物；应编辑全局扩展脚本和 DNS 覆写，而不是
只手改生成文件。

## 验证记录（2026-08-29）

配置后：

- `tailscaled` 成功登录并恢复 Tailnet 身份。
- `tailscale netcheck` 显示 UDP 可用、UPnP 映射可用，东京 DERP 约 52 ms。
- 对在线节点的 `tailscale ping` 可通，但当时经 DERP 中继，尚未建立直连。这通常由对端
  NAT 或防火墙条件决定，不影响正常使用，只影响延迟。

日常检查：

```bash
sudo systemctl status tailscaled
sudo tailscale status
sudo tailscale netcheck
sudo tailscale ping <machine-name>
```

`tailscale` 命令在此安装方式下可能需要 `sudo` 才能访问 `/run/tailscale` 的服务 socket。

## 回滚

需要改回网络层直连/旁路由方案时：

```bash
sudo rm /etc/systemd/system/tailscaled.service.d/10-clash-proxy.conf
sudo systemctl daemon-reload
sudo systemctl restart tailscaled
```

然后把扩展脚本中的两条 Tailscale 域名规则改为 `DIRECT`，或删除它们交给旁路由规则集。
在当前普通网络出口下，`DIRECT` 已验证会导致控制面超时。
