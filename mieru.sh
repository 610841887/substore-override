#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPO="enfein/mieru"
readonly RELAY_SOCKET="/etc/systemd/system/mieru-forward.socket"
readonly RELAY_SERVICE="/etc/systemd/system/mieru-forward.service"
work_dir=""
package_kind=""
package_asset=""

cleanup() {
  [[ -z "$work_dir" || ! -d "$work_dir" ]] || rm -r -- "$work_dir"
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
用法：
  ./mieru.sh                              打开交互菜单
  ./mieru.sh install                      安装 mita 落地服务端
  ./mieru.sh relay                        交互配置前置 TCP 中转
  ./mieru.sh relay <监听端口> <IX IPv4> <IX 端口>
  ./mieru.sh uninstall                    卸载 mita 和本脚本创建的中转
  ./mieru.sh --help                       显示帮助
EOF
}

die() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

ensure_root() {
  [[ $EUID -eq 0 ]] && return
  command -v sudo >/dev/null || die "请使用 root 运行，或先安装 sudo"
  exec sudo -- "$BASH" "$0" "$@"
}

require_linux_systemd() {
  [[ "$(uname -s)" == "Linux" ]] || die "仅支持 Linux 服务器"
  [[ -d /run/systemd/system ]] || die "当前系统未使用 systemd"
  command -v systemctl >/dev/null || die "未找到 systemctl"
}

