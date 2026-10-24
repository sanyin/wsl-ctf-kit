# Ubuntu 操作手册（Pwn / 脚本 / 靶场容器为主）

> 适用对象：本机已有的 Ubuntu 22.04（`baishui`），以及用 `install.ps1 -Distro ubuntu` 装出来的
> `Ubuntu-CTF`（用户 `ctf`）。命令里的用户名按实际替换。

**分工建议**：Ubuntu 做 **Pwn / 逆向脚本 / Docker 靶场 / 日常开发**；Web 与渗透用 Kali。
两套环境都在同一个 WSL2 内核上，文件互通，`wsl -d <名字>` 随时切换。

---

## 1. 进入环境

| 方式 | 操作 |
|---|---|
| Windows Terminal | 标签下拉 → `Ubuntu`（或 `Ubuntu-CTF`） |
| 任意终端 | `wsl -d Ubuntu` / `wsl -d Ubuntu-CTF` |
| 桌面快捷方式 | `Open-Ubuntu.cmd`（本机）/ `Open-Ubuntu-CTF`（kit 生成） |

进入后是 zsh + starship 提示符（目录、git 分支、Python 版本）。第一次用先 `passwd` 改密码。

---

## 2. 环境里有什么

| 类别 | 内容 |
|---|---|
| Shell | zsh + oh-my-zsh + autosuggestions + syntax-highlighting + starship |
| 基础 CLI | `git` `curl` `wget` `jq` `rg` `tmux` `tree` `bat(batcat)` `fd(fdfind)` |
| Pwn | `gdb` + **pwndbg**、`gdb-multiarch`、`pwninit`、`checksec`、`patchelf`、`ropper`、`qemu-x86_64` |
| Python | 3.10 + `pwntools`(4.15) `capstone` `keystone` `unicorn` `pyelftools` `pycryptodome` `gmpy2` `z3` `sympy` `angr` + 数据分析/绘图库 |
| 逆向/取证 | `binwalk` `foremost` `exiftool` `steghide` `pngcheck` `zbarimg` `upx` `nasm` |
| Web/网络 | `nmap` `sqlmap` `nikto` `ffuf` `tcpdump` `tshark` `socat` `nc` |
| 口令 | `john` `hashcat` `hydra` |
| 容器 | Docker 29.x（免 sudo 可用）+ compose |
| GUI | WSLg 可用（`ghidra`/`wireshark` 之类能直接弹窗） |

---

## 3. Pwn 标准流程

```bash
mkdir -p ~/lab/ctf/2026-xx/pwn1 && cd $_

# 1) 看保护
checksec --file=./chall
# 或者
python3 -c "from pwn import *; print(ELF('./chall').checksec())"

# 2) 配 libc/ld（给了 libc.so.6 的时候）
pwninit            # 生成 chall_patched、libc.so.6、ld-linux 的本地运行环境

# 3) 起模板
newpwn 127.0.0.1 1337 ./chall      # 生成 chall.py（pwntools 骨架）

# 4) 调试
gdb -q ./chall                      # pwndbg 自动加载（loaded ... pwndbg commands）
# 常用：b main / r / vmmap / stack / heap / telescope $rsp 20 / cyclic 200 / find 0x6161...

# 5) 打远端
python3 chall.py REMOTE HOST=... PORT=...
```

常用小工具：

```bash
one_gadget /lib/x86_64-linux-gnu/libc.so.6   # 若无此命令：gem install one_gadget（可选）
ropper --file ./chall --search "pop rdi"
ROPgadget --binary ./chall --only "pop|ret"
qemu-x86_64 -L /usr/arm-linux-gnueabihf ./chall   # 跑别的架构
patchelf --set-interpreter ./ld-linux --set-rpath . ./chall
```

---

## 4. Python 环境

系统 Python 直接可用（pwntools 等都在里面），但**不要 `pip install` 到系统**（PEP 668）：

```bash
# 临时项目
python3 -m venv .venv && source .venv/bin/activate

# 长期命令行工具
pipx install <包名>

# 已预装 uv（更快）
uv venv && source .venv/bin/activate
uv pip install pwntools
```

---

