#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
script="$script_dir/mieru.sh"
source "$script"

bash -n "$script"
valid_port 1
valid_port 65535
! valid_port 0
! valid_port 65536
valid_high_port 1025
! valid_high_port 1024
valid_ipv4 192.0.2.1
! valid_ipv4 999.0.0.1
valid_credential 'user_01-test'
! valid_credential 'bad user'
answer_yes ''
answer_yes yes
! answer_yes no
! (answer_yes maybe) >/dev/null 2>&1
random_port="$(random_high_port)"
((random_port >= 20000 && random_port <= 60000))
seed="$(random_seed)"
((seed >= 1 && seed <= 2147483647))
[[ "$("$script" --help)" == *"打开交互菜单"* ]]
[[ "$(printf '0\n' | "$script")" == *"已退出"* ]]
! "$script" relay 40000 999.1.1.1 25000 >/dev/null 2>&1
printf 'mieru.sh: ok\n'
