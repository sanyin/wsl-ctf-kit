#!/usr/bin/env bash
# provision/setup.sh — 在 WSL 发行版内部装配 CTF 环境（Kali / Ubuntu 通用）
#
# 由 install.ps1 以 root 调用：
#   wsl -d <distro> -u root -- env CTF_USER=ctf CTF_PASS=ctf CTF_FLAVOR=kali \
#       CTF_WITH_DESKTOP=0 CTF_LOG=/mnt/c/WSL/logs/provision.log bash /mnt/c/.../setup.sh
#
# 幂等：可以反复跑，已完成的步骤会跳过。
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SELF_DIR/lib.sh"
start_logging

[ "$(id -u)" -eq 0 ] || { err "必须以 root 运行"; exit 1; }

# ---------------------------------------------------------------- 发行版识别
detect_flavor() {
  if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}${ID_LIKE:-}" in
      *kali*) CTF_FLAVOR=kali ;;
      *ubuntu*|*debian*) CTF_FLAVOR=ubuntu ;;
    esac
    PRETTY="${PRETTY_NAME:-$CTF_FLAVOR}"
  else
    PRETTY="unknown"
  fi
  log "发行版: $PRETTY  (flavor=$CTF_FLAVOR)"
}

# ---------------------------------------------------------------- 1. 换源
setup_mirrors() {
  step "配置软件源（自动测速）"

  # 没有 curl 就没法测速。此时不要依赖发行版默认源（可能只解析到 IPv6 而挂住），
  # 直接切到已知可用的镜像，装上 curl 再继续。
  if ! have curl; then
    warn "缺少 curl，先切到清华源把它装上（后面测速要用）"
    if [ "$CTF_FLAVOR" = "kali" ]; then
      set_kali_mirror https://mirrors.tuna.tsinghua.edu.cn/kali
    else
      set_ubuntu_mirror http://mirrors.tuna.tsinghua.edu.cn/ubuntu
    fi
    apt_update_guarded 300
    apt_get install curl ca-certificates >/dev/null 2>&1 || warn "curl 安装失败"
  fi

  local best=""
  if have curl; then
    if [ "$CTF_FLAVOR" = "kali" ]; then
      best=$(pick_mirror kali-rolling kali \
        https://mirrors.tuna.tsinghua.edu.cn/kali \
        https://mirrors.ustc.edu.cn/kali \
        https://mirrors.aliyun.com/kali \
        https://mirror.nju.edu.cn/kali \
        http://http.kali.org/kali)
      [ -n "$best" ] && set_kali_mirror "$best"
    else
      best=$(pick_mirror noble ubuntu \
        http://mirrors.tuna.tsinghua.edu.cn/ubuntu \
        http://mirrors.ustc.edu.cn/ubuntu \
        http://mirrors.aliyun.com/ubuntu \
        http://mirror.nju.edu.cn/ubuntu \
        http://archive.ubuntu.com/ubuntu)
      [ -n "$best" ] && set_ubuntu_mirror "$best"
    fi
  fi

  if [ -z "$best" ]; then
    warn "测速没结果，用固定兜底源（清华）"
    if [ "$CTF_FLAVOR" = "kali" ]; then
      set_kali_mirror https://mirrors.tuna.tsinghua.edu.cn/kali
    else
      set_ubuntu_mirror http://mirrors.tuna.tsinghua.edu.cn/ubuntu
    fi
  fi

  apt_update_guarded 420
}

# ---------------------------------------------------------------- 2. 基础包
BASE_PKGS=(
  zsh zsh-autosuggestions zsh-syntax-highlighting git curl wget ca-certificates
  gnupg build-essential pkg-config python3 python3-pip python3-venv pipx
  tmux htop tree jq unzip zip p7zip-full xz-utils zstd file less vim nano
  man-db locales tzdata net-tools dnsutils iputils-ping traceroute whois
  openssh-client rsync strace ltrace gdb socat
  netcat-openbsd netcat-traditional
  ripgrep fd-find bat fzf zoxide
)

install_base() {
  step "基础工具"
  install_pkgs "${BASE_PKGS[@]}"
  # 时区/本地化：跟随 Windows，避免日志时间错乱
  ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null || true
  [ -f /etc/timezone ] && echo "Asia/Shanghai" > /etc/timezone 2>/dev/null || true
  if have locale-gen; then
    sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen 2>/dev/null || true
    sed -i 's/^# *\(zh_CN.UTF-8\)/\1/' /etc/locale.gen 2>/dev/null || true
    locale-gen >/dev/null 2>&1 || true
  fi
}

# ---------------------------------------------------------------- 3. 用户
setup_user() {
  step "创建用户 $CTF_USER"
  ensure_user "$CTF_USER" "$CTF_PASS" /bin/bash
  # sudo 无需密码？不放开：保持最小权限，装配阶段本来是 root
  cat > "/etc/sudoers.d/90-$CTF_USER" <<EOF
$CTF_USER ALL=(ALL:ALL) ALL
EOF
  chmod 440 "/etc/sudoers.d/90-$CTF_USER"
  ok "$CTF_USER 已加入 sudo 组（密码 $CTF_PASS）"
}

# ---------------------------------------------------------------- 4. CTF 工具链
CTF_COMMON=(
  nmap masscan tcpdump tshark wireshark-common
  sqlmap hydra john hashcat
  binwalk foremost sleuthkit exiftool steghide pngcheck zbar-tools
  ffmpeg imagemagick
  gdb-multiarch qemu-user qemu-user-static patchelf
  gobuster ffuf nikto dirb wordlists
)

install_ctf_tools() {
  step "CTF 工具链"
  if [ "$CTF_FLAVOR" = "kali" ]; then
    log "Kali：安装官方 headless 套装 + 分场景家族（体积较大）"
    install_pkgs kali-linux-headless \
      kali-tools-information-gathering kali-tools-vulnerability kali-tools-web \
      kali-tools-exploitation kali-tools-passwords kali-tools-post-exploitation \
      kali-tools-sniffing-spoofing kali-tools-database kali-tools-forensics \
      kali-tools-reverse-engineering kali-tools-crypto-stego kali-tools-reporting \
      kali-tools-top10 seclists metasploit-framework
    install_pkgs "${CTF_COMMON[@]}"
    install_pkgs radare2 rizin ghidra jadx apktool upx-ucl yasm nasm dwarfdump \
                 responder crackmapexec netexec impacket-scripts python3-impacket \
                 proxychains4 chisel \
                 python3-pwntools checksec
  else
    log "Ubuntu：安装等价工具（metasploit 只在 Kali 里提供）"
    install_pkgs "${CTF_COMMON[@]}"
    install_pkgs python3-pwntools patchelf radare2 upx-ucl nasm yasm \
                 proxychains4 seclists 2>/dev/null || true
    pkg_exists seclists || warn "Ubuntu 仓库没有 seclists，可用 Kali 里的 /usr/share/seclists"
  fi
}

# ---------------------------------------------------------------- 5. Python 环境
setup_python() {
  step "Python 环境（venv，避开 PEP668 限制）"
  local home="/home/$CTF_USER" venv=""
  local py="python3"
  # 优先 3.12/3.13：pwntools、ropper 等在新版本上常缺轮子
  for cand in python3.13 python3.12 python3; do
    if have "$cand"; then py="$cand"; break; fi
  done
  log "使用 $py ($($py -V 2>&1))"

  # 对应版本的 venv 支持包
  case "$py" in
    python3.13) install_pkgs python3.13-venv >/dev/null 2>&1 || true ;;
    python3.12) install_pkgs python3.12-venv >/dev/null 2>&1 || true ;;
  esac

  venv="$home/lab/venv"
  if [ ! -x "$venv/bin/pip" ]; then
    rm -rf "$venv"
    sudo -u "$CTF_USER" "$py" -m venv "$venv" || { warn "venv 创建失败，跳过"; return 0; }
  fi

  local idx="--index-url https://pypi.tuna.tsinghua.edu.cn/simple"
  "$venv/bin/pip" install -q $idx --upgrade pip >/dev/null 2>&1 || true
  local pkg
  for pkg in pwntools pycryptodome z3-solver requests pyelftools capstone impacket; do
    "$venv/bin/pip" install -q $idx "$pkg" >/dev/null 2>&1 || warn "venv: $pkg 安装失败"
  done
  "$venv/bin/pip" install -q $idx ropper >/dev/null 2>&1 || warn "venv: ropper 跳过（fileless 依赖无轮子）"
  if "$venv/bin/python" -c 'import pwn, Crypto, z3' 2>/dev/null; then
    ok "~/lab/venv 就绪（source ~/lab/venv/bin/activate）"
  else
    warn "venv 核心库导入异常"
  fi
}