## 5. Docker（跑靶场/一次性容器）

```bash
docker ps
docker run --rm -it -v "$PWD":/w -w /w ubuntu:24.04 bash
docker run --rm -it --net=host kalilinux/kali-rolling   # 临时借 Kali 的工具
docker compose up -d                                     # 有 compose 文件的靶场
```

权限报错时（刚加进 docker 组）：`wsl --shutdown` 后重进。

---

## 6. 预置别名与函数

| 名字 | 作用 |
|---|---|
| `ll` `la` `l` `..` `...` | 列目录/跳目录 |
| `checksec --file=./chall` | 保护检查（已封装成别名） |
| `newpwn [host] [port] [bin]` | 生成 pwntools exploit 模板 |
| `pg` | `gdb -q -ex 'set pagination off' -ex run --args ...` |
| `pwninit` | 自动配 libc/ld |
| `extract <文件>` | 递归解压 zip/tar/7z/rar/zst |
| `f` / `ss` | file 一把梭 / 提取可见字符串 |
| `serve 8000` | 起 HTTP，Windows 侧 `http://localhost:8000` |
| `listen 4444` | `nc -lvnp 4444` |
| `tun <host> [port]` | 起 SOCKS5 隧道（`-D 1080`） |
| `d` `dc` `dps` `dshell` | docker 快捷方式 |
| `winpath` / `winhome` | 路径转换 / 跳到 Windows 用户目录 |
| `aslr0` / `aslr2` | 关/开 ASLR |
| `venv` | 当前目录建 `.venv` 并激活 |

---

## 7. 与 Windows / Kali 互通

- 文件：`/mnt/c/...`、`/mnt/d/...`；`winpath` 转成 Windows 路径。
- 端口：Windows 侧访问 `localhost:<port>`；反向访问 Windows 服务用宿主网关 IP（`ip route | grep default`）。
- Kali 的东西在 `/mnt/d/WSL/Kali` 里看不到（那是虚拟磁盘），但**网络互通**：把 Kali 当独立主机用 `wsl -d Kali`。
- 剪贴板：Windows Terminal 里 Ctrl+Shift+V / Ctrl+Shift+C。

---

## 8. 排障

| 现象 | 处理 |
|---|---|
| 打开终端出现 `unknown option: --zsh` | 已在 2026-10 修复（`.zshrc` 里 fzf 绑定改成「支持 `fzf --zsh` 就用，否则退回发行版自带 key-bindings」）；若重现见 [docs/faq.md](faq.md) 的 fzf 一节 |
| `starship` 刷 `Scanning current directory timed out` | 已用 `STARSHIP_LOG=error` 静音 |
| `WSL 检测到 localhost 代理配置` | Clash 开系统代理时的固定提示，无害；要用代理见下 |
| 想用 Windows 上的代理 | Clash 开「允许局域网连接」，然后 `export http_proxy=http://$(ip route | awk '{print $3}'):7897` |
| `docker` 权限拒绝 | 退出重进 WSL（`wsl --shutdown`）让 docker 组生效 |
| apt 卡住（网络正常、无输出） | 清锁：`sudo rm -f /var/lib/apt/lists/lock /var/lib/dpkg/lock*; sudo dpkg --configure -a` |
| `radare2`/`rizin` 没有 | Ubuntu 仓库已移除，逆向用 Kali 里的 `r2`/`ghidra`，或用 `pwndbg` + `objdump` |
| `PWNDBG` 没加载 | `gdb -batch -ex "pi import pwndbg"` 看报错；重跑 `wsl-setup/30-pwndbg.sh`（本机）或 kit 的 `provision/pwndbg.sh` |

---

## 9. 维护

```bash
sudo apt update && sudo apt upgrade -y
pipx upgrade-all
docker system prune -f          # 清无用镜像/容器（谨慎）
df -h /                          # 看空间
```

**备份/迁移**

```powershell
wsl --export Ubuntu D:\WSL\backup\ubuntu-$(Get-Date -f yyyyMMdd).tar
wsl --import Ubuntu D:\WSL\Ubuntu D:\WSL\backup\ubuntu-xxx.tar --version 2
```
