# 常见问题

## 安装前

### WSL 没装 / 提示找不到 wsl.exe
管理员 PowerShell：

```powershell
wsl --install --no-distribution
```

装完**重启电脑**，再运行 `.\install.ps1`。若仍失败，检查 BIOS 里 `VT-x` / `SVM`（AMD）是否开启。

### 提示虚拟化不可用
- 任务管理器 → 性能 → CPU，看「虚拟化：已启用」
- 被 Hyper-V / 虚拟机平台 / 内存完整性（核心隔离）占用也会影响，按提示开启对应 Windows 功能

### `-DryRun` 说 Ubuntu 镜像解析失败
说明几个镜像站都连不上。检查网络/代理后重试；或直接只装 Kali：`.\install.ps1 -Distro kali`。

---

## 下载

### Kali 镜像下载很慢 / 断了
Kali 官方只发布在 `kali.download`，没有国内镜像站。下载器支持**断点续传**：

```powershell
# 直接重跑同一命令即可，会从断点继续
.\install.ps1 -Distro kali
```

想手动下载放到缓存目录也行：

```
C:\WSL\_cache\kali-rootfs.wsl        # 默认位置（-Location 改盘则跟着变）
```

放好后重跑安装，脚本会先校验 SHA256 再导入。

### 提示 SHA256 不匹配
文件坏了或下到了错误内容。脚本会自动删掉坏文件，重跑即可。反复失败就换网络环境。

### 安装到一半关掉了窗口
没有半成品风险：镜像在缓存里、发行版要么已注册要么没注册。重跑 `install.ps1` 继续。

---

## 使用

### 密码是什么？忘了怎么办
默认 `ctf` / `ctf`（安装时可 `-Password` 指定）。忘了就：

```powershell
wsl -d Kali -u root -- passwd ctf
```

### 桌面 / 终端里找不到 Kali
- 桌面快捷方式：`Open-Kali`（如果当时用了 `-NoLauncher` 就没有）
- Windows Terminal：标签栏下拉里找 `Kali`；或 `wt -p Kali`
- 任意位置：`wsl -d Kali`

想让 Terminal 重新生成 profile：`.\install.ps1 -NoLauncher:$false`（会重新注入，幂等）。

### `gdb` 进去没有 pwndbg
```bash
# 看加载情况
gdb -batch -ex "pi import pwndbg; print('ok')"
# 重装
sudo bash /mnt/c/<kit路径>/provision/pwndbg.sh
```

pwndbg 装不上最常见原因是 GitHub 镜像都不通；脚本会退回只用裸 gdb，不影响其他工具。

### `pip install` 报 `externally-managed-environment`
新版 Debian/Kali/Ubuntu 的系统 Python 不允许直接装包。用项目预置的 venv：

```bash
source ~/lab/venv/bin/activate
pip install xxx
```

### apt 卡住不动（网络正常、CPU 空闲、没输出）
多半是之前被强杀的 apt 留下了锁：

```bash
sudo rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock \
           /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend
sudo dpkg --configure -a
```

### 想用代理（Clash/v2ray 等）
WSL 默认 NAT 模式，WSL 里的 `127.0.0.1` 是它自己，不是 Windows。两种做法：

1. **代理软件打开「允许局域网连接 / Allow LAN」**，然后在 WSL 里：
   ```bash
   proxy_test     # 看宿主网关和 7897 通不通
   proxy_on       # 设置 http(s)_proxy
   proxy_off
   ```
2. 只让 apt 走国内镜像就够了（本项目默认已经这么做）。

> 不建议开 `networkingMode=mirrored`：它在不少机器上会失败并让 WSL 直接断网，
> 详见 README「已知限制」。

### 中文显示成方块 / 乱码
- Windows Terminal 字体换成 `Cascadia Mono` 或 `Microsoft YaHei`，别用纯英文字体
- Linux 侧：`sudo apt install fonts-wqy-microhei fonts-noto-cjk`

### 升级 Kali
```bash
sudo apt update && sudo apt full-upgrade -y
```

想换镜像：`sudo bash /mnt/c/<kit>/provision/setup.sh`（会重新测速选源）。

### 磁盘占用太大，怎么瘦身
```bash
sudo apt clean
sudo apt autoremove --purge -y
du -sh /var/* 2>/dev/null | sort -h | tail
```

vhdx **不会自动变小**。要真正释放：

```powershell
wsl --shutdown
# 用「磁盘管理」附加 D:\WSL\Kali\ext4.vhdx 后压缩，或用 diskpart compact vdisk
```

### 装了多份 Kali / Ubuntu
脚本默认不覆盖：已存在同名就改用 `Kali-CTF` / `Ubuntu-CTF`。
重装用：

```powershell
.\install.ps1 -Distro kali -Force
```

### 卸载后还有残留
`uninstall.ps1` 会注销发行版、删目录、清快捷方式和 Terminal profile。仍可能残留：

- 镜像缓存：`C:\WSL\_cache`
- Terminal 配置备份：`settings.json.bak-*`
- `.wslconfig`（本项目不改它；若你自己加过配置需手动删）

---

## 图形桌面（Win-KeX）

### `kex` 起不来 / 黑屏
1. 确认装了桌面：`dpkg -l | grep kali-win-kex`
2. 确认 WSLg 可用：`ls /mnt/wslg`
3. 关掉再看日志：
   ```bash
   kex --stop
   kex --win -s
   ```
4. 实在不行用命令行就够打 CTF 了，GUI 工具走 Windows 侧。

### 桌面中文是方块
```bash
sudo apt install fonts-wqy-microhei fonts-noto-cjk
```
