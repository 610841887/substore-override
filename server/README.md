# VLESS / REALITY 防护预览版

版本：`3.7.3-preview.1`。独立于本仓库的 Sub-Store 和 Shadowrocket 配置。

基于 [mozisen/surge](https://github.com/mozisen/surge) 的 `vless-server.sh` 3.7.2，固定来源提交 `8dfe4d0da1383ecde6bcd2c43227c5d407ecd7c5`。保留原作者署名、菜单、多协议和用户管理；`nft.sh` 与原有测试来自同一提交。上游该提交未发现 LICENSE，本目录不另行声明或授予上游代码许可证。

## 安装

预览分支：`codex/reality-defender-preview`。在 Linux 服务器上以 root 运行，建议先备份现有配置并使用测试 VPS；不要在本地电脑执行安装。

```bash
wget -O vless-server.sh https://raw.githubusercontent.com/610841887/substore-override/codex/reality-defender-preview/server/vless-server.sh && bash vless-server.sh
```

首次安装按原菜单选择 VLESS + REALITY，客户端信息仍由原脚本生成。脚本会安装依赖、修改服务和网络配置；下载后可先审阅再执行。

脚本更新和 nft 辅助脚本从本仓库同一分支下载，不跟随上游覆盖本修改。默认不发布 GitHub Release。原脚本依赖的第三方核心、Sing-box 统计预编译产物及其他外部安装资源仍保留原下载来源；这不是完整供应链审计。

## 防护行为

- 每个 Xray REALITY 入站自动生成独立的本地 `dokodemo-door` defender，适用于 TCP、XHTTP 和生成器创建的多 IP 副本。
- target 转向本地 defender，TLS SNI 精确匹配原 `serverNames` 才放行，其余由专用 blackhole 拦截；规则位于普通用户分流之前。
- defender 的远端目的地址固定为生成时解析到的 IP，避免没有 SNI 时因原目的域名匹配而放行。DNS 改变后需重新生成配置；解析失败则保留旧配置。
- 这不更改客户端 UUID、公钥、SNI 或 ShortID，也不适用于 Sing-box 入站。
- 不要手动把所有回落都改成拒绝：合法 REALITY 握手也需要连接 target。

菜单 **15** 设置未认证回落的上传、下载限速。设置保存在配置目录的 `reality-guard.json`，后续用户修改和重建时重新应用。

| 字段 | 默认 | 含义 |
| --- | --- | --- |
| uploadBytesPerSec | 0 | 每条回落连接的上传字节/秒，0 关闭 |
| downloadBytesPerSec | 0 | 每条回落连接的下载字节/秒，0 关闭 |
| afterBytes | 1048576 | 传输多少字节后开始限速 |
| burstBytesPerSec | 0 | 原生令牌桶突发容量，0 使用核心默认行为 |

所有值须为 0..1073741824 的整数。限速使用 Xray 原生 `limitFallbackUpload` / `limitFallbackDownload`，需要支持该功能的版本；本次实测版本为 26.3.27，不保证旧核心识别未知字段。

**这不是防封保证，也不能彻底阻止刷流量。** 正确 SNI 的未认证请求仍可访问 target 内容，大量并发可绕过单连接限速。限速及回落拒绝行为可能形成可探测差异，因此限速默认关闭。目标需具有兼容的 TLS 服务，不能仅按域名知名度选择。

## 配置保护

生成器写临时文件，添加 defender 后通过 `xray run -test` 才原子替换正式配置。生成与脚本内 Xray 服务操作使用文件锁；启动成功并通过短时间进程存活检查后保存 `config.json.last-good`。启动失败则恢复该备份并尝试启动；首次安装无备份时停止失败服务并报错。

回滚仅恢复 Xray 运行配置，不回退用户数据库、流量统计、内核二进制或防火墙。失败后须修正数据库设置再重建。进程存活检查不等于公网连通性检查；手动 systemctl、证书续期外部钩子等不经过脚本服务包装器的重启不受此回滚覆盖。

## 验证

在 Debian 12 ARM64 容器中运行，未在用户 VPS 安装：

```bash
bash -n vless-server.sh
bash tests/reality-guard.sh
bash tests/reality-live.sh
shellcheck -S error vless-server.sh tests/reality-guard.sh tests/reality-live.sh
```

- 配置验证失败保留旧文件、模拟启动失败恢复旧配置、规则优先级、端口分配与限速参数测试通过。
- 使用真实 Xray 26.3.27 的 REALITY/Vision 客户端成功传输；同 SNI 回落与限速正常，错误和缺失 SNI 被拒绝。
- 实际安装器 TCP 与多端口 XHTTP 模板通过核心校验，重复重建保留防护。
- 上游离线测试 9 项通过；`singbox-stats-query.sh` 和 `singbox-stats-update.sh` 失败，在原版同一提交和同一环境中也失败，未修改这些测试。
- 未运行上游 `singbox-stats-live.sh`，未完成真实 systemd/OpenRC VPS 的安装及故障回滚演练；服务回滚测试使用模拟服务。

`reality-live.sh` 需要 Linux、近期 Xray、jq、curl、openssl、iproute2 和 util-linux，使用本机临时端口 18443..18445、43166 起及临时密钥。建议在隔离容器中运行。