# ---------------------------------------------------------------- 6. pwndbg
setup_pwndbg() {
  step "pwndbg（gdb 增强）"
  if bash "$SELF_DIR/pwndbg.sh"; then ok "pwndbg 完成"; else warn "pwndbg 未装好，可用裸 gdb"; fi
}

# ---------------------------------------------------------------- 7. 桌面（Kali）
setup_desktop() {
  [ "$CTF_FLAVOR" = "kali" ] || return 0
  [ "$CTF_WITH_DESKTOP" = "1" ] || { log "跳过图形桌面（加 -WithDesktop 可安装 Win-KeX）"; return 0; }
  step "Win-KeX 图形桌面（XFCE）"
  install_pkgs kali-desktop-xfce kali-win-kex dbus-x11 xfce4-terminal fonts-wqy-microhei
  ok "桌面已装：kex（独立窗口）/ kex --sl（seamless）"
}

# ---------------------------------------------------------------- 8. Docker（可选）
setup_docker() {
  [ "$CTF_WITH_DOCKER" = "1" ] || return 0
  step "Docker（可选）"
  install_pkgs docker.io
  usermod -aG docker "$CTF_USER" 2>/dev/null || true
  ok "Docker 已装，$CTF_USER 已加入 docker 组（重进终端生效）"
}

