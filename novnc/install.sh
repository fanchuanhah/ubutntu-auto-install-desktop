#!/bin/bash
set -e

# ========== 默认配置 ==========
DEFAULT_UPDATE="t"          # 默认更新软件源
DEFAULT_VNC_PORT="5901"     # 默认VNC端口
DEFAULT_NOVNC_PORT="6080"   # 默认noVNC端口
DEFAULT_SSL="t"             # 默认启用SSL
DEFAULT_ENABLE="t"          # 默认开机自启动
DEFAULT_AUTO="false"        # 默认非自动模式

# ========== 颜色定义 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ========== 全局变量 ==========
UPDATE="$DEFAULT_UPDATE"
VNC_PORT="$DEFAULT_VNC_PORT"
NOVNC_PORT="$DEFAULT_NOVNC_PORT"
SSL="$DEFAULT_SSL"
ENABLE="$DEFAULT_ENABLE"
AUTO_MODE="$DEFAULT_AUTO"

# 其他全局变量
OS=""
OS_VERSION=""
OS_ID=""
PKG_MANAGER=""
PKG_INSTALL=""
PKG_UPDATE=""
NETSTAT_CMD=""
VNC_RUNNING=false
SSL_ENABLED=true
SSL_CERT=""
SSL_KEY=""

# ========== 日志函数 ==========
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

# ========== 解析命令行参数 ==========
parse_arguments() {
    for arg in "$@"; do
        case $arg in
            -auto)
                AUTO_MODE="true"
                shift
                ;;
            -update=*)
                UPDATE="${arg#*=}"
                shift
                ;;
            -vncport=*)
                VNC_PORT="${arg#*=}"
                shift
                ;;
            -novncport=*)
                NOVNC_PORT="${arg#*=}"
                shift
                ;;
            -ssl=*)
                SSL="${arg#*=}"
                shift
                ;;
            -enable=*)
                ENABLE="${arg#*=}"
                shift
                ;;
        esac
    done
    
    # 只有在自动模式下才使用参数，否则使用默认值或交互式输入
    if [[ "$AUTO_MODE" != "true" ]]; then
        UPDATE="$DEFAULT_UPDATE"
        VNC_PORT="$DEFAULT_VNC_PORT"
        NOVNC_PORT="$DEFAULT_NOVNC_PORT"
        SSL="$DEFAULT_SSL"
        ENABLE="$DEFAULT_ENABLE"
    fi
}

# ========== 检测系统类型 ==========
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

# ========== 检查root权限 ==========
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用sudo运行此脚本"
        exit 1
    fi
}

# ========== 显示横幅 ==========
show_banner() {
    echo "=========================================="
    echo "  noVNC 一键安装脚本 (多系统适配版)"
    echo "=========================================="
    if [[ "$AUTO_MODE" == "true" ]]; then
        echo "           [自动模式]"
        echo "  更新软件源: $UPDATE"
        echo "  VNC端口: $VNC_PORT"
        echo "  noVNC端口: $NOVNC_PORT"
        echo "  SSL加密: $SSL"
        echo "  开机自启: $ENABLE"
        echo "=========================================="
    fi
}

# ========== 检测网络工具 ==========
detect_network_tools() {
    if command -v netstat >/dev/null 2>&1; then
        NETSTAT_CMD="netstat -tlnp"
    elif command -v ss >/dev/null 2>&1; then
        NETSTAT_CMD="ss -tlnp"
    else
        log_warn "未找到netstat或ss命令，将安装网络工具..."
        $PKG_INSTALL net-tools 2>/dev/null || $PKG_INSTALL iproute2 2>/dev/null || true
        if command -v netstat >/dev/null 2>&1; then
            NETSTAT_CMD="netstat -tlnp"
        else
            NETSTAT_CMD="ss -tlnp"
        fi
    fi
}

