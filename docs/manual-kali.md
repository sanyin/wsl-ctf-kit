# Kali 操作手册（Web 方向为主）

> 适用对象：用本仓库 `install.ps1` 装出来的 Kali，以及本机另一套手工配置的 Kali。
> 用户名以 `baishui` 为例；**如果你是用 `install.ps1` 装的，用户是 `ctf`，把命令里的名字换掉即可。**

---

## 1. 进入环境

| 方式 | 操作 |
|---|---|
| Windows Terminal | 标签下拉 → `Kali`，或 `wt -p Kali` |
| 任意终端 | `wsl -d Kali` |
| 桌面快捷方式 | `Open-Kali`（install.ps1 生成） |
| 图形桌面 | 双击桌面 **`Open-Kali-Desktop`**（全屏）；或终端里 `kex` / `kex --sl` / `kex --stop` |

进入后默认在 `~`，shell 是 zsh。第一件事建议 `passwd` 改密码。

### 1.1 打开桌面（Win-KeX）

装了 `-WithDesktop` 之后，桌面上会有一个 **`Open-Kali-Desktop`** 快捷方式：

- **双击即可**：脚本先进 WSL 里执行 `kex --win --start` 起服务端，再由 Windows 侧拉起 viewer，全屏显示 XFCE 桌面
- 第一次打开可能要等 5–10 秒（WSL 冷启动 + X 服务起来）
- 退出：`Alt+F4` 关闭窗口；`F8` 是 TigerVNC 菜单（里面也有 Exit）
- 关掉窗口**不会**销毁会话，下次点快捷方式会重连
- 命令行等价：
  ```bash
  kex --win --start          # 只起服务端（后台常驻，监听 5901）
  kex --win --start-client   # 只连客户端（注意：从 WSL 拉起会随 wsl.exe 退出而被杀）
  kex --status               # 看状态
  kex --kill                 # 连服务端一起杀
  ```
- 打不开时依次检查：
  1. `kex --status` 是否 `running`
  2. `kex --kill` 后重新点快捷方式
  3. `ls /mnt/wslg` 确认 WSLg 正常
  4. 看日志 `~/.vnc/*.log`
  5. 确认 `/etc/sudoers.d/90-winkex` 存在（启动时要把 WSLg 的 X11 socket 目录重挂为可写）

---

## 2. 目录约定

```bash
~/lab/                # 所有练习/题目都放这里
~/lab/ctf/<题目名>/   # 单题：files/ src/ out/
~/lab/venv/           # Python 虚拟环境（pwntools / pycryptodome / z3 / impacket）
```

新建一个题目目录：

```bash
ctfnew web1        # → ~/lab/... 之外也会建，取决于当前目录；会生成 web1/{files,src,out}
```

---

## 3. Web 工具地图

| 阶段 | 工具 | 一句话 |
|---|---|---|
| 指纹 | `whatweb` `wafw00f` | 识别框架/中间件/WAF |
| 指纹（专用） | `wpscan` `joomscan` | WordPress / Joomla |
| 目录与文件 | `ffuf` `feroxbuster` `gobuster` `dirb` `dirsearch` | 目录/文件爆破 |
| 参数与隐藏字段 | `arjun` `wfuzz` | 找没暴露的 GET/POST 参数 |
| SQL 注入 | `sqlmap` | 自动化注入 |
| 命令注入 | `commix` | 自动化命令注入 |
| XSS | `dalfox` `xsser` | 反射/存储型 XSS 扫描 |
| 漏洞模板扫描 | `nuclei` `nikto` | CVE/配置/常见问题批量检查 |
| 路径穿越 | `dotdotpwn` | 目录穿越模糊测试 |
| 抓包改包 | `burpsuite` `zaproxy`（GUI）、`mitmproxy`（CLI） | 拦截、重放、改包 |
| 端口服务 | `nmap` `masscan` | 先摸清有哪些服务 |
| 代理链 | `proxychains4` `chisel` `sshuttle` | 内网穿透/跳板 |

字典都在：

```
/usr/share/seclists/                 1.9G（推荐，分 Discovery/Passwords/Usernames 等）
/usr/share/wordlists/                51M（含 dirb、dirbuster、john 等）
/usr/share/dirb/wordlists/           1.5M
/usr/share/wfuzz/wordlist/           1.2M
```

---

## 4. 最常用命令（直接复制改目标）

### 4.1 先看是什么

```bash
nmap -sS -sV -sC -Pn -T4 <TARGET>              # 端口+服务+默认脚本
whatweb -a 3 http://<TARGET>/                  # 指纹
wafw00f http://<TARGET>/                       # 有没有 WAF
curl -sI http://<TARGET>/ | head -20           # 响应头 / 是否重定向
```

### 4.2 目录与文件