valid_port() {
  [[ "${1:-}" =~ ^[0-9]{1,5}$ ]] && ((10#$1 >= 1 && 10#$1 <= 65535))
}

valid_high_port() {
  valid_port "${1:-}" && ((10#$1 >= 1025))
}

valid_ipv4() {
  local octet
  local -a octets

  IFS=. read -r -a octets <<<"${1:-}"
  [[ ${#octets[@]} -eq 4 ]] || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^(0|[1-9][0-9]{0,2})$ ]] || return 1
    ((octet <= 255)) || return 1
  done
}

valid_credential() {
  [[ "${1:-}" =~ ^[A-Za-z0-9._-]{1,64}$ ]]
}

random_hex() {
  local bytes="$1"
  od -An -N"$bytes" -tx1 /dev/urandom | tr -d ' \n'
}

random_seed() {
  local number

  read -r number < <(od -An -N4 -tu4 /dev/urandom)
  printf '%s\n' "$((number % 2147483647 + 1))"
}

answer_yes() {
  case "${1:-}" in
    ""|y|Y|yes|Yes|YES) return 0 ;;
    n|N|no|No|NO) return 1 ;;
    *) die "请输入 y 或 n" ;;
  esac
}

port_in_use() {
  command -v ss >/dev/null || return 1
  ss -H -ltn "sport = :$1" 2>/dev/null | grep -q .
}

random_high_port() {
  local attempt number port

  for ((attempt = 0; attempt < 50; attempt++)); do
    read -r number < <(od -An -N4 -tu4 /dev/urandom)
    port=$((20000 + number % 40001))
    if ! port_in_use "$port"; then
      printf '%s\n' "$port"
      return
    fi
  done
  die "未能找到可用的随机高位端口"
}

latest_version() {
  local release_url

  release_url="$(curl --proto '=https' --tlsv1.2 -fsSL -o /dev/null \
    -w '%{url_effective}' "https://github.com/$REPO/releases/latest")" || \
    die "查询 Mieru 最新版本失败"
  [[ "$release_url" =~ /tag/v([0-9]+\.[0-9]+\.[0-9]+)/?$ ]] || \
    die "无法从发布地址解析版本：$release_url"
  printf '%s\n' "${BASH_REMATCH[1]}"
}

detect_package_asset() {
  local version="$1" deb_arch rpm_arch

  case "$(uname -m)" in
    x86_64|amd64)
      deb_arch="amd64"
      rpm_arch="x86_64"
      ;;
    aarch64|arm64)
      deb_arch="arm64"
      rpm_arch="aarch64"
      ;;
    *) die "仅支持 x86_64 和 arm64 CPU" ;;
  esac

  if command -v dpkg-query >/dev/null && dpkg-query -W base-files >/dev/null 2>&1; then
    package_kind="deb"
    package_asset="mita_${version}_${deb_arch}.deb"
  elif command -v rpm >/dev/null && rpm -q rpm >/dev/null 2>&1; then
    package_kind="rpm"
    package_asset="mita-${version}-1.${rpm_arch}.rpm"
  else
    die "仅支持 Debian/Ubuntu 和 RHEL/CentOS/Rocky/Fedora"
  fi
}

install_package() {
  local version base_url

  command -v curl >/dev/null || die "请先安装 curl"
  command -v sha256sum >/dev/null || die "请先安装 coreutils"
  version="$(latest_version)"
  detect_package_asset "$version"
  work_dir="$(mktemp -d)"
  base_url="https://github.com/$REPO/releases/download/v$version"

  printf '正在下载 mita %s...\n' "$version"
  curl --proto '=https' --tlsv1.2 -fL --retry 3 \
    "$base_url/$package_asset" -o "$work_dir/$package_asset"
  curl --proto '=https' --tlsv1.2 -fL --retry 3 \
    "$base_url/$package_asset.sha256.txt" -o "$work_dir/$package_asset.sha256.txt"
  (cd "$work_dir" && sha256sum -c "$package_asset.sha256.txt")

  if [[ "$package_kind" == "deb" ]]; then
    dpkg -i "$work_dir/$package_asset"
  else
    rpm -Uvh --force "$work_dir/$package_asset"
  fi
  printf 'mita %s 安装完成。\n' "$version"
}

public_ipv4() {
  local address

  address="$(curl -4 --proto '=https' --tlsv1.2 -fsSL --max-time 8 \
    https://checkip.amazonaws.com 2>/dev/null || true)"
  address="${address//$'\n'/}"
  valid_ipv4 "$address" && printf '%s\n' "$address"
}

install_server() {
  local port username password config_file client_file mihomo_file server_ip status attempt
  local traffic_choice traffic_seed="" server_traffic_pattern="" client_traffic_pattern=""
  local traffic_pattern_value="" traffic_pattern_output mihomo_traffic_pattern=""
  local traffic_pattern_enabled=0

  [[ $# -eq 0 ]] || die "install 不接受其他参数"
  ensure_root install
  require_linux_systemd
  [[ ! -s /etc/mita/server.conf.pb ]] || \
    die "检测到已有 mita 配置，为避免覆盖已停止。请先备份后卸载。"

  read -r -p "mita TCP 监听端口（回车随机 20000-60000）：" port
  port="${port:-$(random_high_port)}"
  valid_high_port "$port" || die "监听端口必须是 1025-65535"
  port_in_use "$port" && die "TCP 端口 $port 已被占用"

  read -r -p "用户名（回车随机）：" username
  username="${username:-m$(random_hex 4)}"
  valid_credential "$username" || die "用户名仅允许 1-64 位字母、数字、点、下划线和连字符"

  read -r -s -p "密码（回车随机）：" password
  printf '\n'
  password="${password:-$(random_hex 12)}"
  valid_credential "$password" || die "密码仅允许 1-64 位字母、数字、点、下划线和连字符"

  read -r -p "启用保守随机流量特征（可能增加延迟和流量）？[Y/n]：" traffic_choice
  if answer_yes "$traffic_choice"; then
    traffic_pattern_enabled=1
    traffic_seed="$(random_seed)"
    printf -v server_traffic_pattern \
      '"trafficPattern": {"seed": %s, "unlockAll": false},\n  ' "$traffic_seed"
    printf -v client_traffic_pattern \
      '"trafficPattern": {"seed": %s, "unlockAll": false},\n    ' "$traffic_seed"
  fi

  install_package
  command -v mita >/dev/null || die "mita 安装后仍不可用"
  systemctl restart mita
  for ((attempt = 0; attempt < 10; attempt++)); do
    if systemctl is-active --quiet mita && [[ -S /var/run/mita/mita.sock ]]; then
      break
    fi
    sleep 1
  done
  systemctl is-active --quiet mita || die "mita systemd 服务启动失败"
  [[ -S /var/run/mita/mita.sock ]] || die "mita 管理套接字未就绪"

  config_file="$work_dir/server.json"
  cat >"$config_file" <<EOF
{
  "portBindings": [{"port": $port, "protocol": "TCP"}],
  "users": [{"name": "$username", "password": "$password"}],
  ${server_traffic_pattern}"loggingLevel": "INFO",
  "mtu": 1400
}
EOF
  mita apply config "$config_file"
  mita stop >/dev/null 2>&1 || true
  mita start
  sleep 1
  status="$(mita status)"
  [[ "$status" == *'"RUNNING"'* ]] || die "mita 未进入 RUNNING 状态：$status"

  if ((traffic_pattern_enabled)); then
    traffic_pattern_value="$(mita export traffic-pattern)" || die "导出流量特征失败"
    [[ "$traffic_pattern_value" =~ ^[A-Za-z0-9+/]+={0,2}$ ]] || \
      die "mita 返回了无效的流量特征"
    traffic_pattern_output="  流量特征：$traffic_pattern_value"
    printf -v mihomo_traffic_pattern '    traffic-pattern: "%s"\n' \
      "$traffic_pattern_value"
  else
    traffic_pattern_output="  流量特征：未启用（客户端留空）"
  fi

  server_ip="$(public_ipv4 || true)"
  server_ip="${server_ip:-<服务器公网IPv4>}"
  client_file="/etc/mita/generated-client.json"
  (umask 077; cat >"$client_file" <<EOF
{
  "profiles": [{
    "profileName": "default",
    "user": {"name": "$username", "password": "$password"},
    "servers": [{
      "ipAddress": "$server_ip",
      "portBindings": [{"port": $port, "protocol": "TCP"}]
    }],
    ${client_traffic_pattern}"mtu": 1400,
    "multiplexing": {"level": "MULTIPLEXING_HIGH"},
    "handshakeMode": "HANDSHAKE_STANDARD"
  }],
  "activeProfile": "default",
  "rpcPort": 8964,
  "socks5Port": 1080,
  "loggingLevel": "INFO",
  "socks5ListenLAN": false,
  "httpProxyPort": 8080,
  "httpProxyListenLAN": false
}
EOF
  )

  mihomo_file="/etc/mita/generated-mihomo.yaml"
  (umask 077; cat >"$mihomo_file" <<EOF
proxies:
  - name: "Mieru-$server_ip"
    type: mieru
    server: "$server_ip"
    port: $port
    transport: TCP
    username: "$username"
    password: "$password"
    multiplexing: MULTIPLEXING_HIGH
    handshake-mode: HANDSHAKE_STANDARD
${mihomo_traffic_pattern}
EOF
  )

  cat <<EOF

安装成功，节点信息：
  地址：$server_ip
  端口：$port
  协议：TCP
  用户名：$username
  密码：$password
$traffic_pattern_output
  客户端配置：$client_file
  Mihomo 订阅文件：$mihomo_file

请放行服务器安全组/防火墙 TCP $port。
使用前置中转时，客户端的地址和端口改为最前端入口，账号密码不变。
EOF
  printf '\nMihomo 节点 YAML（可直接导入或作为代理提供者内容）：\n'
  cat "$mihomo_file"
}

find_socket_proxyd() {
  local candidate

  for candidate in "$(command -v systemd-socket-proxyd 2>/dev/null || true)" \
    /usr/lib/systemd/systemd-socket-proxyd \
    /lib/systemd/systemd-socket-proxyd; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
  return 1
}

configure_relay() {
  local listen_port="" ix_ip="" ix_port="" proxyd relay_was_active=0

  [[ $# -eq 0 || $# -eq 3 ]] || die "relay 需要 0 或 3 个参数"
  if [[ $# -eq 3 ]]; then
    listen_port="$1"
    ix_ip="$2"
    ix_port="$3"
    valid_high_port "$listen_port" || die "前置监听端口必须是 1025-65535"
    valid_ipv4 "$ix_ip" || die "IX 地址必须是合法的 IPv4"
    valid_port "$ix_port" || die "IX 端口必须是 1-65535"
  fi

  ensure_root relay "$@"
  require_linux_systemd
  if [[ $# -eq 0 ]]; then
    read -r -p "前置 TCP 监听端口（回车随机 20000-60000）：" listen_port
    listen_port="${listen_port:-$(random_high_port)}"
    read -r -p "IX IPv4：" ix_ip
    read -r -p "IX 端口：" ix_port
    valid_high_port "$listen_port" || die "前置监听端口必须是 1025-65535"
    valid_ipv4 "$ix_ip" || die "IX 地址必须是合法的 IPv4"
    valid_port "$ix_port" || die "IX 端口必须是 1-65535"
  fi

  proxyd="$(find_socket_proxyd)" || die "未找到 systemd-socket-proxyd"
  # ponytail: 单条转发覆盖当前链路，需要多入口时再改为模板单元。
  systemctl is-active --quiet mieru-forward.socket && relay_was_active=1
  systemctl stop mieru-forward.service mieru-forward.socket >/dev/null 2>&1 || true
  if port_in_use "$listen_port"; then
    ((relay_was_active)) && systemctl start mieru-forward.socket >/dev/null 2>&1 || true
    die "TCP 端口 $listen_port 已被其他程序占用"
  fi

  cat >"$RELAY_SOCKET" <<EOF
[Unit]
Description=Mieru TCP forward listener

[Socket]
ListenStream=0.0.0.0:$listen_port
NoDelay=true

[Install]
WantedBy=sockets.target
EOF
  cat >"$RELAY_SERVICE" <<EOF
[Unit]
Description=Mieru TCP forward to IX
Wants=network-online.target
After=network-online.target mieru-forward.socket
Requires=mieru-forward.socket

[Service]
Type=notify
ExecStart=$proxyd $ix_ip:$ix_port
PrivateTmp=yes
NoNewPrivileges=yes
EOF

  systemctl daemon-reload
  systemctl enable --now mieru-forward.socket
  systemctl is-active --quiet mieru-forward.socket || die "TCP 中转监听启动失败"
  cat <<EOF

中转配置完成：
  0.0.0.0:$listen_port -> $ix_ip:$ix_port (TCP)

客户端节点地址填前置机公网 IP，端口填 $listen_port。
请放行前置机安全组/防火墙 TCP $listen_port。
EOF
}

uninstall_all() {
  local confirm

  [[ $# -eq 0 ]] || die "uninstall 不接受其他参数"
  ensure_root uninstall
  [[ "$(uname -s)" == "Linux" ]] || die "仅支持 Linux 服务器"
  read -r -p "将删除 mita、服务端配置和本脚本创建的中转，不可恢复。继续？[y/N]：" confirm
  [[ "$confirm" =~ ^[yY]$ ]] || { printf '已取消。\n'; return; }

  if command -v systemctl >/dev/null; then
    systemctl disable --now mieru-forward.socket >/dev/null 2>&1 || true
    systemctl stop mieru-forward.service mita.service >/dev/null 2>&1 || true
  fi
  rm -f -- "$RELAY_SOCKET" "$RELAY_SERVICE"

  if command -v dpkg-query >/dev/null && \
    dpkg-query -W -f='${Status}' mita 2>/dev/null | grep -q 'install ok installed'; then
    dpkg -P mita
  elif command -v rpm >/dev/null && rpm -q mita >/dev/null 2>&1; then
    rpm -e mita
  fi

  rm -rf -- /etc/mita /var/lib/mita /var/run/mita
  rm -f -- /var/run/mita.sock
  userdel mita >/dev/null 2>&1 || true
  groupdel mita >/dev/null 2>&1 || true
  if command -v systemctl >/dev/null; then
    systemctl daemon-reload
    systemctl reset-failed >/dev/null 2>&1 || true
  fi
  printf '已卸载 mita 并删除服务端配置和中转单元。\n'
}

menu() {
  local choice

  cat <<'EOF'

=========== Mieru 一键管理 ===========
1. 安装 mita 落地服务端
2. 配置前置 TCP 中转到 IX
3. 卸载 mita 和中转
0. 退出
======================================
EOF
  read -r -p "请选择 [0-3]：" choice
  case "$choice" in
    1) install_server ;;
    2) configure_relay ;;
    3) uninstall_all ;;
    0) printf '已退出。\n' ;;
    *) die "无效选项：$choice" ;;
  esac
}

main() {
  local action="${1:-}"

  case "$action" in
    "") menu ;;
    install) shift; install_server "$@" ;;
    relay|forward) shift; configure_relay "$@" ;;
    uninstall) shift; uninstall_all "$@" ;;
    -h|--help) [[ $# -eq 1 ]] || die "--help 不接受其他参数"; usage ;;
    *) usage >&2; die "未知操作：$action" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
