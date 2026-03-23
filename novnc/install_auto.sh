#!/bin/bash
set -e

# ========== 默认配置（可在此修改）==========
DEFAULT_UPDATE="yes"       # 是否更新系统包
DEFAULT_VNC_PORT="5901"    # 默认VNC端口
DEFAULT_NOVNC_PORT="6080"  # 默认noVNC端口
DEFAULT_SSL="yes"          # 是否启用SSL
DEFAULT_ENABLE="yes"       # 是否开机自启动
DEFAULT_FORCE_PORT="no"    # 端口被占用时是否强制使用
# ==========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            update=*)
                UPDATE="${1#*=}"
                ;;
            vncport=*)
                VNC_PORT="${1#*=}"
                ;;
            novncport=*)
                NOVNC_PORT="${1#*=}"
                ;;
            ssl=*)
                SSL_ENABLED="${1#*=}"
                ;;
            enable=*)
                ENABLE_AUTOSTART="${1#*=}"
                ;;
            force=*)
                FORCE_PORT="${1#*=}"
                ;;
            *)
                log_warn "未知参数: $1"
                ;;
        esac
        shift
    done
    
    # 设置默认值
    UPDATE=${UPDATE:-$DEFAULT_UPDATE}
    VNC_PORT=${VNC_PORT:-$DEFAULT_VNC_PORT}
    NOVNC_PORT=${NOVNC_PORT:-$DEFAULT_NOVNC_PORT}
    SSL_ENABLED=${SSL_ENABLED:-$DEFAULT_SSL}
    ENABLE_AUTOSTART=${ENABLE_AUTOSTART:-$DEFAULT_ENABLE}
    FORCE_PORT=${FORCE_PORT:-$DEFAULT_FORCE_PORT}
    
    # 转换布尔值为小写
    UPDATE=$(echo "$UPDATE" | tr '[:upper:]' '[:lower:]')
    SSL_ENABLED=$(echo "$SSL_ENABLED" | tr '[:upper:]' '[:lower:]')
    ENABLE_AUTOSTART=$(echo "$ENABLE_AUTOSTART" | tr '[:upper:]' '[:lower:]')
    FORCE_PORT=$(echo "$FORCE_PORT" | tr '[:upper:]' '[:lower:]')
    
    log_info "配置参数:"
    log_info "系统更新: $UPDATE"
    log_info "VNC端口: $VNC_PORT"
    log_info "noVNC端口: $NOVNC_PORT"
    log_info "SSL加密: $SSL_ENABLED"
    log_info "开机自启: $ENABLE_AUTOSTART"
    log_info "强制端口: $FORCE_PORT"
}

# 检测系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        OS_VERSION=$VERSION_ID
        OS_ID=$ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si)
        OS_VERSION=$(lsb_release -sr)
        OS_ID=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    else
        OS=$(uname -s)
        OS_VERSION=$(uname -r)
        OS_ID="unknown"
    fi
    
    log_info "检测到系统: $OS $OS_VERSION"
    
    # 检测包管理器
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
        PKG_INSTALL="apt install -y"
        PKG_UPDATE="apt update"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        PKG_INSTALL="yum install -y"
        PKG_UPDATE="yum update -y"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="dnf install -y"
        PKG_UPDATE="dnf update -y"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER="zypper"
        PKG_INSTALL="zypper install -y"
        PKG_UPDATE="zypper refresh"
    else
        log_error "未找到支持的包管理器"
        exit 1
    fi
    
    log_info "使用包管理器: $PKG_MANAGER"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用sudo运行此脚本"
        exit 1
    fi
}

# 显示横幅
show_banner() {
    echo "=========================================="
    echo "  noVNC 一键安装脚本 (自动版)"
    echo "=========================================="
}

# 检测网络工具
detect_network_tools() {
    if command -v netstat >/dev/null 2>&1; then
        NETSTAT_CMD="netstat -tlnp"
    elif command -v ss >/dev/null 2>&1; then
        NETSTAT_CMD="ss -tlnp"
    else
        log_warn "未找到netstat或ss命令，安装网络工具..."
        $PKG_INSTALL net-tools 2>/dev/null || $PKG_INSTALL iproute2 2>/dev/null || true
        if command -v netstat >/dev/null 2>&1; then
            NETSTAT_CMD="netstat -tlnp"
        else
            NETSTAT_CMD="ss -tlnp"
        fi
    fi
}

