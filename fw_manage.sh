#!/usr/bin/env bash
# fw_manage.sh — manage nftables dynamic whitelists
set -uo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

TABLE="inet myfilter"
ALL_SETS=(input_tcp_22 input_tcp_8080)

# Map chain/proto/port to a set name. Extend as you add sets.
get_set_name() {
  local chain="$1" proto="$2" port="$3"
  case "${chain}:${proto}:${port}" in
    INPUT:tcp:22)   echo "input_tcp_22" ;;   # bypass SSH rate limit
    INPUT:tcp:8080) echo "input_tcp_8080" ;; # direct HTTP backend access
    *) echo "" ;;
  esac
}

valid_ip() {
  local re='^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$'
  [[ $1 =~ $re ]] || return 1
  local ip=${1%%/*} o
  IFS=. read -ra octets <<< "$ip"
  for o in "${octets[@]}"; do (( o <= 255 )) || return 1; done
  if [[ $1 == */* ]]; then (( ${1##*/} <= 32 )) || return 1; fi
  return 0
}

# ---- Subcommand: list current sets ----
if [[ "${1:-}" == "list" ]]; then
  for s in "${ALL_SETS[@]}"; do
    echo "=== $s ==="
    nft list set $TABLE "$s" 2>/dev/null | grep -E 'elements|comment' || echo "(empty)"
  done
  exit 0
fi

# ---- Interactive add/remove loop ----
while true; do
  echo
  read -rp "Add or remove an IP? [a/r/q]: " action
  case "${action,,}" in
    a) op="add" ;;
    r) op="delete" ;;
    q|"") break ;;
    *) echo "Enter a, r, or q." ; continue ;;
  esac

  while true; do
    read -rp "1. Input or output? [i/o]: " dir
    case "${dir,,}" in
      i) chain=INPUT;  break ;;
      o) chain=OUTPUT; break ;;
      *) echo "Enter i or o." ;;
    esac
  done

  while true; do
    read -rp "2. TCP or UDP? [t/u]: " proto
    case "${proto,,}" in
      t) proto=tcp; break ;;
      u) proto=udp; break ;;
      *) echo "Enter t or u." ;;
    esac
  done

  while true; do
    read -rp "3. Port number? " port
    if [[ $port =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then break; fi
    echo "Enter a port 1–65535."
  done

  set_name=$(get_set_name "$chain" "$proto" "$port")
  if [[ -z $set_name ]]; then
    echo "No set defined for $chain $proto/$port."
    echo "Add a set block + rule to /etc/nftables.conf first."
    continue
  fi

  read -rp "4. IP/CIDR to $op: " ip
  if ! valid_ip "$ip"; then
    echo "'$ip' is not a valid IPv4 address/CIDR."
    continue
  fi

  if nft "$op" element $TABLE "$set_name" { "$ip" } 2>/dev/null; then
    echo "✅ $op '$ip' in @$set_name"
  else
    echo "⚠️  '$op' failed (entry may not exist for delete, or set is missing)."
  fi
done

echo
echo "Current sets:"
nft list sets $TABLE
