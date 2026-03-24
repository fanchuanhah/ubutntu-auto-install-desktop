# Tmoe 桌面安装说明（适用于 Ubuntu）

本文档基于仓库中的 tmoe 安装脚本生成，汇总了脚本在 Ubuntu 系统上安装各类桌面环境（DE）时的要点、依赖包与额外配置步骤，便于手动复现或理解脚本行为。

## 快速安装命令（Ubuntu）
下面为常见桌面环境在 Ubuntu 上的快速安装命令与最小 `~/.vnc/xstartup` 示例。使用前请先 `sudo apt update`，并根据需要选择完整版（如 `xubuntu-desktop`/`kubuntu-desktop` 等）。

- XFCE（推荐轻量且兼容）：

```bash
sudo apt update
sudo apt install -y xfce4 xfce4-goodies xfce4-terminal fonts-noto-cjk fonts-noto-color-emoji tigervnc-standalone-server
cat > ~/.vnc/xstartup <<'EOF'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
x-terminal-emulator &
exec dbus-launch startxfce4
EOF
chmod +x ~/.vnc/xstartup
```

- KDE (Plasma 5)：

```bash
sudo apt update
sudo apt install -y kde-plasma-desktop fonts-noto-cjk fonts-noto-color-emoji tigervnc-standalone-server
cat > ~/.vnc/xstartup <<'EOF'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
x-terminal-emulator &
exec dbus-launch startplasma-x11
EOF
chmod +x ~/.vnc/xstartup
```

- GNOME（最小）：

```bash
sudo apt update
sudo apt install -y --no-install-recommends xorg gnome-core gnome-session gnome-shell gnome-tweak-tool fonts-noto-cjk fonts-noto-color-emoji tigervnc-standalone-server
cat > ~/.vnc/xstartup <<'EOF'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
x-terminal-emulator &
exec dbus-launch gnome-session
EOF
chmod +x ~/.vnc/xstartup
```

- LXDE：

```bash
sudo apt update
sudo apt install -y lxde-core lxterminal fonts-noto-cjk tigervnc-standalone-server
cat > ~/.vnc/xstartup <<'EOF'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
x-terminal-emulator &
exec dbus-launch lxsession
EOF
chmod +x ~/.vnc/xstartup
```

- LXQt：

```bash
sudo apt update
sudo apt install -y lxqt-core qterminal xfwm4 xfwm4-theme-breeze lxqt-config fonts-noto-cjk tigervnc-standalone-server
cat > ~/.vnc/xstartup <<'EOF'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
x-terminal-emulator &
exec dbus-launch startlxqt
EOF
chmod +x ~/.vnc/xstartup
```

- MATE：

```bash
sudo apt update
sudo apt install -y mate-desktop-environment mate-terminal fonts-noto-cjk tigervnc-standalone-server
cat > ~/.vnc/xstartup <<'EOF'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
x-terminal-emulator &
exec dbus-launch mate-session
EOF
chmod +x ~/.vnc/xstartup
```

- Cinnamon：

```bash
sudo apt update
sudo apt install -y --no-install-recommends cinnamon cinnamon-desktop-environment fonts-noto-cjk tigervnc-standalone-server
cat > ~/.vnc/xstartup <<'EOF'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
x-terminal-emulator &
exec dbus-launch cinnamon-session
EOF
chmod +x ~/.vnc/xstartup
```

- Deepin（Ubuntu 衍生环境）：

```bash
sudo apt update
sudo apt install -y ubuntudde-dde deepin-terminal fonts-noto-cjk tigervnc-standalone-server
cat > ~/.vnc/xstartup <<'EOF'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
x-terminal-emulator &
exec dbus-launch startdde
EOF
chmod +x ~/.vnc/xstartup
```

- UKUI：

```bash
sudo apt update
sudo apt install -y ukui-session-manager ukui-menu ukui-control-center ukui-screensaver ukui-themes peony fonts-noto-cjk tigervnc-standalone-server
cat > ~/.vnc/xstartup <<'EOF'
#!/usr/bin/env bash
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
x-terminal-emulator &
exec dbus-launch ukui-session
EOF
chmod +x ~/.vnc/xstartup
```

-- 将 tmoe 的菜单快捷方式放入系统菜单（可选）：

```bash
sudo cp tools/app/lnk/tmoe-linux.desktop /usr/share/applications/
```

以上为最常用的快速命令示例。若需我在文件中为某个 Ubuntu 版本（如 20.04/22.04/24.04）做细化说明或生成可执行安装脚本，请告诉我要针对的版本或要包含的额外步骤。

<!-- 原详细说明可继续保留于下方 -->