# ========== 检测VNC端口 ==========
detect_vnc_port() {
    log_info "检测VNC服务端口..."
    
    if [[ "$AUTO_MODE" == "true" ]]; then
        log_info "自动模式使用指定VNC端口: $VNC_PORT"
        return
    fi
    
    # 使用检测到的网络工具
    local detected_ports=$($NETSTAT_CMD 2>/dev/null | grep -E "(vnc|Xvnc|tightvnc|tigervnc)" | grep -E ":([0-9]+)" | awk '{print $4}' | awk -F: '{print $NF}' | sort -u)
    
    if [[ -n "$detected_ports" ]]; then
        log_info "检测到VNC服务在以下端口运行:"
        echo "$detected_ports"
        log_warn "是否使用检测到的端口? (Y/n)"
        read -r use_detected
        case "$use_detected" in
            [nN][oO]|[nN])
                VNC_PORT=""
                ;;
            *)
                VNC_PORT=$(echo "$detected_ports" | head -1)
                log_info "使用检测到的VNC端口: $VNC_PORT"
                return
                ;;
        esac
    fi
    
    # 手动输入端口
    log_warn "请输入VNC服务端口 (默认: $DEFAULT_VNC_PORT)"
    read -r custom_port
    if [[ -n "$custom_port" ]]; then
        VNC_PORT="$custom_port"
    else
        VNC_PORT="$DEFAULT_VNC_PORT"
    fi
    
    # 验证端口格式
    if ! [[ "$VNC_PORT" =~ ^[0-9]+$ ]] || [[ "$VNC_PORT" -lt 1 || "$VNC_PORT" -gt 65535 ]]; then
        log_error "无效的端口号: $VNC_PORT"
        exit 1
    fi
    
    log_info "使用VNC端口: $VNC_PORT"
}

# ========== 检查VNC服务状态 ==========
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

# ========== 安装依赖 ==========
install_dependencies() {
    log_info "安装系统依赖..."
    
    # 根据参数决定是否更新软件源
    if [[ "$UPDATE" == "t" ]]; then
        $PKG_UPDATE
    else
        log_info "跳过软件源更新"
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
            log_error "未找到pip，无法安装websockify"
            exit 1
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

# ========== 设置SSL证书 ==========
setup_ssl_certificate() {
    log_info "配置SSL证书..."
    
    # 根据参数决定是否启用SSL
    if [[ "$SSL" != "t" ]]; then
        log_info "禁用SSL加密（根据参数设置）"
        SSL_ENABLED=false
        return
    fi
    
    local ssl_dir="/etc/novnc/ssl"
    mkdir -p "$ssl_dir"
    
    if [[ "$AUTO_MODE" == "true" ]]; then
        # 自动模式：默认生成自签名证书
        log_info "自动模式：生成自签名SSL证书..."
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
        else
            log_error "证书生成失败，将禁用SSL"
            SSL_ENABLED=false
        fi
        return
    fi
    
    # 交互式模式
    log_warn "是否生成自签名SSL证书? (y/N)"
    read -r ssl_response
    case "$ssl_response" in
        [yY][eE][sS]|[yY])
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
            else
                log_error "证书生成失败，将禁用SSL"
                SSL_ENABLED=false
            fi
            ;;
        *)
            log_warn "使用现有证书还是禁用SSL?"
            log_warn "1. 使用现有证书"
            log_warn "2. 禁用SSL"
            read -r ssl_choice
            case "$ssl_choice" in
                1)
                    log_info "请提供证书路径:"
                    read -p "证书文件路径: " cert_path
                    read -p "私钥文件路径: " key_path
                    if [[ -f "$cert_path" && -f "$key_path" ]]; then
                        cp "$cert_path" "$ssl_dir/novnc.crt"
                        cp "$key_path" "$ssl_dir/novnc.key"
                        chmod 600 "$ssl_dir/novnc.key"
                        chmod 644 "$ssl_dir/novnc.crt"
                        SSL_CERT="$ssl_dir/novnc.crt"
                        SSL_KEY="$ssl_dir/novnc.key"
                        log_info "✓ 证书已复制到 $SSL_CERT"
                    else
                        log_error "证书文件不存在，将禁用SSL"
                        SSL_ENABLED=false
                    fi
                    ;;
                *)
                    log_info "禁用SSL加密"
                    SSL_ENABLED=false
                    ;;
            esac
            ;;
    esac
}

