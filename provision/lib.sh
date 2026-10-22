#!/usr/bin/env bash
# provision/lib.sh — 装配脚本公共函数（被 setup.sh / pwndbg.sh source）
#
# 这里固化了本机实测过的几个坑：
#   1) 被 SIGKILL 的 apt 会留下锁，之后所有 apt 永久挂起（网络正常、CPU 空闲、无输出）
#   2) 部分国内镜像只解析到 IPv6，NAT 下不可达 → apt 加 ForceIPv4
#   3) 选镜像要看真实索引吞吐（Packages.gz），不能只看 Release 的延迟
#   4) .cmd/.sh 从 Windows 侧拷贝过来可能带 CRLF/BOM

CTF_USER="${CTF_USER:-ctf}"
CTF_PASS="${CTF_PASS:-ctf}"
CTF_FLAVOR="${CTF_FLAVOR:-ubuntu}"
CTF_WITH_DESKTOP="${CTF_WITH_DESKTOP:-0}"
CTF_WITH_DOCKER="${CTF_WITH_DOCKER:-0}"
CTF_LOG="${CTF_LOG:-/tmp/ctf-provision.log}"

if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_GRAY=$'\033[90m'
else
  C_RESET=''; C_CYAN=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_GRAY=''
fi

log()  { printf '%s[%s]%s %s\n' "$C_CYAN" "$(date +%H:%M:%S)" "$C_RESET" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf '%s[FAIL]%s %s\n' "$C_RED" "$C_RESET" "$*"; }
step() { printf '\n%s== %s ==%s\n' "$C_CYAN" "$*" "$C_RESET"; }

start_logging() {
  local dir
  dir="$(dirname "$CTF_LOG")"
  mkdir -p "$dir" 2>/dev/null || true
  : > "$CTF_LOG" 2>/dev/null || true
  exec > >(tee -a "$CTF_LOG") 2>&1
  log "日志: $CTF_LOG"
}

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export APT_LISTCHANGES_FRONTEND=none

have() { command -v "$1" >/dev/null 2>&1; }
pkg_exists() { apt-cache show "$1" >/dev/null 2>&1; }

apt_unlock() {
  rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock \
        /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend 2>/dev/null || true
  dpkg --configure -a >/dev/null 2>&1 || true
}

apt_get() {
  apt_unlock
  apt-get -y -q \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    -o Acquire::Retries=5 \
    -o Acquire::ForceIPv4=true \
    -o Acquire::http::Timeout=30 \
    -o Acquire::https::Timeout=30 \
    -o Dpkg::Progress-Fancy=0 \
    "$@"
}

