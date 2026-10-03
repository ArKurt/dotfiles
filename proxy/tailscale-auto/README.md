# Tailscale 与 FlClash 按需联动（2026-10-03）

此 MacBook 的 FlClash 已配置家庭 Wi-Fi 排除名单，mixed port 为
7890。Tailscale 的独立 systemd 服务不会继承 GUI 的按需策略，固定代理变量会使它
依赖已关闭的 FlClash。这里为 Tailscale 补上自动选择和启动顺序处理。

## 策略

| 网络和代理状态 | Tailscale 控制面及 HTTPS 中继 |
| --- | --- |
| 家庭 Wi-Fi（本机排除名单） | 不设置有效代理，通过家庭网关 |
| 外部网络，127.0.0.1:7890 已监听 | 经 FlClash HTTP CONNECT |
| 外部网络，FlClash 未就绪或已关闭 | 取消固定代理，尝试网络层路径；每 15 秒复查 |
| 没有物理网络连接 | 检查任务不重启服务；开机时默认无代理 |

不负责启动或关闭 FlClash，沿用它自己的按需策略。UDP 数据面仍由 Tailscale
处理，未改路由、DNS、订阅或退出节点。监听探测只验证端口可连接，不证明代理出口
或 Tailscale 的加密控制连接可用；实际健康状态仍看 `tailscale status`。

家庭网络与端口保存在 root 管理的 `/etc/tailscale-proxy.json`，来源为此次核验的
FlClash 设置快照。后续修改 FlClash 的排除名单或端口时，需要同步修改此文件；
root 脚本不执行或动态导入用户可写的 FlClash 配置。

## 实现

- `sync.py` 用 NetworkManager 查询当前物理连接的实际 SSID，不使用易变的事件快照。
- `ExecStartPre` 每次启动 Tailscale 时重新选择，原子写入 `/run/tailscale-proxy/environment`。
- systemd `EnvironmentFile` 给随后启动的主进程传入环境，清空不适用的其他代理变量。
- NetworkManager dispatcher 只排队启动短检查任务，不阻塞网络激活。忽略 tailscale0 事件。
- timer 每 15 秒补查 GUI 内核的启动、停止以及漏掉的网络事件。
- 仅环境内容变化时 `try-restart`，不会启动被用户停止的 Tailscale，也不注销账号。

模式切换会短暂重启 VPN；重启后沿用已登录的身份。用户主动停止 Tailscale 时，
timer 仍存在，但不会把它启动。家庭直连不是固定 HTTP 代理的自动失败回退。

## 安装、检查与恢复

仓库中的 `config.json` 已脱敏。安装前将 `YOUR_HOME_WIFI_SSID` 替换为实际家庭
SSID，并确认端口与 FlClash 一致；不要直接用模板覆盖已部署的本机配置。
公开仓库不保存真实 SSID、账号、设备地址或登录链接。本次脱敏不修改已部署的
`/etc/tailscale-proxy.json`，因此不会影响当前按需切换。

```bash
sudo -A bash install.sh
/usr/local/libexec/tailscale-proxy-sync status
systemctl status tailscale-proxy-sync.timer
tailscale status
journalctl -u tailscale-proxy-sync.service -u tailscaled --since '5 minutes ago'
```

依赖：已安装的 Python 3、NetworkManager/nmcli、systemd、Tailscale。安装脚本先将
已有目标文件备份到 `/var/backups/tailscale-proxy/<时间>/`。

此次首次部署的固定代理备份为
`/etc/systemd/system/tailscaled.service.d/10-clash-proxy.conf.before-auto-20261003`。
回到固定代理时，先禁用 timer 并将 dispatcher 移出 dispatcher.d，恢复该备份到
`10-clash-proxy.conf`，再 `systemctl daemon-reload`、`systemctl restart tailscaled`。
固定代理仍要求 FlClash 持续运行。

## 验证与边界

当前外部 Wi-Fi：实测选择 proxy，日志记录控制面 CONNECT 200，Tailscale 恢复
Running、Online=true、Health=[]。重复检查未改变服务启动时间。
六种网络/端口组合、direct/proxy 环境文件生成、幂等检查和模式变化重启均通过
隔离测试。systemd 定义在宿主机验证通过。

家庭 Wi-Fi 当前不在连接范围内，尚未实测切回家庭网关后的控制面可达性；已验证
该 SSID 的选择逻辑会生成空代理。回家后请检查 status 的 desired=direct 与
tailscale 的 Online/Health。外部 FlClash 未运行时也不保证直连可用。

## 调研依据

- [Tailscale 代理源码](https://github.com/tailscale/tailscale/blob/main/net/tshttpproxy/tshttpproxy.go)：FromEnvironment 缓存代理配置；网络变化的 InvalidateCache 不是修改进程环境。
- [Tailscale 环境配置说明](https://tailscale.com/docs/reference/messages/client/could-not-apply-config)：HTTP_PROXY 属于后台服务参数。
- [NetworkManager dispatcher 官方说明](https://networkmanager.dev/docs/api/latest/NetworkManager-dispatcher.html)：root 权限要求、up/down/DHCP/connectivity 事件、排队事件可能过时。
- [systemd.exec](https://www.freedesktop.org/software/systemd/man/latest/systemd.exec.html)：EnvironmentFile 在进程执行前、之前启动阶段完成后读取。
- [FlClash 配置源码](https://github.com/chen08209/FlClash/blob/main/lib/models/config.dart)：excludeSSIDs 配置字段。
- [上游代理域名 DNS 死锁讨论](https://github.com/tailscale/tailscale/issues/18190)：本方案使用回环 IP，避免解析代理主机名的依赖。
- [上游 DialPlan/代理讨论](https://github.com/tailscale/tailscale/issues/20801)：连接候选失败不一定是掉线，应核验后续 DNS 回退和真实健康状态。该问题未在本次被确认为根因。
