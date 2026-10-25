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
      best=$(pick_mirror kali-rolling \
        https://mirrors.tuna.tsinghua.edu.cn/kali \
        https://mirrors.ustc.edu.cn/kali \
        https://mirrors.aliyun.com/kali \
        https://mirror.nju.edu.cn/kali \
        http://http.kali.org/kali)
      [ -n "$best" ] && set_kali_mirror "$best"
    else
      best=$(pick_mirror noble \
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
  sudo
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

# ---------------------------------------------------------------- 3.5 工作目录说明
# ~/lab 下预留 ctf/ tools/ 两个空目录，容易让人以为"装坏了"或"工具呢"，
# 所以各放一个 README 说明清楚。
setup_lab() {
  local H="/home/$CTF_USER/lab"
  install -d -o "$CTF_USER" -g "$CTF_USER" "$H/ctf" "$H/tools" 2>/dev/null || true

  if [ ! -f "$H/README.md" ]; then
    cat > "$H/README.md" <<'EOF'
# ~/lab —— 工作目录

| 目录 | 用途 |
|---|---|
| `ctf/` | 放题目。**默认是空目录，这是故意的**：用 `ctfnew <名字>` 生成 `<名字>/{files,src,out}` |
| `tools/` | 放你自己下载/编译的工具。**默认也是空的** |
| `venv/` | Python 虚拟环境：`source ~/lab/venv/bin/activate` |

工具本体不在这里：apt 装的在 `/usr/bin`，字典在 `/usr/share/seclists`，pwndbg 在 `/opt/pwndbg-src`。
EOF
  fi

  if [ ! -f "$H/ctf/README.md" ]; then
    cat > "$H/ctf/README.md" <<'EOF'
# ~/lab/ctf

放题目的地方（空目录是正常的）。

```bash
cd ~/lab/ctf && ctfnew web1     # 生成 web1/{files,src,out}
```
EOF
  fi

  if [ ! -f "$H/tools/README.md" ]; then
    cat > "$H/tools/README.md" <<'EOF'
# ~/lab/tools

放自己下载/编译的工具。

```bash
cd ~/lab/tools && git clone https://ghfast.top/https://github.com/<owner>/<repo>
ln -s ~/lab/tools/<repo>/<entry> ~/.local/bin/<name>   # ~/.local/bin 在 PATH 里
```
EOF
  fi

  chown -R "$CTF_USER:$CTF_USER" "$H" 2>/dev/null || true
  ok "~/lab 已就绪（ctf/ tools/ 目录里的 README 说明了用途）"
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
    log "Kali：官方 headless 套装 + 分场景家族（约 3.5-4GB 下载）"
    # 只挑 CTF/渗透真会用到的家族：
    #  - 不含 kali-tools-802-11（无线攻击需要真实无线网卡+监听模式，WSL 里没有）
    #  - 不含 kali-tools-bluetooth / sdr / rfid / hardware / voip（同理，需要硬件）
    #  - 不含 kali-tools-database（sqlmap 已在 web 家族里，单独的 DB 工具链少用又占地方）
    install_pkgs kali-linux-headless \
      kali-tools-information-gathering kali-tools-vulnerability kali-tools-web \
      kali-tools-exploitation kali-tools-passwords kali-tools-post-exploitation \
      kali-tools-sniffing-spoofing kali-tools-forensics \
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
    as_user "$CTF_USER" "$py" -m venv "$venv" || { warn "venv 创建失败，跳过"; return 0; }
    chown -R "$CTF_USER:$CTF_USER" "$home/lab" 2>/dev/null || true
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
  install_pkgs kali-desktop-xfce kali-win-kex dbus-x11 xfce4-terminal \
               fonts-wqy-microhei fonts-wqy-zenhei
  install_pkgs kali-win-kex >/dev/null 2>&1 || true

  # 1) Win-KeX 启动时要 sudo 把 WSLg 的只读 X11 socket 目录重挂为可写。
  #    只放开这一条，其它 sudo 仍然需要密码。
  #    注意 sudoers 里逗号是命令分隔符，参数里的逗号必须写成 \,
  local sudoers=/etc/sudoers.d/90-winkex
  cat > "$sudoers" <<EOF
# 由 wsl-ctf-kit 添加：Win-KeX 启动桌面时需要重挂 WSLg 的 X11 socket 目录
$CTF_USER ALL=(root) NOPASSWD: /usr/bin/mount -o remount\,rw /tmp/.X11-unix
EOF
  chmod 440 "$sudoers"
  if visudo -cf "$sudoers" >/dev/null 2>&1; then
    ok "已授权免密重挂 /tmp/.X11-unix（其余 sudo 仍需密码）"
  else
    rm -f "$sudoers"
    warn "sudoers 校验失败，已回滚（桌面可能需要手动输密码）"
  fi

  # 2) 预生成 VNC 密码文件，否则 kex 会交互式问密码，快捷方式就没法一键
  local vd="/home/$CTF_USER/.config/tigervnc"
  install -d -o "$CTF_USER" -g "$CTF_USER" -m 700 "$vd" 2>/dev/null || true
  if [ ! -f "$vd/passwd" ]; then
    head -c 18 /dev/urandom | base64 | tr -d '\n' | cut -c1-16 \
      | as_user "$CTF_USER" vncpasswd -f > "$vd/passwd" 2>/dev/null || true
    chown "$CTF_USER:$CTF_USER" "$vd/passwd" 2>/dev/null || true
    chmod 600 "$vd/passwd" 2>/dev/null || true
    [ -s "$vd/passwd" ] && ok "VNC 密码已预生成（免交互）" || warn "VNC 密码生成失败，首次 kex 会问密码"
  fi

  ok "桌面已装：kex（独立窗口）/ kex --sl（seamless）"
  ok "Windows 侧会有「打开 Kali 桌面」快捷方式（install.ps1 -WithDesktop 生成）"
}

# ---------------------------------------------------------------- 8. pwn 内核参数
setup_sysctl() {
  step "CTF/pwn 内核参数"
  cat > /etc/sysctl.d/99-ctf.conf <<'EOF'
# 由 wsl-ctf-kit 生成（仅本机分析环境使用，不要照搬到服务器）
kernel.yama.ptrace_scope = 0
vm.mmap_min_addr = 0
fs.suid_dumpable = 1
kernel.core_pattern = core.%e.%p
EOF
  sysctl --system >/dev/null 2>&1 || warn "sysctl 部分参数未生效（WSL 内核限制，不影响使用）"
  cat > /etc/security/limits.d/99-ctf.conf <<'EOF'
* soft core unlimited
* hard core unlimited
EOF
  ok "ptrace_scope=0 / mmap_min_addr=0 / core dump 已配置"
}

# ---------------------------------------------------------------- 9. Docker（可选）
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
# 早期标记：万一装配被中断（此时 wsl.conf 还没写），重跑 install.ps1 也能认出
# 这是本工具的发行版，不会傻乎乎再建一个 Kali-CTF2
touch /etc/wsl-ctf-kit
setup_policy_rcd      # 安装期间不启动服务（否则个别 postinst 会卡住）
setup_mirrors
install_base
setup_user
setup_lab
install_ctf_tools
setup_python
setup_pwndbg
setup_sysctl
setup_desktop
setup_docker
setup_shell
write_wslconf
finish
