# 实测记录

本项目的每条路径都是在本机真跑出来的，不是"应该能用"。记录如下，方便你判断适配性。

## 测试机

| 项 | 值 |
|---|---|
| Windows | Windows 11 Build 26200 |
| WSL | 2.7.3.0（内核 6.6.114.1-1） |
| 硬件 | 32GB 内存 / 24 线程 |
| 网络 | 国内家宽，无代理（GitHub 直连不通） |

## Ubuntu 路径（2026-10-22）

```
install.ps1 -Distro ubuntu -Location C:\WSL-test -UserName ctf
```

| 步骤 | 结果 |
|---|---|
| 预检（Build/WSL/虚拟化） | 通过 |
| 解析镜像 | 清华 `ubuntu-base-24.04.5-base-amd64.tar.gz` |
| SHA256 | 与镜像站 SHA256SUMS 一致 ✓ |
| `wsl --import` | 成功 |
| 装配 | 完成（基础包 + 26 个 CTF 工具 + venv + pwndbg + zsh + wsl.conf） |
| `doctor.ps1` | **21 通过 / 0 警告 / 0 失败** |
| `uninstall.ps1` | 注销 + 删目录 + 删快捷方式 + 删 Terminal profile，干净 |

## Kali 路径（2026-10-24）

```
install.ps1 -Distro kali -Location C:\WSL-test -UserName ctf
```

| 步骤 | 结果 |
|---|---|
| 官方 rootfs | `kali-2026.2-wsl-rootfs-amd64.wsl`，SHA256 `1b172389…466c6` 校验通过 ✓ |
| 导入 | 成功（切换到 `kali-rolling` 后 `apt full-upgrade`） |
| 装配 | 完成，**3123 个包**，磁盘约 22GB |
| 镜像 | 自动测速选中清华（3.1 MB/s），源写入正确 |
| pwndbg | `gdb` 启动即加载（`pwndbg: loaded …`）——包括 gdb 内嵌 Python 3.14 的情况 |
| `doctor.ps1` | **24 通过 / 0 失败**（`kex` 为可选未装） |
| 启动器 | `.cmd` + Terminal profile + 桌面快捷方式 均生成；卸载后全部清除 |

## 这些测试里发现并修掉的问题

按发现顺序（都是真实会卡住新手的问题）：

1. **微软商店 / `wsl --install` 下载失败**（`0x80072f78`）→ 改成直接下官方 rootfs + `wsl --import`
2. **`git autocrlf=true` 会把 `.sh` 转成 CRLF** → bash 报 `$'\r': command not found`；加 `.gitattributes` + 安装时兜底 `sed`
3. **`ubuntu-base` 没有 `sudo`** → venv 创建失败；改 `as_user()`（runuser → sudo → su 降级）
4. **pwndbg 新版依赖 `niche-elf`**（启动即 import）→ 依赖表补齐
5. **`ubuntu.sources` 有多个 stanza**，统一改写 `Suites:` 会产生重复源告警 → 只改 `URIs:`
6. **`pick_mirror` 的 URL 多拼了一层发行版路径**（`…/kali/kali/dists/…`）→ Kali 侧测速全 404，只剩兜底
7. **缺 pwn 内核参数** → 增加 `ptrace_scope=0` / `mmap_min_addr=0` / core dump
8. **`Invoke-Stream` 的子进程输出混进返回值** → 退出码误判、汇总串行
9. **`kismet` 的 debconf 配置脚本读 stdin** → detached 进程里永久挂住（实测卡 1 小时）；apt/dpkg 全部加 `</dev/null` + `policy-rc.d`
10. **装配中断会留下 `Kali-CTF2` 之类重复发行版** → 加早期标记 `/etc/wsl-ctf-kit`
11. **Terminal 自动生成的同名 profile 会让 `wt -p Kali` 命中错误的那个** → 就地改造同名项并去掉 `source`
12. **机器同时装 Store 版和便携版 Terminal** → 写入所有发现的配置

## 尚未覆盖

| 项 | 说明 |
|---|---|
| `-WithDesktop`（Win-KeX） | 代码路径已写，未在本机跑完整流程 |
| `-WithDocker` | 同上；且 Docker Desktop 与本项目无耦合 |
| Windows 10 (2004–21H2) | 逻辑上兼容（未用 Win11 独有特性），未实测 |
| ARM64 / WSL 的 arm64 发行版 | 只实现了 amd64；ARM 设备会下载失败并明确报错 |
| 有代理 / 企业网络 | 镜像站被拦时会退回官方源，速度未知 |
| 中文以外的系统语言 | `.cmd` 是纯 ASCII，理论上与语言无关，未实测 |
