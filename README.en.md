# wsl-ctf-kit

> One-click CTF environment for Windows: **WSL2 Kali + Ubuntu**, fully provisioned.
> Run one script, get two Linux environments with a complete toolchain — no VM, no dual boot.

```
Windows 11 / 10 (2004+)
   └── WSL2
        ├── Kali   — web / pwn / reversing / forensics / AD, with Metasploit, pwndbg, SecLists
        └── Ubuntu — general dev + pwn (gdb+pwndbg, pwntools, Docker)
```

Distribution images are downloaded from their official publishers (or a fast local mirror)
at install time. **No images are stored in this repository** — the repo is a few dozen KB.

---

## Why not install it yourself

Getting Kali into WSL2 makes beginners hit the same handful of walls. This project already solved them:

| Problem | What you see | How this repo handles it |
|---|---|---|
| Store / `wsl --install` download fails | `0x80072f78`, or stuck at 0% | Fetch the official rootfs, verify SHA256, `wsl --import` |
| Kali's default mirror is slow | `apt update` hangs for minutes | Measure real index throughput, pick fastest mirror (TUNA / USTC / Aliyun) |
| Image pinned to a release snapshot | Old packages | Rewrite `kali-last-snapshot` → `kali-rolling` |
| `pwndbg` removed from Kali repos | `apt install pwndbg` → not found | Build from source via GitHub mirror + own venv + `uv.lock.hash` fix |
| GitHub blocked | cloning tools / templates fails | Built-in `ghfast.top` / `gh-proxy.com` fallback chain |
| `pip install` blocked by PEP 668 | `externally-managed-environment` | Everything goes into `~/lab/venv` |
| apt killed leaves stale locks | every later apt hangs forever | Locks cleared automatically before each apt call |
| Mirror resolves to IPv6 only | `Network is unreachable` | apt forced to IPv4 |
| Installer scripts reading stdin | hangs forever in a detached process | `< /dev/null` everywhere + `policy-rc.d` |
| Hand-editing `wsl.conf` | default user / systemd not applied | Written by the installer, then distro restarted |

Every step is **idempotent**: if something breaks, just run it again.
`doctor.ps1` verifies the result, `uninstall.ps1` removes everything cleanly.

---

## Quick start

```powershell
# 1. PowerShell (no admin needed)
git clone https://github.com/sanyin/wsl-ctf-kit.git
cd wsl-ctf-kit

# 2. Check prerequisites only — no download, no changes
.\install.ps1 -DryRun

# 3. Install both (default user: ctf / password: ctf)
.\install.ps1
```

You get:

- Desktop shortcuts `Open-Kali` / `Open-Ubuntu-CTF`
- Windows Terminal profiles `Kali` and `Ubuntu-CTF` (color coded)
- Virtual disks under `C:\WSL\Kali` and `C:\WSL\Ubuntu-CTF`

> First run: Kali image 236 MB + ~3.5–4 GB of packages (20–45 min);
> Ubuntu image 30 MB + ~1 GB of packages (10–20 min).
> Interrupting is safe — rerun and it resumes / skips completed work.

> To keep disks small, Kali installs only the tool families that matter in WSL.
> **Not** included: `kali-tools-802-11` (needs a real wireless card with monitor mode),
> bluetooth / SDR / RFID / hardware / VoIP (same reason). Install them yourself if you need them.

---

## Parameters

```powershell
.\install.ps1 -Distro kali                       # Kali only
.\install.ps1 -Distro ubuntu                     # Ubuntu only
.\install.ps1 -WithDesktop                       # Kali + Win-KeX (XFCE)
.\install.ps1 -Location D:\WSL                   # install somewhere else (default C:\WSL)
.\install.ps1 -UserName alice -Password 'MyPass' # custom account
.\install.ps1 -Force                             # reinstall (unregisters first)
.\install.ps1 -SkipProvision                     # import only, no toolchain (debug)
```

| Parameter | Default | Meaning |
|---|---|---|
| `-Distro` | `both` | `both` / `kali` / `ubuntu` |
| `-Location` | `C:\WSL` | where virtual disks live |
| `-UserName` | `ctf` | Linux user |
| `-Password` | `ctf` | user password (also sudo password) |
| `-WithDesktop` | off | Kali: `kali-desktop-xfce` + `kali-win-kex` (+1.5 GB) |
| `-WithDocker` | off | install Docker as well |
| `-NoLauncher` | off | skip shortcuts / Terminal profiles |
| `-DryRun` | — | resolve URLs and check env, change nothing |

---

## What gets installed

### Kali (the CTF workhorse)
- `kali-linux-headless` plus the families: information-gathering / vulnerability / web /
  exploitation / passwords / post-exploitation / sniffing / forensics / reverse-engineering /
  crypto-stego / reporting / top10
