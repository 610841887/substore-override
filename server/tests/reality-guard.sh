#!/usr/bin/env bash
# Isolated regression tests; never source the installer entry point.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
CFG="$fixture"
load_function() {
    eval "$(awk -v fn="$1" 'index($0, fn "() {") == 1 {on=1} on {print} on && $0 == "}" {exit}' "$repo/vless-server.sh")"
}
for fn in _reality_guard_settings _reality_guard_ip _apply_reality_guard generate_xray_config svc; do load_function "$fn"; done
_err() { printf '%s\n' "$*" >&2; }
_generate_xray_config_raw() { cp "$fixture/input.json" "$XRAY_CONFIG_FILE"; }
# Only external dependencies are stubbed for transaction tests.
xray() { jq -e '.reject != true' "${@: -1}" >/dev/null; }
_svc_raw() {
    printf '%s\n' "$1" >>"$fixture/service-actions"
    [[ "$1" == stop ]] || jq -e '.failStart != true' "$CFG/config.json" >/dev/null
}
_xray_service_healthy() { return 0; }
printf '%s\n' '{"marker":"old","inbounds":[],"outbounds":[]}' >"$CFG/config.json"
printf '%s\n' '{"marker":"bad","reject":true,"inbounds":[]}' >"$fixture/input.json"
if generate_xray_config; then echo 'invalid candidate was accepted'; exit 1; fi
jq -e '.marker == "old"' "$CFG/config.json" >/dev/null
printf '%s\n' '{"marker":"bad-start","failStart":true,"inbounds":[]}' >"$fixture/input.json"
generate_xray_config
if svc restart vless-reality; then echo 'failed restart was accepted'; exit 1; fi
jq -e '.marker == "old"' "$CFG/config.json" >/dev/null
grep -qx stop "$fixture/service-actions"
printf '%s\n' '{"marker":"good","inbounds":[]}' >"$fixture/input.json"
generate_xray_config
svc restart vless-reality
jq -e '.marker == "good"' "$CFG/config.json.last-good" >/dev/null

cat >"$fixture/input.json" <<'JSON'
{"inbounds":[
 {"tag":"vless-443","port":443,"protocol":"vless","streamSettings":{"security":"reality","realitySettings":{"dest":"127.0.0.1:18444","serverNames":["guard.test"]}}},
 {"tag":"vless-xhttp-8443","port":8443,"protocol":"vless","streamSettings":{"network":"xhttp","security":"reality","realitySettings":{"dest":"[::1]:18444","serverNames":["second.test"]}}},
 {"tag":"socks","port":43166,"protocol":"socks"}
],"outbounds":[{"tag":"direct","protocol":"freedom"}],
"routing":{"rules":[{"type":"field","network":"tcp","outboundTag":"direct"}]}}
JSON
generate_xray_config
jq -e '
 [.inbounds[]|select(.protocol=="dokodemo-door")] as $d |
 ($d|length)==2 and ($d|map(.port)|unique|length)==2 and
 all($d[];.listen=="127.0.0.1" and .port!=43166 and .sniffing.routeOnly==true) and
 .routing.rules[0].domain==["full:second.test"] and
 .routing.rules[1].outboundTag=="reality-guard-block" and
 .routing.rules[2].domain==["full:guard.test"] and
 .routing.rules[3].outboundTag=="reality-guard-block" and
 .routing.rules[4].network=="tcp" and
 ([.inbounds[]|select(.protocol=="dokodemo-door")|.settings.address]|sort)==["127.0.0.1","::1"]
' "$CFG/config.json" >/dev/null
cp "$CFG/config.json" "$fixture/first.json"
generate_xray_config
cmp "$CFG/config.json" "$fixture/first.json"
printf '%s\n' '{"uploadBytesPerSec":32768,"downloadBytesPerSec":65536,"afterBytes":4096,"burstBytesPerSec":1024}' >"$CFG/reality-guard.json"
generate_xray_config
jq -e 'all(.inbounds[]|select(.streamSettings.security=="reality"); .streamSettings.realitySettings.limitFallbackDownload.bytesPerSec==65536)' "$CFG/config.json" >/dev/null
cp "$CFG/config.json" "$fixture/limited.json"
printf '%s\n' '{"uploadBytesPerSec":-1}' >"$CFG/reality-guard.json"
if generate_xray_config; then echo 'invalid limits were accepted'; exit 1; fi
cmp "$CFG/config.json" "$fixture/limited.json"

# Verify fork update metadata without running installer initialization.
grep -q '^readonly SCRIPT_SOURCE_REPO="610841887/substore-override"' "$repo/vless-server.sh"
grep -q '^readonly SCRIPT_SOURCE_PATH="server/vless-server.sh"' "$repo/vless-server.sh"
echo 'PASS: rejected candidates, failed-start rollback, successful promotion, TCP/XHTTP, port collisions, regeneration, limits, fork source'