# ========== 设置noVNC服务 ==========
setup_novnc_service() {
    log_info "配置noVNC系统服务..."
    
    # 检查端口占用
    if $NETSTAT_CMD 2>/dev/null | grep -q ":${NOVNC_PORT}[^0-9]"; then
        if [[ "$AUTO_MODE" == "true" ]]; then
            log_error "端口 $NOVNC_PORT 已被占用，自动模式中止"
            exit 1
        else
            log_warn "端口 $NOVNC_PORT 已被占用，请选择:"
            log_warn "1. 强制使用此端口（可能冲突）"
            log_warn "2. 更换其他端口"
            read -r port_choice
            
            case "$port_choice" in
                1)
                    log_warn "强制使用端口 $NOVNC_PORT，可能与其他服务冲突"
                    ;;
                2)
                    log_warn "请输入新的noVNC端口:"
                    read -r new_port
                    if [[ -n "$new_port" ]] && [[ "$new_port" =~ ^[0-9]+$ ]] && [[ "$new_port" -ge 1 ]] && [[ "$new_port" -le 65535 ]]; then
                        NOVNC_PORT="$new_port"
                        log_info "使用新端口: $NOVNC_PORT"
                    else
                        log_error "无效的端口号"
                        exit 1
                    fi
                    ;;
                *)
                    log_error "无效选择"
                    exit 1
                    ;;
            esac
        fi
    fi
    
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
    if [[ "$SSL_ENABLED" != "false" && -n "$SSL_CERT" && -n "$SSL_KEY" ]]; then
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

# ========== 启用自启动 ==========
enable_autostart() {
    log_info "配置开机自启动..."
    systemctl daemon-reload
    
    if [[ "$ENABLE" == "t" ]]; then
        systemctl enable novnc
        systemctl start novnc
        log_info "✓ noVNC服务已设置为开机自启动"
    else
        systemctl disable novnc 2>/dev/null || true
        log_info "✓ noVNC服务开机自启动已禁用"
    fi
}

# ========== 检查防火墙 ==========
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
    
    if [[ "$SSL_ENABLED" != "false" ]]; then
        log_warn "当前配置使用SSL加密连接"
    else
        log_warn "当前配置使用普通HTTP连接（未加密）"
    fi
    
    if [[ "$VNC_RUNNING" == "false" ]]; then
        log_warn "⚠️  当前VNC服务未运行，请确保VNC服务在端口 ${VNC_PORT} 启动"
    fi
    log_warn "================="
}

