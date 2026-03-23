#!/bin/bash
set -e
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}
log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}
log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用sudo运行此脚本"
        exit 1
    fi
}
show_banner() {
    echo "=========================================="
    echo "          noVNC 一键卸载脚本"
    echo "=========================================="
}
stop_services() {
    log_info "停止noVNC服务..."
    if systemctl is-active --quiet novnc 2>/dev/null; then
        systemctl stop novnc
        log_info "已停止novnc服务"
    fi
    if systemctl is-enabled --quiet novnc 2>/dev/null; then
        systemctl disable novnc
        log_info "已禁用novnc服务"
    fi
    log_info "终止noVNC相关进程..."
    pkill -f websockify || true
    pkill -f novnc_proxy || true
    pkill -f ".*6080.*localhost:5901" || true
    sleep 2
    pgrep -f websockify && killall -9 websockify 2>/dev/null || true
    pgrep -f novnc_proxy && killall -9 novnc_proxy 2>/dev/null || true
}
remove_systemd_services() {
    log_info "删除systemd服务..."
    local services=("novnc.service" "novnc@.service")
    for service in "${services[@]}"; do
        if [[ -f "/etc/systemd/system/$service" ]]; then
            rm -f "/etc/systemd/system/$service"
            log_info "已删除 /etc/systemd/system/$service"
        fi
        if [[ -f "/lib/systemd/system/$service" ]]; then
            rm -f "/lib/systemd/system/$service"
            log_info "已删除 /lib/systemd/system/$service"
        fi
    done
    if [[ -d "/etc/systemd/system/novnc.service.d" ]]; then
        rm -rf "/etc/systemd/system/novnc.service.d"
        log_info "已删除服务配置目录"
    fi
    systemctl daemon-reload
    systemctl reset-failed
}
remove_packages() {
    log_info "卸载noVNC相关软件包..."
    local packages=("novnc" "websockify" "python3-websockify")
    for pkg in "${packages[@]}"; do
        if dpkg -l | grep -q "$pkg"; then
            apt remove --purge -y "$pkg"
            log_info "已卸载 $pkg"
        fi
    done
    apt autoremove -y
    apt autoclean
}
remove_files() {
    log_info "删除noVNC相关文件和目录..."
    local dirs=(
        "/usr/share/novnc"
        "/var/lib/novnc"
        "/var/log/novnc"
        "/etc/novnc"
        "/opt/novnc"
        "/usr/local/share/novnc"
    )
    local files=(
        "/usr/local/bin/start_novnc.sh"
        "/usr/local/bin/novnc_proxy"
        "/usr/bin/novnc_proxy"
        "/etc/init.d/novnc"
        "/tmp/websockify"
        "/tmp/novnc"
    )
    for dir in "${dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            log_info "已删除目录 $dir"
        fi
    done
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            rm -f "$file"
            log_info "已删除文件 $file"
        fi
    done
    local users_home=("/home/*" "/root")
    for home_dir in ${users_home[@]}; do
        if [[ -d "$home_dir/noVNC" ]]; then
            rm -rf "$home_dir/noVNC"
            log_info "已删除 $home_dir/noVNC"
        fi
    done
}
remove_certificates() {
    log_info "清理证书文件..."
    local cert_files=(
        "self.pem"
        "novnc.pem"
        "/etc/ssl/novnc/cert.pem"
        "/etc/ssl/novnc/key.pem"
    )
    for cert in "${cert_files[@]}"; do
        if [[ -f "$cert" ]]; then
            rm -f "$cert"
            log_info "已删除证书 $cert"
        fi
    done
    if [[ -d "/etc/ssl/novnc" ]]; then
        rmdir "/etc/ssl/novnc" 2>/dev/null && log_info "已删除空证书目录" || true
    fi
}
verify_uninstall() {
    log_info "验证卸载结果..."
    echo "=== 验证检查 ==="
    if pgrep -f websockify >/dev/null || pgrep -f novnc_proxy >/dev/null; then
        log_error "发现残留的noVNC进程:"
        pgrep -fa websockify || pgrep -fa novnc_proxy
    else
        log_info "✓ 无noVNC相关进程运行"
    fi
    if netstat -tlnp 2>/dev/null | grep -q ":6080"; then
        log_error "端口6080仍在监听:"
        netstat -tlnp | grep ":6080"
    else
        log_info "✓ 端口6080未监听"
    fi
    if systemctl list-unit-files | grep -q novnc; then
        log_error "发现systemd服务残留"
        systemctl list-unit-files | grep novnc
    else
        log_info "✓ 无systemd服务残留"
    fi
    if dpkg -l | grep -i novnc || dpkg -l | grep -i websockify; then
        log_error "发现软件包残留"
        dpkg -l | grep -i novnc
        dpkg -l | grep -i websockify
    else
        log_info "✓ 无软件包残留"
    fi
    local found_files=0
    for path in /usr/share/novnc /etc/novnc /var/lib/novnc; do
        if [[ -d "$path" ]]; then
            log_error "发现目录残留: $path"
            found_files=1
        fi
    done
    if [[ $found_files -eq 0 ]]; then
        log_info "✓ 无重要文件残留"
    fi
}
main() {
    show_banner
    check_root
    log_warn "此操作将完全卸载noVNC，是否继续? (y/N)"
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY])
            echo "开始卸载..."
            ;;
        *)
            log_info "取消卸载"
            exit 0
            ;;
    esac
    stop_services
    remove_systemd_services
    remove_packages
    remove_files
    remove_certificates
    verify_uninstall
    echo
    log_info "noVNC 卸载完成!"
    log_info "注意: VNC服务(5901端口)仍然保持运行状态"
}
main "$@"