- Named tools: `metasploit-framework`, `seclists` (1.9 G), `sqlmap`, `ffuf`, `gobuster`,
  `feroxbuster`, `nikto`, `whatweb`, `wpscan`, `nuclei`, `dalfox`, `arjun`, `dirsearch`,
  `nmap`, `masscan`, `hashcat`, `john`, `hydra`, `tshark`, `binwalk`, `foremost`, `sleuthkit`,
  `radare2`, `rizin`, `ghidra`, `jadx`, `apktool`, `responder`, `nxc`, `impacket`, `proxychains4`, `chisel`
- Pwn: `pwndbg`, `python3-pwntools`, `patchelf`, `checksec`, `qemu-user`
- Desktop (opt-in): Win-KeX — `kex` (window) or `kex --sl` (seamless)

### Ubuntu (dev + pwn)
- zsh + completions/highlighting, `fzf`, `zoxide`, `ripgrep`, `bat`, `tmux`, `git`, `build-essential`
- `nmap`, `sqlmap`, `hydra`, `john`, `hashcat`, `gobuster`, `ffuf`, `nikto`, `tcpdump`, `tshark`,
  `binwalk`, `foremost`, `sleuthkit`, `exiftool`, `steghide`, `radare2`, `patchelf`, `qemu-user`
- Pwn: `pwndbg` + `~/lab/venv` (pwntools / pycryptodome / z3 / capstone / impacket)
- Note: Metasploit is Kali-only (not packaged in Ubuntu)

Both environments share the same aliases: `ctfnew` (scaffold a challenge dir),
`revshell` (generate reverse-shell one-liners), `newpwn` (pwntools template),
`extract` (recursive unpack), `serve`, `proxy_on/proxy_off/proxy_test`, `winpath`, `wdesk`.

---

## After install

```bash
wsl -d Kali

passwd                     # change the default password first
ctfnew web1                # -> web1/{files,src,out}
checksec --file=./chall
newpwn 127.0.0.1 1337 ./chall
gdb -q ./chall             # pwndbg loads automatically

serve 8000                 # browse http://localhost:8000 on Windows
kex                        # GUI desktop (only with -WithDesktop)
```

Health check / removal (Windows side):

```powershell
.\doctor.ps1
.\uninstall.ps1 -Distro Kali        # interactive confirmation
.\uninstall.ps1 -Distro all -Yes
```

---

## Documentation

| Doc | Content |
|---|---|
| [docs/manual-kali.md](docs/manual-kali.md) | Kali operations manual — web-focused: recon, content discovery, params, SQLi, XSS, nuclei, Burp/mitmproxy, wordlists, proxy, troubleshooting |
| [docs/manual-ubuntu.md](docs/manual-ubuntu.md) | Ubuntu operations manual — pwn workflow, pwndbg, python/venv, Docker, aliases, troubleshooting |
| [docs/tools.md](docs/tools.md) | Full tool inventory grouped by purpose |
| [docs/faq.md](docs/faq.md) | FAQ: no WSL / slow download / disk / proxy / desktop / uninstall |
| [docs/tested.md](docs/tested.md) | What was actually tested on real hardware, plus the 12 bugs found and fixed |
| [README.md](README.md) | Chinese README |

---

## Repository layout

```
wsl-ctf-kit/
├── install.ps1           # preflight → download → import → provision → launchers
├── doctor.ps1            # health check
├── uninstall.ps1         # clean removal (distro + files + shortcuts + Terminal profiles)
├── lib/
│   ├── Common.ps1        # logging, WSL probing, resumable download, SHA256, path conversion
│   └── Launcher.ps1      # .cmd + Terminal profile + desktop shortcut
├── provision/
│   ├── setup.sh          # in-distro provisioning (mirrors → user → tools → venv → pwndbg → shell → wsl.conf)
│   ├── lib.sh            # apt wrapper, mirror speed test, user creation
│   ├── pwndbg.sh         # pwndbg from source (with the uv.lock.hash fix)
│   ├── doctor.sh         # in-distro checks
│   └── zshrc.tpl         # shell config template
└── docs/{manual-kali,manual-ubuntu,tools,faq,tested}.md
```

---

## Known limitations

- **No local mirror for the Kali image** (official `kali.download` only). 236 MB, resumable.
- **`networkingMode=mirrored` is not enabled.** On many machines it fails with
  `0x8007054f` (proxy TUN/filter driver conflict) and WSL falls back to no networking.
  Use `proxy_on` instead (see FAQ).
- **No Metasploit on Ubuntu** (not packaged upstream). Use Kali.
- **Virtual disks only grow.** Shrink with `wsl --shutdown` + `diskpart compact vdisk` if needed.
- **Desktop is opt-in** (`-WithDesktop`).
- Verified on **Windows 11 and Windows 10 2004+**; older builds have incomplete WSL2 support.
- **AMD64 only.** ARM64 hosts are not supported yet (the installer fails with a clear error).

## Disclaimer

The installed tools are for **authorized security testing, CTF competitions and learning only**.
Kali Linux is a trademark of Offensive Security; Ubuntu is a trademark of Canonical Ltd.
This project only downloads images published by those vendors and does not redistribute them.

## License

[MIT](LICENSE)
