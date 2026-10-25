# wsl-ctf-kit

> **[English README](README.en.md)** · 中文

> Windows 上给 CTF 新手的一键环境：**WSL2 Kali + Ubuntu，装完就能打**。
> 双击一个 `install.ps1`，得到两个带完整工具链的 Linux 环境，不用碰虚拟机、不用配双系统。

```
Windows 11 / 10 (2004+)
   └── WSL2
        ├── Kali   —— web / pwn / 逆向 / 取证 / 内网，Metasploit、pwndbg、seclists 全在
        └── Ubuntu —— 通用开发 + pwn（gdb+pwndbg、pwntools、pwndbg 一键就绪）
```

镜像在安装时从官方/国内镜像站下载，**仓库里不放镜像**（所以只有几十 KB）。

---

## 为什么用这个而不是自己装

装 Kali 到 WSL 这件事，新手会连踩这几个坑，本仓库都已经修好了：

| 坑 | 现象 | 本项目怎么处理 |
|---|---|---|
| 微软商店/`wsl --install` 下载失败 | `0x80072f78` / 卡在 0% | 直接下官方 rootfs 并校验 SHA256 后 `wsl --import` |
| Kali 官方源慢 | `apt update` 几分钟不动 | 用真实索引吞吐测速，自动选清华/中科大/阿里云 |
| Kali 镜像钉在发布快照 | 装完版本很旧 | 自动把 `kali-last-snapshot` 切成 `kali-rolling` |
| `pwndbg` 已从 Kali 仓库移除 | `apt install pwndbg` 找不到 | 从镜像下源码 + 手工 venv + `uv.lock.hash` 修好自动更新检查 |
| GitHub 被墙 | 装 pwndbg / clone 词表失败 | 内置 `ghfast.top`、`gh-proxy.com` 降级链 |
| `pip install` 被 PEP668 拦 | `externally-managed-environment` | 一律用 `~/lab/venv`（挑兼容性最好的 Python 版本） |
| apt 被强杀后留锁 | 之后所有 apt 永久挂起 | 每次 apt 前自动清锁 |
| 源里的镜像只解析到 IPv6 | `Network is unreachable` | apt 强制 IPv4 |
| 新手手动改 `wsl.conf` 改坏 | 默认用户/systemd 不生效 | 脚本统一写入，并在安装后自动重启发行版让配置生效 |

另外：所有步骤**幂等**，坏了重跑就行；有 `doctor.ps1` 体检和 `uninstall.ps1` 干净卸载。

> 上面这些坑都是在本机真跑时踩出来并修掉的，每条都有记录 → [docs/tested.md](docs/tested.md)

---

## 快速开始

```powershell
# 1. 打开 PowerShell（不需要管理员）
git clone https://github.com/<你的账号>/wsl-ctf-kit.git
cd wsl-ctf-kit

# 2. 先看看环境是否就绪（不下载、不安装）
.\install.ps1 -DryRun

# 3. 正式安装（Kali + Ubuntu，默认用户 ctf / 密码 ctf）
.\install.ps1
```

装完会多出：

- 桌面快捷方式 `Open-Kali` / `Open-Ubuntu-CTF`
- Windows Terminal 里的 `Kali`、`Ubuntu-CTF` 两个 profile（tab 颜色区分）
- `C:\WSL\Kali`、`C:\WSL\Ubuntu-CTF`（虚拟磁盘位置）

> 首次安装耗时：Kali 镜像 236MB + 工具链约 3.5–4GB（20–45 分钟）；Ubuntu 镜像 30MB + 工具链约 1GB（10–20 分钟）。
> 中途断网/关窗口不用怕，重跑 `install.ps1` 会复用已下载的镜像并跳过已完成步骤。

> 为了不把新手硬盘塞满，Kali 只装 CTF/渗透真正用得到的家族：
> **不含** `kali-tools-802-11`（无线攻击要真实无线网卡 + 监听模式，WSL 里没有）、
> 蓝牙 / SDR / RFID / 硬件 / VoIP 同理。要的话自己 `apt install kali-tools-802-11`。

