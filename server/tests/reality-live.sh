#!/usr/bin/env bash
# Needs Linux, jq, curl, openssl, iproute2 and a recent Xray on PATH.
# All listeners and generated keys are temporary and local to the test environment.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
pids=()
cleanup() { for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done; rm -rf "$fixture"; }
trap cleanup EXIT
CFG="$fixture"
for fn in _reality_guard_settings _reality_guard_ip _apply_reality_guard; do
    eval "$(awk -v fn="$fn" 'index($0, fn "() {") == 1 {on=1} on {print} on && $0 == "}" {exit}' "$repo/vless-server.sh")"
done
_err() { printf '%s\n' "$*" >&2; }
cd "$fixture"
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -subj /CN=guard.test -days 1 >/dev/null 2>&1
dd if=/dev/zero bs=1024 count=192 status=none | tr '\0' a > data.txt
openssl s_server -accept 127.0.0.1:18444 -cert cert.pem -key key.pem -tls1_3 -alpn h2,http/1.1 -WWW >tls.log 2>&1 &
pids+=("$!")
keys=$(xray x25519)
private=$(awk -F': *' '/PrivateKey:|Private key:/ {print $2}' <<<"$keys")
public=$(awk -F': *' '/^Password|^PublicKey:|^Public key:/ {print $2}' <<<"$keys")
uuid=$(xray uuid)
[[ ${#private} == 43 && ${#public} == 43 ]]
jq -n --arg key "$private" --arg id "$uuid" '{log:{loglevel:"warning"},inbounds:[{
 tag:"vless-test",listen:"127.0.0.1",port:18443,protocol:"vless",
 settings:{clients:[{id:$id,flow:"xtls-rprx-vision"}],decryption:"none"},
 streamSettings:{network:"tcp",security:"reality",realitySettings:{dest:"127.0.0.1:18444",serverNames:["guard.test"],privateKey:$key,shortIds:["12ab"]}}
}],outbounds:[{protocol:"freedom",tag:"direct"}]}' > server.json
printf '%s\n' '{"uploadBytesPerSec":0,"downloadBytesPerSec":32768,"afterBytes":0,"burstBytesPerSec":0}' >reality-guard.json
_apply_reality_guard "$fixture/server.json"
xray run -test -c server.json
xray run -c server.json >server.log 2>&1 &
pids+=("$!")
jq -n --arg key "$public" --arg id "$uuid" '{log:{loglevel:"warning"},inbounds:[{listen:"127.0.0.1",port:18445,protocol:"socks",settings:{auth:"noauth"}}],
 outbounds:[{protocol:"vless",settings:{vnext:[{address:"127.0.0.1",port:18443,users:[{id:$id,flow:"xtls-rprx-vision",encryption:"none"}]}]},
 streamSettings:{network:"tcp",security:"reality",realitySettings:{serverName:"guard.test",fingerprint:"chrome",password:$key,shortId:"12ab"}}}]}' >client.json
xray run -test -c client.json
xray run -c client.json >client.log 2>&1 &
pids+=("$!")
sleep 2
if ! curl -ksS --max-time 15 --http1.1 --noproxy '' --proxy socks5h://127.0.0.1:18445 https://127.0.0.1:18444/data.txt -o authorized; then
    cat client.log server.log >&2; exit 1
fi
cmp data.txt authorized
elapsed=$(curl -ksS --max-time 20 --http1.1 --noproxy '*' --resolve guard.test:18443:127.0.0.1 https://guard.test:18443/data.txt -o fallback -w '%{time_total}')
cmp data.txt fallback
awk -v elapsed="$elapsed" 'BEGIN {exit !(elapsed >= 3)}'
if curl -ksS --max-time 5 --http1.1 --noproxy '*' --resolve wrong.test:18443:127.0.0.1 https://wrong.test:18443/data.txt -o wrong; then
    echo 'Unknown SNI was accepted'; exit 1
fi
# An IP URL omits the TLS SNI extension.
if curl -ksS --max-time 5 --http1.1 --noproxy '*' https://127.0.0.1:18443/data.txt -o nosni; then
    echo 'Missing SNI was accepted'; exit 1
fi
echo "PASS: real REALITY/Vision handshake, authorized proxy, allowed fallback (${elapsed}s), rate limit, unknown/missing SNI blocked"

# Exercise the actual installer templates, including its multi-port database path.
for fn in generate_xray_config _generate_xray_config_raw add_xray_inbound_v2 gen_xray_vless_clients; do
    eval "$(awk -v fn="$fn" 'index($0, fn "() {") == 1 {on=1} on {print} on && $0 == "}" {exit}' "$repo/vless-server.sh")"
done
get_xray_protocols() { printf 'vless\nvless-xhttp\n'; }
_listen_addr() { echo 127.0.0.1; }
db_get_routing_rules() { echo '[]'; }
gen_xray_user_routing_rules() { echo '[]'; }
gen_xray_ip_routing_outbounds() { echo '[]'; }
db_ip_routing_enabled() { return 1; }
db_get_users_stats() { :; }
db_exists() { test -f "$CFG/db-$2.json"; }
db_get() { cat "$CFG/db-$2.json"; }
db_add() { printf '%s\n' "$3" >"$CFG/db-$2.json"; }
db_del() { rm -f "$CFG/db-$2.json"; }
_reality_guard_ip() { echo 127.0.0.1; }
_ok() { echo "$*"; }
_warn() { echo "$*" >&2; }
jq -n --arg key "$private" --arg id "$uuid" '{port:19443,uuid:$id,sni:"guard.test",private_key:$key,short_id:"12ab",path:"/test"}' >db-vless.json
jq '[. + {port:19444}, . + {port:19445}]' db-vless.json >db-vless-xhttp.json
# Upstream functions use optional unset globals and post-increment counters.
set +u
if ! generate_xray_config; then echo 'Installer template generation failed'; exit 1; fi
jq -e '[.inbounds[] | select(.streamSettings.security == "reality")] | length == 3' config.json >/dev/null
jq -e '[.inbounds[] | select(.tag | startswith("reality-defender-"))] | length == 3' config.json >/dev/null
cp config.json before.json
if ! generate_xray_config; then exit 1; fi
cmp config.json before.json
set -u
echo 'PASS: actual installer templates, TCP and multi-port XHTTP, persistent defender on rebuild'