# ---------------------------------------------------------------- 9. shell
setup_shell() {
  step "shell 配置（zsh）"
  local home="/home/$CTF_USER"
  if [ -f "$SELF_DIR/zshrc.tpl" ]; then
    sed -e "s|@CTF_USER@|$CTF_USER|g" "$SELF_DIR/zshrc.tpl" > "$home/.zshrc"
    chown "$CTF_USER:$CTF_USER" "$home/.zshrc"
    ok "已写入 $home/.zshrc"
  fi
  if have zsh; then
    usermod -s /usr/bin/zsh "$CTF_USER" && ok "$CTF_USER 默认 shell → zsh"
  fi
  # 兜底 bash
  if ! grep -q 'wsl-ctf-kit' "$home/.bashrc" 2>/dev/null; then
    printf '\n# wsl-ctf-kit\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$home/.bashrc"
    chown "$CTF_USER:$CTF_USER" "$home/.bashrc"
  fi
}

# ---------------------------------------------------------------- 10. wsl.conf
write_wslconf() {
  step "写入 /etc/wsl.conf"
  local systemd=false
  [ -x /usr/lib/systemd/systemd ] && systemd=true
  cat > /etc/wsl.conf <<EOF
# 由 wsl-ctf-kit 生成
[boot]
systemd=$systemd

[user]
default=$CTF_USER

[interop]
enabled=true
appendWindowsPath=true

[time]
useWindowsTimezone=true
EOF
  ok "wsl.conf 已写入（systemd=$systemd，默认用户=$CTF_USER）"
  # 关掉 Kali 的 minimal 提示、企业级横幅
  touch /root/.hushlogin "/home/$CTF_USER/.hushlogin" 2>/dev/null || true
  chown "$CTF_USER:$CTF_USER" "/home/$CTF_USER/.hushlogin" 2>/dev/null || true
}

# ---------------------------------------------------------------- 11. 收尾
finish() {
  step "清理与小结"
  apt_get autoremove -y >/dev/null 2>&1 || true
  apt_get clean >/dev/null 2>&1 || true
  echo
  ok "装配完成：$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")"
  echo "  用户      : $CTF_USER / $CTF_PASS"
  echo "  家目录     : /home/$CTF_USER（lab/ 下放题目）"
  echo "  Python venv: ~/lab/venv"
  echo "  常用命令   : nmap / sqlmap / gdb / ghidra / msfconsole（Kali）"
  echo "  体检       : Windows 侧运行 doctor.ps1"
}

# ---------------------------------------------------------------- 主流程
detect_flavor
setup_mirrors
install_base
setup_user
install_ctf_tools
setup_python
setup_pwndbg
setup_desktop
setup_docker
setup_shell
write_wslconf
finish