---

## 常用参数

```powershell
.\install.ps1 -Distro kali            # 只装 Kali
.\install.ps1 -Distro ubuntu          # 只装 Ubuntu
.\install.ps1 -WithDesktop            # Kali 额外装 Win-KeX 图形桌面
.\install.ps1 -Location D:\WSL        # 装到别的盘（默认 C:\WSL）
.\install.ps1 -UserName alice -Password 'MyPass123'   # 自定义账号
.\install.ps1 -Force                  # 已装过则重装（会先注销）
.\install.ps1 -SkipProvision          # 只导入系统，不装工具（调试用）
```

| 参数 | 默认 | 说明 |
|---|---|---|
| `-Distro` | `both` | `both` / `kali` / `ubuntu` |
| `-Location` | `C:\WSL` | 发行版存放目录 |
| `-UserName` | `ctf` | Linux 用户名 |
| `-Password` | `ctf` | 用户密码（也是 sudo 密码） |
| `-WithDesktop` | 关 | Kali 装 `kali-desktop-xfce` + `kali-win-kex`（约 +1.5GB） |
| `-WithDocker` | 关 | 额外装 Docker |
| `-NoLauncher` | 关 | 不创建快捷方式和 Terminal profile |
| `-DryRun` | — | 只检查环境、解析下载地址 |

---

## 装了什么

### Kali（CTF 主战场）
- **基础套件**：`kali-linux-headless` + information-gathering / vulnerability / web / exploitation /
  passwords / post-exploitation / sniffing / forensics / reverse-engineering /
  crypto-stego / reporting / top10
- **点名的**：`metasploit-framework`、`seclists`(1.9G)、`sqlmap`、`ffuf`、`gobuster`、`nikto`、
  `nmap`、`masscan`、`hashcat`、`john`、`hydra`、`tshark`、`binwalk`、`foremost`、`sleuthkit`、
  `radare2`、`rizin`、`ghidra`、`jadx`、`apktool`、`responder`、`nxc`、`impacket`、`proxychains4`、`chisel`
- **Pwn**：`pwndbg`、`python3-pwntools`、`patchelf`、`checksec`、`qemu-user`
- **桌面**（`-WithDesktop`）：Win-KeX / XFCE。装完会多一个 **`Open-Kali-Desktop`** 快捷方式，
  双击直接全屏打开 Kali 桌面；也可以在终端里 `kex`（窗口）/ `kex --sl`（混合）/ `kex --stop`
- **不含**无线/蓝牙/SDR/RFID/硬件/VoIP 家族（WSL 里没有对应硬件，装了也是摆设）

### Ubuntu（通用 / pwn）
- zsh + 补全高亮、`fzf`、`zoxide`、`ripgrep`、`bat`、`tmux`、`git`、`build-essential`
- `nmap`、`sqlmap`、`hydra`、`john`、`hashcat`、`gobuster`、`ffuf`、`nikto`、`tcpdump`、`tshark`、
  `binwalk`、`foremost`、`sleuthkit`、`exiftool`、`steghide`、`radare2`、`patchelf`、`qemu-user`
- Pwn：`pwndbg` + `~/lab/venv`（pwntools / pycryptodome / z3 / capstone / impacket）
- 注：`metasploit` 只在 Kali 里提供（Ubuntu 仓库没有）

两套环境都预置了这些 alias/函数：`ctfnew`（建题目目录）、`revshell`（生成反向 shell）、
`newpwn`（pwntools 模板）、`extract`（递归解压）、`serve`、`proxy_on/proxy_off/proxy_test`、
`winpath`、`wdesk`。完整清单见 [docs/tools.md](docs/tools.md)。

---

## 装完之后

