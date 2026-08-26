# Sub-Store Mihomo 覆写 / Shadowrocket 配置

本仓库提供两个彼此独立的配置：

- `substore-mihomo-override.js`：供 Sub-Store 处理 Mihomo 配置。
- `shadowrocket.conf`：直接导入 Shadowrocket，不经过 Sub-Store。

## Mihomo 覆写功能

- 局域网、Apple、Microsoft、OneDrive 和 SSH 22 端口直连
- AI、Telegram、Google、游戏平台独立分流
- Google API 优先走代理，避免 `googleapis.cn` 被中国规则直连
- Pixiv 可选独立分流，默认关闭
- 中国游戏/CDN 直连，海外游戏平台走代理
- 中国大陆直连，海外流量及 MATCH 兜底走代理
- Fake-IP、加密 DNS、DNS 劫持和严格 TUN
- 常见 STUN/WebRTC 拦截（可能影响语音和视频通话）
- YouTube 不单独分流，按海外流量处理

## Mihomo / Sub-Store 使用

1. 在 Sub-Store 中新建 Mihomo 配置，来源选择单条订阅或组合订阅。
2. 添加 JavaScript 覆写，粘贴脚本内容或填写公开仓库的 Raw 链接。
3. 在 Mihomo 客户端导入 Sub-Store 生成的配置链接。
4. 如需增加直连域名，在 `CUSTOM_DIRECT_RULES` 中添加 Mihomo 规则。

### URL 参数

默认开启严格 WebRTC 拦截、关闭 Pixiv 独立分流。

- `#pixiv=true`：新增 `🎨 Pixiv` 策略组并启用 Pixiv 分流。
- `#blockWebrtc=false`：关闭严格 WebRTC 拦截。
- 多参数使用 `&` 连接：

  `https://raw.githubusercontent.com/610841887/substore-override/main/substore-mihomo-override.js#pixiv=true&blockWebrtc=false`

布尔值支持 `true/1/yes/on` 和 `false/0/no/off`；非法值使用默认设置。

## Shadowrocket 使用（不经过 Sub-Store）

配置链接：

`https://raw.githubusercontent.com/610841887/substore-override/main/shadowrocket.conf`

1. 先在 Shadowrocket 首页添加节点或节点订阅。
2. 在“配置”页通过上面的链接下载配置并选中它。
3. 将首页“全局路由”设为“配置”。

配置不要求订阅名称。每个服务分组会直接列出 Shadowrocket 已有节点，可以分别选择；默认 `PROXY` 跟随首页当前节点。它包含独立的 AI、Telegram、Google、游戏平台分组；Apple、Microsoft、腾讯、SSH 22、局域网和中国大陆直连；中国域名通过完整 DOMAIN-SET 匹配，GEOIP 仅处理已经是 IP 的请求，避免海外域名为 GEOIP 判断触发本地 DNS；YouTube 随海外流量走代理；加密 DNS、DNS 劫持和 STUN 假地址用于降低 DNS/WebRTC 泄露风险。

Shadowrocket 配置是静态文件，不解析 URL 的 `#pixiv=true` 参数：

- Pixiv 默认关闭；需要时取消 `Pixiv/Pixiv.list` 规则行前面的 `# `。
- 如需关闭 WebRTC 防泄露，注释 `stun-response-ip` 和 `stun-response-ipv6` 两行。

## 注意

- `GEOIP,CN` 必须保留 `no-resolve`，否则未命中的海外域名会先触发本地 DNS 查询。
- 两份配置默认关闭 IPv6，减少 IPv6 绕行风险。
- 浏览器自身的 ICE 行为无法只靠规则配置完全控制。
- 游戏中国 CDN 依赖规则集分类；漏网域名需要手动补充。