# ========== 验证安装 ==========
verify_installation() {
    log_info "验证安装..."
    sleep 3
    
    if [[ "$ENABLE" == "t" ]]; then
        if systemctl is-active --quiet novnc; then
            log_info "✓ noVNC服务运行正常"
        else
            log_error "noVNC服务启动失败"
            systemctl status novnc
            exit 1
        fi
        
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
    
    # 获取内网IP地址
    local local_ip=""
    if command -v ip >/dev/null 2>&1; then
        # 尝试获取内网IP（优先获取eth0或ens33等网络接口）
        local_ip=$(ip addr show | grep -E "inet (192\.168|10\.|172\.(1[6-9]|2[0-9]|3[0-1]))" | grep -v "127.0.0.1" | head -1 | awk '{print $2}' | cut -d/ -f1)
        if [ -z "$local_ip" ]; then
            local_ip=$(ip route get 1 | awk '{print $7}' | head -1)
        fi
    elif command -v hostname >/dev/null 2>&1; then
        local_ip=$(hostname -I | awk '{print $1}')
    else
        local_ip="localhost"
    fi
    
    # 获取公网IP地址
    local public_ip=""
    if command -v curl >/dev/null 2>&1; then
        # 尝试多个公网IP查询服务
        public_ip=$(curl -s --connect-timeout 3 ifconfig.me 2>/dev/null || \
                    curl -s --connect-timeout 3 ipinfo.io/ip 2>/dev/null || \
                    curl -s --connect-timeout 3 icanhazip.com 2>/dev/null || \
                    echo "无法获取")
    else
        public_ip="需要安装curl获取"
    fi
    
    log_info "✓ 安装完成！"
    
    echo "=========================================="
    log_info "连接信息："
    echo "------------------------------------------"
    
    # 显示内网IP访问地址
    if [[ "$SSL_ENABLED" != "false" ]]; then
        log_info "内网访问: https://${local_ip}:${NOVNC_PORT}/vnc.html"
        if [ "$public_ip" != "无法获取" ] && [ "$public_ip" != "需要安装curl获取" ]; then
            log_info "公网访问: https://${public_ip}:${NOVNC_PORT}/vnc.html"
        fi
        log_warn "注意: 使用自签名证书时浏览器会显示安全警告，这是正常的"
    else
        log_info "内网访问: http://${local_ip}:${NOVNC_PORT}/vnc.html"
        if [ "$public_ip" != "无法获取" ] && [ "$public_ip" != "需要安装curl获取" ]; then
            log_info "公网访问: http://${public_ip}:${NOVNC_PORT}/vnc.html"
        fi
        log_warn "注意: 当前使用未加密的HTTP连接"
    fi
    
    # 显示IP地址详情
    echo "------------------------------------------"
    log_info "IP地址信息："
    log_info "内网IP: ${local_ip}"
    if [ "$public_ip" != "无法获取" ] && [ "$public_ip" != "需要安装curl获取" ]; then
        log_info "公网IP: ${public_ip}"
    else
        log_warn "公网IP: ${public_ip}"
    fi
    echo "=========================================="
    
    # 显示证书信息
    if [[ "$SSL_ENABLED" != "false" && -f "$SSL_CERT" ]]; then
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
    
    if [[ "$VNC_RUNNING" == "false" ]]; then
        echo
        log_warn "⚠️  重要提示: VNC服务未在端口 ${VNC_PORT} 运行"
        log_warn "请启动VNC服务后，noVNC才能正常使用"
    fi
}
# ========== 检查现有安装 ==========
check_existing_installation() {
    if systemctl list-unit-files | grep -q novnc; then
        if [[ "$AUTO_MODE" == "true" ]]; then
            log_info "自动模式：停止现有服务并重新安装..."
            systemctl stop novnc 2>/dev/null || true
            systemctl disable novnc 2>/dev/null || true
            rm -f /etc/systemd/system/novnc.service
            systemctl daemon-reload
        else
            log_warn "检测到已存在的noVNC安装"
            log_warn "是否重新安装? (y/N)"
            read -r reinstall
            case "$reinstall" in
                [yY][eE][sS]|[yY])
                    log_info "停止现有服务..."
                    systemctl stop novnc 2>/dev/null || true
                    systemctl disable novnc 2>/dev/null || true
                    rm -f /etc/systemd/system/novnc.service
                    systemctl daemon-reload
                    ;;
                *)
                    log_info "退出安装"
                    exit 0
                    ;;
            esac
        fi
    fi
}

# ========== 主函数 ==========
main() {
    parse_arguments "$@"
    show_banner
    check_root
    detect_os
    detect_network_tools
    
    if [[ "$AUTO_MODE" != "true" ]]; then
        log_warn "此操作将安装noVNC并设置开机自启动，是否继续? (y/N)"
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY])
                echo "开始安装..."
                ;;
            *)
                log_info "取消安装"
                exit 0
                ;;
        esac
    fi
    
    check_existing_installation
    detect_vnc_port
    check_vnc_service
    install_dependencies
    setup_ssl_certificate
    setup_novnc_service
    enable_autostart
    check_firewall
    verify_installation
}

# ========== 脚本入口 ==========
main "$@"