```bash
# 进去
wsl -d Kali

# 第一件事：改密码
passwd

# 建个题目目录
ctfnew web1        # 生成 web1/{files,src,out}

# pwn 三件套
checksec --file=./chall
newpwn 127.0.0.1 1337 ./chall
gdb -q ./chall     # pwndbg 自动接管

# 起服务给 Windows 侧访问
serve 8000         # 浏览器开 http://localhost:8000

# 图形桌面（装了 -WithDesktop 才有）
kex                # 独立窗口（在 Kali 终端里）
kex --sl           # 窗口直接混在 Windows 桌面上
kex --stop         # 关掉

# 或者直接双击桌面上的 Open-Kali-Desktop（全屏 Kali 桌面；F8 打开 viewer 菜单，Alt+F4 退出）
```

Windows 侧随时体检：

```powershell
.\doctor.ps1
```

卸载（会删虚拟磁盘，谨慎）：

```powershell
.\uninstall.ps1 -Distro Kali     # 交互确认
.\uninstall.ps1 -Distro all -Yes
```

---

## 文档

| 文档 | 内容 |
|---|---|
| [docs/manual-kali.md](docs/manual-kali.md) | **Kali 操作手册**（Web 为主）：信息收集 → 目录/参数爆破 → SQLi/XSS → nuclei 漏扫 → Burp/mitmproxy → 字典位置 → 代理 → 排障 |
| [docs/manual-ubuntu.md](docs/manual-ubuntu.md) | **Ubuntu 操作手册**：Pwn 标准流程、pwndbg 用法、Python/venv、Docker 靶场、别名速查、排障 |
| [docs/tools.md](docs/tools.md) | 工具全量清单（按用途分组）+ 预置别名/函数 |
| [docs/faq.md](docs/faq.md) | 常见问题：没装 WSL / 下载慢 / 磁盘 / 代理 / 桌面 / 卸载 |
| [docs/tested.md](docs/tested.md) | 实测记录：真实机器上的全流程结果 + 踩过并修掉的 12 个问题 |
| [README.en.md](README.en.md) | English README |

## 目录结构

```
wsl-ctf-kit/
├── install.ps1           # 入口：检查环境 → 下载镜像 → 导入 → 装配 → 生成启动器
├── doctor.ps1            # 体检
├── uninstall.ps1         # 卸载（含快捷方式 / Terminal profile 清理）
├── lib/
│   ├── Common.ps1        # 日志、WSL 探测、下载/校验、路径转换
│   └── Launcher.ps1      # .cmd 启动器 + Terminal profile + 桌面快捷方式
├── provision/
│   ├── setup.sh          # 发行版内部装配主流程（幂等）
│   ├── lib.sh            # 换源、apt 包装、建用户
│   ├── pwndbg.sh         # pwndbg 源码安装（含 uv.lock.hash 修复）
│   ├── doctor.sh         # 内部体检
│   └── zshrc.tpl         # zsh 配置模板
└── docs/
    ├── faq.md            # 常见问题
    └── tools.md          # 工具清单
```

---

## 已知限制

- **Kali 镜像没有国内镜像站**（官方只发布在 kali.download），236MB 可能要几分钟；支持断点续传。
- **`networkingMode=mirrored` 不一定可用**（取决于代理软件/网络过滤驱动）。本项目**不启用**它：
  启用失败时 WSL 会直接退化成无网络状态。想用代理请走 `proxy_on`（见 docs/faq.md）。
- **Ubuntu 没有 metasploit**（上游没打包），需要就用 Kali。
- **虚拟磁盘只会增长不会自动缩小**：删了大文件后想释放，需 `wsl --shutdown` 后压缩 vhdx。
- Kali 默认关闭图形桌面，需要 `-WithDesktop`。
- 只在 **Win11 与 Win10 2004+** 上验证过；更老的版本 WSL2 支持不完整。

---

## 免责声明

本项目安装的工具用于**授权范围内的安全测试、CTF 比赛与学习**。
Kali Linux 是 Offensive Security 的商标，Ubuntu 是 Canonical 的商标；
本项目只下载其官方发布的镜像，不重新分发任何发行版镜像。

## License

[MIT](LICENSE)
