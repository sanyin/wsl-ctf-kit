# 工具清单

装完后的工具，按用途分组。标 **K** 的只在 Kali 里（Ubuntu 上游没打包）。

## 探查 / 信息收集
| 工具 | 用途 |
|---|---|
| `nmap` | 端口/服务扫描，`nmap-up`、`nmap-full` 两个预设别名 |
| `masscan` **K** | 大网段高速扫描 |
| `netdiscover` **K** / `arp-scan` **K** | 二层发现 |
| `whois` `dig` `traceroute` | 域名与链路 |
| `searchsploit` **K** | 本地 exploit-db 检索（别名 `seek`） |

## Web
| 工具 | 用途 |
|---|---|
| `sqlmap` | SQL 注入 |
| `ffuf` / `gobuster` / `feroxbuster` **K** / `dirb` | 目录与参数爆破 |
| `nikto` | Web 服务快扫 |
| `whatweb` / `wpscan` **K** | 指纹、WordPress |
| `nuclei` **K** | 模板化漏洞扫描（`nuclei -update-templates` 更新模板） |
| `dalfox` **K** / `xsser` **K** | XSS 扫描 / 生成 payload |
| `arjun` **K** | 隐藏参数发现 |
| `dirsearch` **K** / `feroxbuster` **K** | 目录爆破 |
| `commix` **K** / `dotdotpwn` **K** / `wafw00f` **K** / `joomscan` **K** | 命令注入 / 目录穿越 / WAF 识别 / Joomla |
| `burpsuite` **K** / `zaproxy` **K** / `mitmproxy` **K** | 抓包改包（GUI） |

## 口令
| 工具 | 用途 |
|---|---|
| `hydra` / `medusa` **K** | 在线爆破 |
| `john` / `hashcat` | 离线破解 |
| `cewl` **K** | 从站点生成字典 |
| `seclists` **K** | 词表合集（`/usr/share/seclists`，约 1.9G） |
| `wordlists` | 发行版自带小词表（`/usr/share/wordlists`） |

## Pwn
| 工具 | 用途 |
|---|---|
| `pwndbg` | gdb 增强（`gdb` 启动自动加载） |
| `pwntools` | exploit 框架（系统包 + `~/lab/venv` 各一份） |
| `checksec` | 保护机制检查 |
| `patchelf` | 改 ELF 的 interpreter/rpath（换 libc 必备） |
| `qemu-user` / `qemu-user-static` | 跑其他架构的题目 |
| `gdb-multiarch` | 非 x86 调试 |
| `one_gadget` **K** | libc 一把梭（在 `kali-tools-reverse-engineering` 里） |

## 逆向
| 工具 | 用途 |
|---|---|
| `radare2` (`r2`) / `rizin` **K** | 命令行反汇编 |
| `ghidra` **K** | 反编译（GUI，Java） |
| `jadx` **K** / `apktool` **K** | Android 逆向 |
| `upx-ucl` / `nasm` / `yasm` | 脱壳、汇编 |
| `objdump` `readelf` `nm` `strings` `xxd` | 基础三件套（binutils） |

## 取证 / 杂项
| 工具 | 用途 |
|---|---|
| `binwalk` | 固件/嵌套压缩包 |
| `foremost` / `sleuthkit` **K** | 文件 carving / 磁盘镜像 |
| `exiftool` | 元数据 |
| `steghide` / `zsteg` **K** / `pngcheck` / `zbar-tools` | 图片隐写、二维码 |
| `ffmpeg` / `imagemagick` | 音视频、图片处理 |
| `foremost` **K** / `scalpel` **K** | 恢复已删文件 |

## 内网 / 后渗透（Kali）
| 工具 | 用途 |
|---|---|
| `metasploit-framework` (`msf`) | 漏洞利用框架 |
| `responder` | LLMNR/NBT-NS 投毒 |
| `netexec` (`nxc`) / `crackmapexec` | AD/横向 |
| `impacket-scripts` | 一堆 SMB/Kerberos 脚本 |
| `proxychains4` / `chisel` / `sshuttle` | 隧道与代理链 |
| `tcpdump` / `tshark` / `wireshark-common` | 流量分析 |

## 系统 / 开发
`git` `curl` `wget` `tmux` `htop` `jq` `tree` `less` `vim` `nano` `build-essential`
`python3` `pipx` `ripgrep`(`rg`) `fd-find`(`fdfind`) `bat`(`batcat`) `fzf` `zoxide` `zsh`

> 提示：Debian 系里 `bat` 装完叫 `batcat`、`fd` 叫 `fdfind`（和包名冲突），可以自己加
> `alias bat='batcat'` / `alias fd='fdfind'`。Kali 里就是 `bat` / `fd`。

---

## 预置别名 / 函数

| 名字 | 作用 |
|---|---|
| `ctfnew <名字>` | 建 `名字/{files,src,out}` 并进入 |
| `revshell <LHOST> [LPORT]` | 打印 bash/python/nc 反向 shell 一行命令 |
| `newpwn [host] [port] [bin]` | 生成 pwntools exploit 模板 |
| `checksec --file=./chall` | 保护检查 |
| `extract <文件>` | 递归解压 zip/tar/7z/rar/zst… |
| `serve 8000` | 起 HTTP 服务（Windows 侧 `http://localhost:8000`） |
| `listen 4444` | `rlwrap nc -lvnp 4444` |
| `nmap-up` / `nmap-full` | 快速 / 全端口扫描预设 |
| `seek <关键字>` | searchsploit |
| `msf` | `sudo msfconsole` |
| `nse <关键字>` | 搜 nmap 脚本 |
| `winpath` | 当前路径转 Windows 路径 |
| `winhome` / `wdesk` | 跳到 Windows 用户目录 / 桌面 |
| `proxy_on` / `proxy_off` / `proxy_test` | 开关/检测 Windows 侧代理 |
| `aslr0` / `aslr2` | 关/开 ASLR（pwn 调试用） |
| `venv` | 在当前目录建 `.venv` 并激活 |