# 检测端口占用
check_port_usage() {
    local port=$1
    local service_name=$2
    local forced=$3
    
    if $NETSTAT_CMD 2>/dev/null | grep -q ":${port}[^0-9]"; then
        log_warn "$service_name 端口 $port 已被占用"
        
        if [[ "$forced" == "yes" ]]; then
            log_info "强制使用端口 $port"
            return 0
        else
            # 自动寻找可用端口
            local new_port=$((port + 1))
            while [[ $new_port -lt 65535 ]]; do
                if ! $NETSTAT_CMD 2>/dev/null | grep -q ":${new_port}[^0-9]"; then
                    log_info "端口 $port 被占用，自动切换到端口 $new_port"
                    if [[ "$service_name" == "noVNC" ]]; then
                        NOVNC_PORT=$new_port
                    elif [[ "$service_name" == "VNC" ]]; then
                        VNC_PORT=$new_port
                    fi
                    return 1
                fi
                ((new_port++))
            done
            log_error "找不到可用端口"
            exit 1
        fi
    fi
    return 0
}

# 检查VNC服务状态
check_vnc_service() {
    log_info "检查VNC服务状态..."
    if $NETSTAT_CMD 2>/dev/null | grep -q ":${VNC_PORT}[^0-9]"; then
        log_info "✓ VNC服务在端口 $VNC_PORT 正常运行"
        VNC_RUNNING=true
    else
        log_warn "未检测到VNC服务在端口 $VNC_PORT 运行"
        log_warn "noVNC将正常安装，但需要VNC服务运行后才能使用"
        VNC_RUNNING=false
    fi
}

