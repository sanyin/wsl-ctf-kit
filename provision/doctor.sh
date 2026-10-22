#!/usr/bin/env bash
# provision/doctor.sh — 发行版内部体检（由 doctor.ps1 调用，也可手动跑）
# 用法： wsl -d Kali -u ctf -- bash /mnt/c/.../provision/doctor.sh
set -uo pipefail

PASS=0; WARN=0; FAIL=0
ok()   { PASS=$((PASS+1));  printf '\033[32m[ OK ]\033[0m %-22s %s\n' "$1" "${2-}"; }
warn() { WARN=$((WARN+1));  printf '\033[33m[WARN]\033[0m %-22s %s\n' "$1" "${2-}"; }
bad()  { FAIL=$((FAIL+1));  printf '\033[31m[FAIL]\033[0m %-22s %s\n' "$1" "${2-}"; }

USER_NAME="$(id -un)"
echo "=============== 环境体检 ==============="
. /etc/os-release 2>/dev/null || true
echo "系统   : ${PRETTY_NAME:-unknown}"
echo "内核   : $(uname -r)"
echo "用户   : $USER_NAME (uid=$(id -u))"
echo "shell  : $(getent passwd "$USER_NAME" | cut -d: -f7)"
echo "磁盘   : $(df -h / | awk 'NR==2 {print $4" 可用 / "$2}')"
echo "----------------------------------------"

# 系统
[ -f /etc/wsl.conf ] && ok "wsl.conf" || warn "wsl.conf" "缺失"
[ -d /run/systemd/system ] && ok "systemd" "PID1 运行中" || warn "systemd" "未启用（命令行不受影响）"
if grep -qh 'kali-rolling\|noble' /etc/apt/sources.list /etc/apt/sources.list.d/*.sources 2>/dev/null; then
  ok "apt 源" "$(grep -h '^URIs\|^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/*.sources 2>/dev/null | head -1 | cut -c1-56)"
else
  warn "apt 源" "未识别"
fi
[ "$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null)" = "0" ] && ok "ptrace_scope" "0（gdb attach 可用）" || warn "ptrace_scope" "非 0"

# 网络
if curl -s -o /dev/null -m 8 https://mirrors.tuna.tsinghua.edu.cn/ 2>/dev/null; then
  ok "外网/镜像" "可达"
else
  warn "外网/镜像" "不可达（检查网络/代理）"
fi

# 工具
check() { # 名称 命令
  if command -v "$2" >/dev/null 2>&1; then ok "$1" "$(command -v "$2")"; else warn "$1" "未找到 $2"; fi
}
check "zsh"       zsh
check "git"       git
check "python3"   python3
check "gdb"       gdb
check "nmap"      nmap
check "sqlmap"    sqlmap
check "ffuf"      ffuf
check "gobuster"  gobuster
check "binwalk"   binwalk
check "exiftool"  exiftool
check "hashcat"   hashcat
check "hydra"     hydra
check "r2"        r2
check "pwntools"  pwn

# 这些只有 Kali 有，Ubuntu 上不该报 WARN
IS_KALI=0
. /etc/os-release 2>/dev/null || true
case "${ID:-}${ID_LIKE:-}" in *kali*) IS_KALI=1 ;; esac
if [ "$IS_KALI" = "1" ]; then
  check "msfconsole" msfconsole
  check "kex"       kex
else
  echo "  [ -- ] msfconsole / kex      仅 Kali 提供，Ubuntu 跳过"
fi

# pwndbg：必须能真的 import
if timeout 90 gdb -batch -nx -ex "source /opt/pwndbg-src/gdbinit.py" \
     -ex "pi import pwndbg; print('PWNDBG_OK')" 2>/dev/null | grep -q PWNDBG_OK; then
  ok "pwndbg" "gdb 内加载正常"
elif [ -f /opt/pwndbg-src/gdbinit.py ]; then
  warn "pwndbg" "已安装但加载异常"
else
  warn "pwndbg" "未安装（重跑 setup.sh）"
fi

# Python venv
VENV="$HOME/lab/venv"
if [ -x "$VENV/bin/python" ]; then
  if "$VENV/bin/python" -c 'import pwn, Crypto, z3' 2>/dev/null; then
    ok "venv" "$VENV（pwntools/pycryptodome/z3 正常）"
  else
    warn "venv" "存在但依赖不全"
  fi
else
  warn "venv" "未创建"
fi

# 词表（Kali 有 seclists；Ubuntu 上游没有）
if [ "$IS_KALI" = "1" ]; then
  [ -d /usr/share/seclists ] && ok "seclists" "$(du -sh /usr/share/seclists 2>/dev/null | cut -f1)" || warn "seclists" "未安装"
  [ -d /usr/share/wordlists ] && ok "wordlists" "$(ls /usr/share/wordlists | tr '\n' ' ' | cut -c1-40)" || warn "wordlists" "未安装"
else
  echo "  [ -- ] seclists              Ubuntu 仓库无此包，用 Kali 里的 /usr/share/seclists"
fi

echo "----------------------------------------"
printf '通过 \033[32m%d\033[0m / 警告 \033[33m%d\033[0m / 失败 \033[31m%d\033[0m\n' "$PASS" "$WARN" "$FAIL"
[ "$FAIL" -eq 0 ] && echo "结论：可用 ✓" || echo "结论：见上"
exit 0