```bash
ffuf -u http://<TARGET>/FUZZ -w /usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt \
     -mc 200,204,301,302,307,401,403 -t 60

feroxbuster -u http://<TARGET>/ -w /usr/share/seclists/Discovery/Web-Content/raft-medium-words.txt -x php,html,js,txt,bak

dirsearch -u http://<TARGET>/ -e php,html,js,zip,bak -i 200,302
```

备份/源码泄露重点看：`.git/`、`.svn/`、`www.zip`、`*.bak`、`*.swp`、`robots.txt`、`/backup.sql`。

### 4.3 参数发现（拿到接口再找隐藏参数）

```bash
arjun -u "http://<TARGET>/api/user" -m GET
arjun -u "http://<TARGET>/login" -m POST
```

### 4.4 注入

```bash
# 单点探测
sqlmap -u "http://<TARGET>/item?id=1" --batch --dbs
# 带 Cookie / POST
sqlmap -u "http://<TARGET>/login" --data "user=a&pass=b" --cookie "PHPSESSID=xxx" --batch --level 3 --risk 2
# 拿到库之后
sqlmap -u "..." -D <db> --tables
sqlmap -u "..." -D <db> -T <table> --dump

commix --url="http://<TARGET>/ping?ip=127.0.0.1" --batch
```

### 4.5 XSS

```bash
dalfox url "http://<TARGET>/search?q=test" --skip-bav
dalfox file urls.txt --skip-bav -o xss.txt
```

### 4.6 批量漏扫

```bash
nuclei -update-templates                 # 第一次先更新模板
nuclei -u http://<TARGET>/ -severity critical,high,medium
nuclei -l urls.txt -t http/cves/ -rl 50
nikto -h http://<TARGET>/ -Tuning 123bde
```

### 4.7 抓包

GUI（需要 `-WithDesktop` 或 WSLg）：

```bash
burpsuite          # 社区版；浏览器代理指到 127.0.0.1:8080
zaproxy
```

命令行（不需要桌面，适合快速看/改请求）：

```bash
mitmproxy -p 8080            # 交互式 TUI，按 ? 看帮助
mitmdump -p 8080 -w flow.log # 只落盘
```

> Windows 侧的浏览器要用 Burp 证书：先访问 `http://burp` 下载 CA，导入「受信任的根证书颁发机构」。
> 或者干脆在 Windows 上用 Reqable/浏览器插件抓包，Kali 只负责跑命令。

---

## 5. 让 Windows 访问 Kali 里的服务

NAT 模式下，Kali 里起的服务在 Windows 侧就是 `localhost:<端口>`：

```bash
cd ~/lab/ctf/web1 && serve 8000     # 然后浏览器开 http://localhost:8000
python3 -m http.server 9000
```

反过来 Kali 访问 Windows 上的服务：用宿主网关 IP（`proxy_test` 会打印），或者直接 `curl http://<宿主IP>:<端口>`。

---

## 6. 代理与内网

```bash
proxy_test        # 看宿主网关 + Windows 侧 7897 通不通
proxy_on          # 给当前 shell 设 http(s)_proxy（Clash 需开「允许局域网连接」）
proxy_off
proxychains4 curl -s https://ifconfig.me    # 走 socks/代理链（配置 /etc/proxychains4.conf）
chisel client <server>:8080 R:socks         # 内网隧道
sshuttle -r user@<host> 10.0.0.0/24         # 把内网段路由过来
```

---

## 7. 排障

| 现象 | 处理 |
|---|---|
| 某个工具 `command not found` | 先 `apt-cache show <名字>` 看仓库有没有，再 `sudo apt install <名字>`；确认 `kali-tools-web` 已装 |
| 目录爆破全 404 / 全 200 | 检查是否需要 `-H "Host: ..."`、是否有 WAF 拦截，先手工 `curl -i` 看一眼 |
| sqlmap 卡住 | 加 `--batch --timeout 15 --retries 2`，或先 `--technique=BEU` 减少探测面 |
| nuclei 没结果 | 先 `nuclei -update-templates`；模板放 `~/nuclei-templates` |
| `kex` 起不来 | `ls /mnt/wslg` 看 WSLg 是否可用；不行就纯命令行，GUI 工具用 Windows 侧 |
| Burp 证书报错 | 装 CA 到 Windows「受信任的根证书颁发机构」，或在 Kali 里配 `http_proxy` |
| 字典找不到 | `ls /usr/share/seclists/Discovery/Web-Content/` 挑合适的，别死记路径 |

---

## 8. 维护

```bash
sudo apt update && sudo apt full-upgrade -y     # 滚动更新
sudo apt clean && sudo apt autoremove -y        # 清缓存
searchsploit -u                                 # 更新 exploit-db
nuclei -update-templates                        # 更新模板
```

> ⚠️ 只对**自己搭的靶场、CTF 题目、有书面授权的目标**使用这些工具。