install_pkgs() {
  local want=() p
  for p in "$@"; do
    if pkg_exists "$p"; then want+=("$p"); else warn "仓库里没有 $p，跳过"; fi
  done
  [ ${#want[@]} -eq 0 ] && return 0
  log "安装 ${#want[@]} 个包: ${want[*]}"
  apt_get install "${want[@]}" || { warn "部分包安装失败，继续"; return 1; }
}

# apt update 必须有硬超时：apt 对 SIGTERM 免疫，只能用 SIGKILL，
# 而且默认源可能只解析到 IPv6，在 NAT 下会一直挂着。
apt_update_guarded() {
  apt_unlock
  timeout -s KILL "${1:-420}" apt-get update -q \
    -o Acquire::Retries=3 \
    -o Acquire::ForceIPv4=true \
    -o Acquire::http::Timeout=20 \
    -o Acquire::https::Timeout=20 \
    -o Dpkg::Progress-Fancy=0 || warn "apt update 超时或失败，继续"
}

# 用真实索引文件测吞吐，选出最快的镜像（结果写到 stdout，其它信息走 stderr）
pick_mirror() {
  local suite="$1" base_path="$2"; shift 2
  local best="" best_speed=0 m
  for m in "$@"; do
    local res code speed
    res=$(curl -s -o /dev/null -m 8 -w "%{http_code} %{speed_download}" "$m/$base_path/dists/$suite/main/binary-amd64/Packages.gz" 2>/dev/null || echo "000 0")
    code=${res%% *}; speed=${res##* }; speed=${speed%.*}
    if [ "$code" = "200" ] || [ "$code" = "206" ]; then
      printf '  %-46s %s MB/s\n' "$m" "$(awk -v s="$speed" 'BEGIN{printf "%.2f", s/1048576}')" >&2
      if [ "${speed:-0}" -gt "$best_speed" ]; then best="$m"; best_speed=${speed:-0}; fi
    else
      printf '  %-46s HTTP %s（跳过）\n' "$m" "$code" >&2
    fi
  done
  printf '%s\n' "$best"
}

set_ubuntu_mirror() {
  local m="$1" comps="main restricted universe multiverse"
  local f
  # 只改 URIs：ubuntu.sources 里可能有多个 stanza（noble / noble-security 各一段），
  # 如果把 Suites/Components 统一改写，会出现「configured multiple times」的重复源告警。
  for f in /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/*.sources; do
    [ -f "$f" ] || continue
    sed -i -E "s|^URIs:.*|URIs: ${m}/|" "$f"
    ok "已设置 deb822 源: $f → $m"
    return 0
  done

  [ -f /etc/apt/sources.list ] && cp -a /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null
  {
    echo "# 由 wsl-ctf-kit 生成"
    for s in noble noble-updates noble-backports noble-security; do
      echo "deb ${m}/ $s ${comps}"
    done
  } > /etc/apt/sources.list
  ok "已设置 sources.list → $m"
}

set_kali_mirror() {
  local m="$1" f
  f=$(ls /etc/apt/sources.list.d/*.sources 2>/dev/null | head -n1 || true)
  if [ -n "$f" ]; then
    sed -i -E "s|^URIs:.*|URIs: ${m}/|" "$f"
    if grep -qi '^Suites:.*kali-last-snapshot' "$f"; then
      sed -i -E 's|^Suites:.*kali-last-snapshot.*|Suites: kali-rolling|' "$f"
      ok "套件从 kali-last-snapshot 切到 kali-rolling"
    fi
    ok "已设置 Kali 源 → $m"
    return 0
  fi
  [ -f /etc/apt/sources.list ] && cp -a /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null
  echo "deb ${m}/ kali-rolling main contrib non-free non-free-firmware" > /etc/apt/sources.list
  ok "已设置 Kali sources.list → $m"
}

ensure_group() { getent group "$1" >/dev/null 2>&1 || groupadd "$1"; }

# 以某个用户身份执行命令。
# 注意：ubuntu-base 这种最小镜像里可能没有 sudo，所以优先用 runuser(util-linux)，
# 再退 sudo，最后用 su -c。
as_user() {
  local u="$1"; shift
  if have runuser; then
    runuser -u "$u" -- "$@"
  elif have sudo; then
    sudo -u "$u" -- "$@"
  else
    local q=""
    local arg
    for arg in "$@"; do q+="$(printf '%q' "$arg") "; done
    su -s /bin/sh "$u" -c "$q"
  fi
}

ensure_user() {
  local u="$1" pw="$2" shell="${3:-/bin/bash}"
  ensure_group sudo
  if id "$u" >/dev/null 2>&1; then
    ok "用户 $u 已存在"
  else
    useradd -m -s "$shell" -G sudo "$u" || warn "useradd 失败"
    ok "已创建用户 $u"
  fi
  echo "$u:$pw" | chpasswd
  install -d -o "$u" -g "$u" -m 755 "/home/$u"/{lab,lab/ctf,lab/tools,.local/bin} 2>/dev/null || true
}

enable_systemd() {
  if [ -x /usr/lib/systemd/systemd ] || pkg_exists systemd; then
    install_pkgs systemd systemd-sysv >/dev/null 2>&1 || true
  fi
}
