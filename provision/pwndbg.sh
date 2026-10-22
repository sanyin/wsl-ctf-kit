#!/usr/bin/env bash
# provision/pwndbg.sh — 安装 pwndbg（Kali 仓库已移除；Ubuntu 也没有现成包）
#
# 为什么不用官方 setup.sh / uv sync：
#   * pwndbg 新版依赖 uv，且有一个 git 依赖 pt（gdb-pt-dump），国内直连 GitHub 常被墙
#   * 官方 setup.sh 是交互式的，无人值守容易卡住
# 这里的做法：镜像下源码 → 手工建 .venv → 按 pyproject 装依赖 → 单独 vendor pt
#            → 写 uv.lock.hash 跳过自动更新 → 验证通过后才写 .gdbinit
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SELF_DIR/lib.sh"

SRC=/opt/pwndbg-src
VENV="$SRC/.venv"
PT_SRC=/opt/gdb-pt-dump
PIP_INDEX="--index-url https://pypi.tuna.tsinghua.edu.cn/simple"
GH_MIRRORS=(
  "https://ghfast.top/https://github.com"
  "https://gh-proxy.com/https://github.com"
  "https://github.com"
)

[ "$(id -u)" -eq 0 ] || { err "必须以 root 运行"; exit 1; }
have gdb || { warn "没有 gdb，跳过 pwndbg"; exit 1; }

if command -v pwndbg >/dev/null 2>&1 && "$VENV/bin/python" -c 'import pwndbg' 2>/dev/null; then
  ok "pwndbg 已可用"
  exit 0
fi

dl() { # dl <github-path> <dest>
  local path="$1" dest="$2" m
  for m in "${GH_MIRRORS[@]}"; do
    if curl -fL --connect-timeout 10 --max-time 300 -o "$dest" "$m/$path"; then
      [ -s "$dest" ] && return 0
    fi
  done
  return 1
}

# ---------- 源码 ----------
if [ -f "$SRC/gdbinit.py" ]; then
  ok "pwndbg 源码已存在"
else
  log "下载 pwndbg 源码（GitHub 镜像）"
  if dl "pwndbg/pwndbg/archive/refs/heads/dev.tar.gz" /tmp/pwndbg.tar.gz \
     && tar -tzf /tmp/pwndbg.tar.gz >/dev/null 2>&1; then
    rm -rf /opt/pwndbg-dev "$SRC"
    tar xzf /tmp/pwndbg.tar.gz -C /opt && [ -d /opt/pwndbg-dev ] && mv /opt/pwndbg-dev "$SRC"
    ok "源码: $SRC"
  else
    err "pwndbg 源码下载失败"; exit 1
  fi
fi
[ -f "$SRC/gdbinit.py" ] || { err "缺少 gdbinit.py"; exit 1; }

# ---------- pt（git 依赖，单独 vendor） ----------
if [ ! -d "$PT_SRC" ]; then
  log "下载 gdb-pt-dump"
  if dl "martinradev/gdb-pt-dump/archive/refs/heads/master.tar.gz" /tmp/pt.tar.gz; then
    rm -rf /opt/gdb-pt-dump-master
    tar xzf /tmp/pt.tar.gz -C /opt && [ -d /opt/gdb-pt-dump-master ] && mv /opt/gdb-pt-dump-master "$PT_SRC"
  fi
fi

# ---------- venv（版本必须和 gdb 内嵌 Python 一致） ----------
GDB_PY_VER=$(gdb -batch -nx -ex 'python import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null | tail -n1)
PY="python3"
if [ -n "$GDB_PY_VER" ] && have "python$GDB_PY_VER"; then PY="python$GDB_PY_VER"; fi
log "gdb 内嵌 Python ${GDB_PY_VER:-未知}，用 $PY"

# 该版本的 venv 支持包
install_pkgs "python$GDB_PY_VER-venv" >/dev/null 2>&1 || true

if [ ! -x "$VENV/bin/python" ]; then
  "$PY" -m venv "$VENV" || { err "venv 创建失败（缺 python$GDB_PY_VER-venv？）"; exit 1; }
fi
"$VENV/bin/pip" install -q $PIP_INDEX --upgrade pip >/dev/null 2>&1 || true

DEPS=(
  "capstone6pwndbg==8.0.0"
  "unicorn>=2.1.4,<3"
  "pwntools>=4.14.1,<5"
  "sortedcontainers>=2.4.0,<3"
  "tabulate>=0.10.0,<0.11"
  "typing-extensions>=4.16.0,<5"
  "pycparser~=3.0"
  "pyelftools>=0.33,<1"
  "pygments>=2.19.2,<3"
  "psutil>=7.0.0,<8"
  "uv>=0.12.0"
  "ipython>=8.39.0,<10"
  "ropgadget==7.6"
  "requests>=2.34.2,<3"
  "rich>=15.0.0,<16"
)
log "安装 pwndbg 依赖（${#DEPS[@]} 个）"
"$VENV/bin/pip" install -q $PIP_INDEX "${DEPS[@]}" 2>&1 | tail -n 5 || warn "部分依赖安装失败"

if [ -d "$PT_SRC" ]; then
  "$VENV/bin/pip" install -q $PIP_INDEX --no-deps "$PT_SRC" >/dev/null 2>&1 \
    && ok "pt 已装入 venv" || warn "pt 安装失败"
fi

# 关键：不写这个哈希，pwndbg 每次启动都想 uv sync；非 root 无权写 /opt 会直接静默退出
if [ -f "$SRC/uv.lock" ]; then
  sha256sum "$SRC/uv.lock" | cut -d' ' -f1 > "$VENV/uv.lock.hash"
  chmod 644 "$VENV/uv.lock.hash"
fi

# ---------- 包装命令 ----------
cat > /usr/local/bin/pwndbg <<EOF
#!/bin/sh
exec gdb -q -ex "source $SRC/gdbinit.py" "\$@"
EOF
chmod 755 /usr/local/bin/pwndbg

# ---------- 验证 ----------
log "验证 gdb 内加载…"
VERIFY=$(timeout 120 gdb -batch -nx -ex "source $SRC/gdbinit.py" \
         -ex "pi import pwndbg; print('PWNDBG_LOADED_OK')" 2>&1 || true)
if ! printf '%s' "$VERIFY" | grep -q "PWNDBG_LOADED_OK"; then
  warn "pwndbg 加载验证未通过，不写 .gdbinit（普通 gdb 不受影响）"
  printf '%s\n' "$VERIFY" | tail -n 12
  exit 1
fi

# ---------- .gdbinit（必须用源码真实路径：软链会让 pwndbginit 找不到） ----------
for u in root "${CTF_USER:-ctf}"; do
  H=$(getent passwd "$u" | cut -d: -f6)
  [ -n "$H" ] || continue
  grep -q 'pwndbg-src/gdbinit.py' "$H/.gdbinit" 2>/dev/null && continue
  cat >> "$H/.gdbinit" <<GDBINIT
# 由 wsl-ctf-kit 添加：存在 pwndbg 就加载，不存在则静默跳过
python
import os as _os, sys as _sys
_p = "$SRC/gdbinit.py"
if _os.path.exists(_p):
    _d = _os.path.dirname(_p)
    if _d not in _sys.path:
        _sys.path.insert(0, _d)
    try:
        gdb.execute("source " + _p)
    except Exception as _e:
        print("[gdb] pwndbg 加载失败: %s" % _e)
end
GDBINIT
  chown "$u:$u" "$H/.gdbinit" 2>/dev/null || true
done

ok "pwndbg 已就绪：gdb 启动即加载（pwndbg: loaded ...）"
