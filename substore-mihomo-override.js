// Sub-Store -> 文件 -> Mihomo 配置 -> 覆写脚本
// 默认拦截；脚本链接加 #blockWebrtc=false 可关闭。
const WEBRTC_ARG =
  typeof $arguments === "object" && $arguments ? $arguments.blockWebrtc : undefined;
const BLOCK_WEBRTC = !["false", "0", "no", "off"].includes(
  String(WEBRTC_ARG).toLowerCase(),
);

// 在这里追加必须直连的规则，例如："DOMAIN-SUFFIX,example.com,DIRECT"
const CUSTOM_DIRECT_RULES = [];

const GROUP = {
  SELECT: "🚀 节点选择",
  AUTO: "♻️ 自动选择",
  AI: "🤖 AI",
  TELEGRAM: "✈️ Telegram",
  GAME: "🎮 游戏平台",
  ABROAD: "🌍 海外流量",
  FINAL: "🐟 MATCH 兜底",
};

function main(config) {
  if (!config || !Array.isArray(config.proxies)) {
    throw new Error("未找到 config.proxies，请把 Sub-Store 节点/组合订阅设为 Mihomo 配置来源");
  }

  const nodes = [...new Set(config.proxies.map((proxy) => proxy && proxy.name).filter(Boolean))];
  if (!nodes.length) throw new Error("订阅中没有可用节点");

  const selectGroup = (name, first = []) => ({
    name,
    type: "select",
    proxies: [...first, ...nodes, "DIRECT"],
  });

  config.mode = "rule";
  config.ipv6 = false;
  config["geodata-mode"] = true;
  config["geo-auto-update"] = true;
  config["geo-update-interval"] = 24;
  config["geox-url"] = {
    ...(config["geox-url"] || {}),
    geoip: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat",
    geosite: "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat",
  };

  config.profile = {
    ...(config.profile || {}),
    "store-selected": true,
    "store-fake-ip": true,
  };

  config.tun = {
    enable: true,
    stack: "mixed",
    "auto-route": true,
    "auto-detect-interface": true,
    "strict-route": true,
    "dns-hijack": ["any:53", "tcp://any:53"],
  };

  const domesticDns = [
    "https://dns.alidns.com/dns-query",
    "https://doh.pub/dns-query",
  ];
  const overseasDns = [
    "https://cloudflare-dns.com/dns-query",
    "https://dns.google/dns-query",
  ];

  config.dns = {
    enable: true,
    listen: "0.0.0.0:1053",
    ipv6: false,
    "enhanced-mode": "fake-ip",
    "fake-ip-range": "198.18.0.1/16",
    "fake-ip-filter-mode": "blacklist",
    "fake-ip-filter": ["*.lan", "*.local"],
    "use-hosts": true,
    "use-system-hosts": true,
    "respect-rules": true,
    "default-nameserver": ["tls://223.5.5.5", "tls://1.1.1.1"],
    "nameserver-policy": {
      "geosite:cn,private": domesticDns,
      "geosite:geolocation-!cn": overseasDns,
    },
    nameserver: overseasDns,
    "proxy-server-nameserver": domesticDns,
    "direct-nameserver": domesticDns,
    "direct-nameserver-follow-policy": true,
  };

  config["proxy-groups"] = [
    selectGroup(GROUP.SELECT, [GROUP.AUTO]),
    {
      name: GROUP.AUTO,
      type: "url-test",
      proxies: nodes,
      url: "https://www.gstatic.com/generate_204",
      interval: 300,
      tolerance: 50,
      lazy: true,
    },
    selectGroup(GROUP.AI, [GROUP.SELECT, GROUP.AUTO]),
    selectGroup(GROUP.TELEGRAM, [GROUP.SELECT, GROUP.AUTO]),
    selectGroup(GROUP.GAME, [GROUP.SELECT, GROUP.AUTO]),
    selectGroup(GROUP.ABROAD, [GROUP.SELECT, GROUP.AUTO]),
    selectGroup(GROUP.FINAL, [GROUP.ABROAD, GROUP.SELECT]),
  ];

  const rtcRules = BLOCK_WEBRTC
    ? [
        "GEOSITE,category-stun,REJECT",
        "DST-PORT,3478/3479/3480/3481/5349/19302,REJECT",
      ]
    : [];

  config.rules = [
    ...CUSTOM_DIRECT_RULES,
    "DST-PORT,22,DIRECT",
    "GEOSITE,private,DIRECT",
    "GEOIP,private,DIRECT,no-resolve",
    ...rtcRules,
    // ponytail: GEO 分类只能近似识别中国下载 CDN；漏网域名可追加到 CUSTOM_DIRECT_RULES。
    "GEOSITE,steam@cn,DIRECT",
    "GEOSITE,category-games@cn,DIRECT",
    "GEOSITE,category-games-cn,DIRECT",
    `GEOSITE,category-games-!cn,${GROUP.GAME}`,
    "GEOSITE,apple,DIRECT",
    "GEOSITE,microsoft,DIRECT",
    "GEOSITE,onedrive,DIRECT",
    `GEOSITE,category-ai-!cn,${GROUP.AI}`,
    `GEOSITE,telegram,${GROUP.TELEGRAM}`,
    `GEOIP,telegram,${GROUP.TELEGRAM},no-resolve`,
    `GEOSITE,geolocation-!cn,${GROUP.ABROAD}`,
    "GEOSITE,cn,DIRECT",
    "GEOIP,CN,DIRECT",
    `MATCH,${GROUP.FINAL}`,
  ];

  return config;
}