# 安装依赖
install_dependencies() {
    log_info "安装系统依赖..."
    
    if [[ "$UPDATE" == "yes" ]]; then
        $PKG_UPDATE
    fi
    
    # 根据不同的包管理器安装依赖
    case $PKG_MANAGER in
        apt)
            apt install -y python3-websockify novnc net-tools openssl curl
            ;;
        yum|dnf)
            $PKG_INSTALL python3-websockify novnc net-tools openssl curl
            ;;
        zypper)
            zypper install -y python3-websockify novnc net-tools openssl curl
            ;;
    esac
    
    # 检查websockify安装
    if ! command -v websockify >/dev/null 2>&1; then
        log_warn "websockify未找到，尝试通过pip安装..."
        if command -v pip3 >/dev/null 2>&1; then
            pip3 install websockify
        elif command -v pip >/dev/null 2>&1; then
            pip install websockify
        else
            $PKG_INSTALL python3-pip || $PKG_INSTALL python-pip
            if command -v pip3 >/dev/null 2>&1; then
                pip3 install websockify
            else
                pip install websockify
            fi
        fi
    fi
    
    # 检查noVNC网页文件
    if [ ! -d "/usr/share/novnc" ] && [ ! -d "/usr/local/share/novnc" ]; then
        log_warn "noVNC网页文件未找到，尝试从GitHub下载..."
        local novnc_dir="/usr/local/share/novnc"
        mkdir -p $novnc_dir
        if command -v git >/dev/null 2>&1; then
            git clone https://github.com/novnc/noVNC.git /tmp/novnc
            cp -r /tmp/novnc/* $novnc_dir/
            rm -rf /tmp/novnc
        elif command -v curl >/dev/null 2>&1; then
            cd /tmp
            curl -L https://github.com/novnc/noVNC/archive/master.tar.gz -o novnc.tar.gz
            tar -xzf novnc.tar.gz
            cp -r noVNC-master/* $novnc_dir/
            rm -rf noVNC-master novnc.tar.gz
        else
            log_error "无法下载noVNC文件"
            exit 1
        fi
    fi
}

# 设置SSL证书
setup_ssl_certificate() {
    if [[ "$SSL_ENABLED" != "yes" ]]; then
        log_info "禁用SSL加密"
        SSL_ENABLED=false
        return
    fi
    
    log_info "配置SSL证书..."
    local ssl_dir="/etc/novnc/ssl"
    mkdir -p "$ssl_dir"
    
    # 生成自签名证书
    log_info "生成自签名SSL证书..."
    if ! command -v openssl >/dev/null 2>&1; then
        log_error "OpenSSL未安装，无法生成证书"
        SSL_ENABLED=false
        return
    fi
    
    openssl req -new -x509 -days 3650 -nodes \
        -out "$ssl_dir/novnc.crt" \
        -keyout "$ssl_dir/novnc.key" \
        -subj "/C=CN/ST=State/L=City/O=Organization/OU=Organization Unit/CN=$(hostname)" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        chmod 600 "$ssl_dir/novnc.key"
        chmod 644 "$ssl_dir/novnc.crt"
        SSL_CERT="$ssl_dir/novnc.crt"
        SSL_KEY="$ssl_dir/novnc.key"
        log_info "✓ 自签名证书已生成: $SSL_CERT"
        SSL_ENABLED=true
    else
        log_error "证书生成失败，将禁用SSL"
        SSL_ENABLED=false
    fi
}

# 设置noVNC服务
setup_novnc_service() {
    log_info "配置noVNC系统服务..."
    
    # 检查noVNC端口占用
    check_port_usage "$NOVNC_PORT" "noVNC" "$FORCE_PORT"
    
    # 查找websockify路径
    local websockify_path=$(command -v websockify)
    if [ -z "$websockify_path" ]; then
        log_error "未找到websockify"
        exit 1
    fi
    
    # 查找noVNC网页目录
    local novnc_web_dir=""
    if [ -d "/usr/share/novnc" ]; then
        novnc_web_dir="/usr/share/novnc"
    elif [ -d "/usr/local/share/novnc" ]; then
        novnc_web_dir="/usr/local/share/novnc"
    else
        log_error "未找到noVNC网页目录"
        exit 1
    fi
    
    # 创建服务文件
    if [[ "$SSL_ENABLED" == "true" && -n "$SSL_CERT" && -n "$SSL_KEY" ]]; then
        log_info "配置带SSL加密的noVNC服务..."
        cat > /etc/systemd/system/novnc.service << EOF
[Unit]
Description=noVNC Service with SSL (VNC:${VNC_PORT})
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=${websockify_path} --web=${novnc_web_dir} --cert=${SSL_CERT} --key=${SSL_KEY} ${NOVNC_PORT} localhost:${VNC_PORT}
Restart=always
RestartSec=5
StartLimitInterval=60
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF
    else
        log_info "配置普通noVNC服务（无SSL）..."
        cat > /etc/systemd/system/novnc.service << EOF
[Unit]
Description=noVNC Service (VNC:${VNC_PORT})
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=${websockify_path} --web=${novnc_web_dir} ${NOVNC_PORT} localhost:${VNC_PORT}
Restart=always
RestartSec=5
StartLimitInterval=60
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
EOF
    fi
    
    log_info "✓ noVNC服务配置完成: VNC端口 $VNC_PORT -> Web端口 $NOVNC_PORT"
}

# 启用自启动
enable_autostart() {
    if [[ "$ENABLE_AUTOSTART" != "yes" ]]; then
        log_info "跳过开机自启动配置"
        return
    fi
    
    log_info "配置开机自启动..."
    systemctl daemon-reload
    systemctl enable novnc
    systemctl start novnc
    log_info "✓ noVNC服务已设置为开机自启动"
}

# 检查防火墙
check_firewall() {
    log_warn "=== 重要提醒 ==="
    log_warn "noVNC将使用端口 ${NOVNC_PORT} 提供Web访问"
    log_warn "VNC服务端口: ${VNC_PORT}"
    
    # 检测防火墙并提示
    if command -v ufw >/dev/null 2>&1; then
        log_warn "检测到UFW防火墙，请运行: ufw allow ${NOVNC_PORT}"
    elif command -v firewall-cmd >/dev/null 2>&1; then
        log_warn "检测到firewalld，请运行: firewall-cmd --add-port=${NOVNC_PORT}/tcp --permanent && firewall-cmd --reload"
    elif command -v iptables >/dev/null 2>&1; then
        log_warn "检测到iptables，请确保端口 ${NOVNC_PORT} 已开放"
    fi
    
    if [[ "$SSL_ENABLED" == "true" ]]; then
        log_warn "当前配置使用SSL加密连接"
    else
        log_warn "当前配置使用普通HTTP连接（未加密）"
    fi
    
    if [[ "$VNC_RUNNING" == "false" ]]; then
        log_warn "⚠️  当前VNC服务未运行，请确保VNC服务在端口 ${VNC_PORT} 启动"
    fi
    log_warn "================="
}

# 验证安装
verify_installation() {
    log_info "验证安装..."
    sleep 3
    
    if systemctl is-active --quiet novnc; then
        log_info "✓ noVNC服务运行正常"
    else
        log_error "noVNC服务启动失败"
        systemctl status novnc
        exit 1
    fi
    
    if [[ "$ENABLE_AUTOSTART" == "yes" ]]; then
        if systemctl is-enabled --quiet novnc; then
            log_info "✓ noVNC服务已启用开机自启动"
        else
            log_error "noVNC服务开机自启动配置失败"
            exit 1
        fi
    fi
    
    if $NETSTAT_CMD 2>/dev/null | grep -q ":${NOVNC_PORT}[^0-9]"; then
        log_info "✓ noVNC在端口 ${NOVNC_PORT} 监听"
    else
        log_error "noVNC未在端口 ${NOVNC_PORT} 监听"
        exit 1
    fi
    
    # 获取IP地址
    local local_ip=""
    if command -v ip >/dev/null 2>&1; then
        local_ip=$(ip route get 1 | awk '{print $7}' | head -1)
    elif command -v hostname >/dev/null 2>&1; then
        local_ip=$(hostname -I | awk '{print $1}')
    else
        local_ip="localhost"
    fi
    
    local public_ip=""
    if command -v curl >/dev/null 2>&1; then
        public_ip=$(curl -s --connect-timeout 5 ifconfig.me || echo "无法获取")
    else
        public_ip="需要安装curl获取"
    fi
    
    log_info "✓ 安装完成！"
    
    if [[ "$SSL_ENABLED" == "true" ]]; then
        log_info "访问地址: https://${local_ip}:${NOVNC_PORT}/vnc.html"
        if [ "$public_ip" != "无法获取" ] && [ "$public_ip" != "需要安装curl获取" ]; then
            log_info "或: https://${public_ip}:${NOVNC_PORT}/vnc.html (公网IP)"
        fi
        log_warn "注意: 使用自签名证书时浏览器会显示安全警告，这是正常的"
    else
        log_info "访问地址: http://${local_ip}:${NOVNC_PORT}/vnc.html"
        if [ "$public_ip" != "无法获取" ] && [ "$public_ip" != "需要安装curl获取" ]; then
            log_info "或: http://${public_ip}:${NOVNC_PORT}/vnc.html (公网IP)"
        fi
        log_warn "注意: 当前使用未加密的HTTP连接"
    fi
    
    # 显示证书信息
    if [[ "$SSL_ENABLED" == "true" && -f "$SSL_CERT" ]]; then
        echo
        log_info "证书信息:"
        openssl x509 -in "$SSL_CERT" -noout -subject -dates 2>/dev/null || log_warn "无法显示证书详情"
    fi
    
    # 显示服务管理命令
    echo
    log_info "服务管理命令:"
    log_info "启动服务: systemctl start novnc"
    log_info "停止服务: systemctl stop novnc"
    log_info "重启服务: systemctl restart novnc"
    log_info "查看状态: systemctl status novnc"
    log_info "查看日志: journalctl -u novnc -f"
    
    if [[ "$ENABLE_AUTOSTART" != "yes" ]]; then
        log_info "提示: 开机自启动未启用"
    fi
    
    if [[ "$VNC_RUNNING" == "false" ]]; then
        echo
        log_warn "⚠️  重要提示: VNC服务未在端口 ${VNC_PORT} 运行"
        log_warn "请启动VNC服务后，noVNC才能正常使用"
    fi
}

# 检查现有安装
check_existing_installation() {
    if systemctl list-unit-files | grep -q novnc; then
        log_warn "检测到已存在的noVNC安装，停止并禁用服务..."
        systemctl stop novnc 2>/dev/null || true
        systemctl disable novnc 2>/dev/null || true
        rm -f /etc/systemd/system/novnc.service
        systemctl daemon-reload
        sleep 2
    fi
}

# 主函数
main() {
    show_banner
    parse_arguments "$@"
    check_root
    detect_os
    detect_network_tools
    
    log_info "开始自动安装noVNC..."
    
    # 初始化变量
    SSL_CERT=""
    SSL_KEY=""
    VNC_RUNNING=false
    
    check_existing_installation
    
    # 验证端口号
    if ! [[ "$VNC_PORT" =~ ^[0-9]+$ ]] || [[ "$VNC_PORT" -lt 1 || "$VNC_PORT" -gt 65535 ]]; then
        log_error "无效的VNC端口号: $VNC_PORT"
        exit 1
    fi
    
    if ! [[ "$NOVNC_PORT" =~ ^[0-9]+$ ]] || [[ "$NOVNC_PORT" -lt 1 || "$NOVNC_PORT" -gt 65535 ]]; then
        log_error "无效的noVNC端口号: $NOVNC_PORT"
        exit 1
    fi
    
    check_vnc_service
    install_dependencies
    setup_ssl_certificate
    setup_novnc_service
    enable_autostart
    check_firewall
    verify_installation
}

# 脚本入口
main "$@"