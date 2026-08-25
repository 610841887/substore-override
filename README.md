# Sub-Store Mihomo 覆写

一个面向 Sub-Store 的 Mihomo JavaScript 覆写脚本。

## 功能

- 局域网、Apple、Microsoft、OneDrive 和 SSH 22 端口直连
- AI、Telegram、游戏平台独立分流
- 中国游戏/CDN 直连，海外游戏平台走代理
- 中国大陆直连，海外流量及 MATCH 兜底走代理
- Fake-IP、加密 DNS、DNS 劫持和严格 TUN
- 常见 STUN/WebRTC 拦截（可能影响语音和视频通话）
- YouTube 不单独分流，按海外流量处理

## 使用

1. 在 Sub-Store 中新建 Mihomo 配置，来源选择单条订阅或组合订阅。
2. 添加 JavaScript 覆写并粘贴 `substore-mihomo-override.js`。
3. 在 Mihomo 客户端导入 Sub-Store 生成的配置链接。
4. 如需关闭严格 WebRTC 拦截，把 `BLOCK_WEBRTC` 改为 `false`。
5. 如需增加直连域名，在 `CUSTOM_DIRECT_RULES` 中添加 Mihomo 规则。

## 注意

- 默认关闭 IPv6，减少 IPv6 绕行风险。
- 浏览器本地 ICE 地址暴露无法仅靠 Mihomo 完全控制。
- 游戏中国 CDN 依赖 GEO 分类；漏网域名可加入 `CUSTOM_DIRECT_RULES`。
