#!/bin/bash
# proxy/anytls-go.sh - AnyTLS-go 服务端安装管理脚本
# 版本: v0.0.12

# ============================================
# 颜色输出
# ============================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================
# 日志函数
# ============================================
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================
# 通用函数
# ============================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请以 root 身份运行此脚本"
        exit 1
    fi
}

gen_password() {
    openssl rand -hex 16
}

get_public_ip() {
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -z "$ip" ]]; then
        ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
    fi
    echo "$ip"
}

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        i386|i686) echo "386" ;;
        *)       echo "$arch" ;;
    esac
}

random_cdn_domain() {
    local domains=("update.microsoft.com" "assets.msn.com")
    echo "${domains[$RANDOM % ${#domains[@]}]}"
}

# ============================================
# 配置变量
# ============================================
ANYTLS_VERSION="v0.0.12"
ANYTLS_BIN="/usr/local/bin/anytls-server"
ANYTLS_CONFIG_DIR="/etc/anytls"
ANYTLS_PADDING_FILE="$ANYTLS_CONFIG_DIR/padding.txt"
ANYTLS_SERVICE_FILE="/etc/systemd/system/anytls-server.service"
ANYTLS_DOWNLOAD_BASE="https://github.com/anytls/anytls-go/releases/download/v0.0.12"

# ============================================
# 默认 PaddingScheme
# ============================================
generate_padding_scheme() {
    mkdir -p "$ANYTLS_CONFIG_DIR"
    cat > "$ANYTLS_PADDING_FILE" << 'PADDINGEOF'
stop=8
0=30-30
1=100-400
2=400-500,c,500-1000,c,500-1000,c,500-1000,c,500-1000
3=9-9,500-1000
4=500-1000
5=500-1000
6=500-1000
7=500-1000
PADDINGEOF
    log_success "PaddingScheme 已生成: $ANYTLS_PADDING_FILE"
}

# ============================================
# 检查是否已安装
# ============================================
is_installed() {
    [[ -f "$ANYTLS_BIN" ]]
}

# ============================================
# 安装 AnyTLS-go 服务端
# ============================================
install_anytls() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  安装 AnyTLS-go 服务端${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""

    # 端口
    read -r -p "请输入监听端口 [默认: 8443]: " port
    port=${port:-8443}

    # 密码
    echo ""
    echo "请选择密码方式:"
    echo "  1. 自动生成随机密码（推荐）"
    echo "  2. 手动输入密码"
    read -r -p "请选择 [1-2]: " pwd_choice
    case "$pwd_choice" in
        2)
            read -r -p "请输入密码: " password
            while [[ -z "$password" ]]; do
                log_error "密码不能为空"
                read -r -p "请输入密码: " password
            done
            ;;
        *)
            password=$(gen_password)
            echo -e "${GREEN}生成的密码: $password${NC}"
            ;;
    esac

    # PaddingScheme
    echo ""
    read -r -p "是否安装内置默认 PaddingScheme？[Y/n]: " padding_choice
    padding_choice=${padding_choice:-Y}

    # 确认
    echo ""
    echo "确认安装："
    echo "  端口: $port"
    echo "  密码: $password"
    if [[ "$padding_choice" =~ ^[Yy]$ ]]; then
        echo "  PaddingScheme: 是"
    else
        echo "  PaddingScheme: 否"
    fi
    read -r -p "继续安装？[Y/n]: " confirm
    confirm=${confirm:-Y}
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "安装已取消"
        return
    fi

    echo ""

    # 检测架构
    local arch
    arch=$(detect_arch)
    log_info "检测系统架构... $arch"

    # 下载
    local zip_file="anytls_0.0.12_linux_${arch}.zip"
    local download_url="$ANYTLS_DOWNLOAD_BASE/$zip_file"
    log_info "下载 AnyTLS-go $ANYTLS_VERSION..."
    if ! wget -q --show-progress "$download_url" -O "$zip_file"; then
        log_error "下载失败: $download_url"
        exit 1
    fi

    # 解压
    log_info "解压中..."
    if ! unzip -o "$zip_file"; then
        log_error "解压失败"
        exit 1
    fi

    # 安装
    log_info "安装 anytls-server 到 /usr/local/bin/..."
    mv anytls-server "$ANYTLS_BIN"
    chmod +x "$ANYTLS_BIN"

    # 清理垃圾文件
    rm -f anytls-client readme.md "$zip_file"
    log_info "已清理临时文件"

    # PaddingScheme
    if [[ "$padding_choice" =~ ^[Yy]$ ]]; then
        generate_padding_scheme
    fi

    # 生成 systemd 服务
    log_info "创建 systemd 服务..."
    local exec_start="$ANYTLS_BIN -l 0.0.0.0:$port -p $password"
    if [[ -f "$ANYTLS_PADDING_FILE" ]]; then
        exec_start="$exec_start --padding-scheme $ANYTLS_PADDING_FILE"
    fi

    cat > "$ANYTLS_SERVICE_FILE" << SERVICEEOF
[Unit]
Description=AnyTLS-go Server v0.0.12
After=network.target

[Service]
Type=simple
ExecStart=$exec_start
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SERVICEEOF

    # 启动服务
    log_info "启动服务..."
    systemctl daemon-reload
    systemctl enable --now anytls-server

    # 检查状态
    if systemctl is-active --quiet anytls-server; then
        log_success "AnyTLS-go 服务端安装完成！"
    else
        log_error "服务启动失败，请检查日志: journalctl -u anytls-server -n 50"
        return
    fi

    # 输出客户端信息
    local server_ip
    server_ip=$(get_public_ip)
    local sni
    sni=$(random_cdn_domain)

    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  客户端连接信息${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo "  服务器 IP: $server_ip"
    echo "  端口: $port"
    echo "  密码: $password"
    echo ""
    echo "  URI格式:"
    echo "    anytls://${password}@${server_ip}:${port}/?insecure=1"
    echo ""
    echo "  mihomo 配置:"
    echo "    proxies:"
    echo "      - name: anytls"
    echo "        type: anytls"
    echo "        server: $server_ip"
    echo "        port: $port"
    echo "        password: \"$password\""
    echo "        client-fingerprint: chrome"
    echo "        udp: true"
    echo "        idle-session-check-interval: 30"
    echo "        idle-session-timeout: 30"
    echo "        min-idle-session: 0"
    echo "        sni: \"$sni\""
    echo "        alpn:"
    echo "          - h2"
    echo "          - http/1.1"
    echo "        skip-cert-verify: true"
    echo -e "${CYAN}=========================================${NC}"
    echo ""
    read -r -p "按 Enter 键返回主菜单..."
}

# ============================================
# 查看状态
# ============================================
show_status() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  AnyTLS-go 服务状态${NC}"
    echo -e "${CYAN}=========================================${NC}"

    if ! is_installed; then
        echo -e "  运行状态: ${YELLOW}未安装${NC}"
        echo ""
        read -r -p "按 Enter 键返回主菜单..."
        return
    fi

    # 运行状态
    if systemctl is-active --quiet anytls-server; then
        local pid
        pid=$(systemctl show -p MainPID anytls-server 2>/dev/null | cut -d= -f2)
        echo -e "  运行状态: ${GREEN}运行中${NC} (PID: ${pid:-N/A})"
    else
        echo -e "  运行状态: ${RED}已停止${NC}"
    fi

    # 监听地址
    local listen_info
    listen_info=$(systemctl show -p ExecStart anytls-server 2>/dev/null | grep -oP '\-l\s+\S+' | head -1)
    echo "  监听地址: ${listen_info:-未知}"

    # 内存占用
    if systemctl is-active --quiet anytls-server; then
        local mem
        mem=$(ps -o rss= -p "$(systemctl show -p MainPID anytls-server 2>/dev/null | cut -d= -f2)" 2>/dev/null)
        mem=$((mem / 1024))
        echo "  内存占用: ${mem:-N/A} MB"
    fi

    # 开机自启
    if systemctl is-enabled --quiet anytls-server 2>/dev/null; then
        echo -e "  开机自启: ${GREEN}已启用${NC}"
    else
        echo -e "  开机自启: ${RED}未启用${NC}"
    fi

    echo ""
    echo "  服务文件: $ANYTLS_SERVICE_FILE"
    echo "  配置文件: $ANYTLS_PADDING_FILE"
    echo "  二进制:   $ANYTLS_BIN"
    echo -e "${CYAN}=========================================${NC}"
    echo ""
    read -r -p "按 Enter 键返回主菜单..."
}

# ============================================
# 卸载
# ============================================
uninstall_anytls() {
    echo ""
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}  卸载 AnyTLS-go 服务端${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo ""
    echo "将执行以下操作:"
    echo "  - 停止并禁用 systemd 服务"
    echo "  - 删除 $ANYTLS_BIN"
    echo "  - 删除 $ANYTLS_CONFIG_DIR/"
    echo "  - 删除 $ANYTLS_SERVICE_FILE"
    echo ""
    read -r -p "确认卸载？[y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "卸载已取消"
        return
    fi

    echo ""

    if systemctl is-active --quiet anytls-server 2>/dev/null; then
        log_info "停止服务..."
        systemctl stop anytls-server
    fi

    if systemctl is-enabled --quiet anytls-server 2>/dev/null; then
        log_info "禁用开机自启..."
        systemctl disable anytls-server
    fi

    log_info "删除服务文件..."
    rm -f "$ANYTLS_SERVICE_FILE"
    systemctl daemon-reload

    log_info "删除二进制文件..."
    rm -f "$ANYTLS_BIN"

    log_info "删除配置目录..."
    rm -rf "$ANYTLS_CONFIG_DIR"

    log_success "卸载完成！"
    echo ""
    read -r -p "按 Enter 键返回主菜单..."
}

# ============================================
# 修改密码
# ============================================
change_password() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  修改密码${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""

    if ! is_installed; then
        log_error "AnyTLS-go 未安装，请先安装"
        read -r -p "按 Enter 键返回主菜单..."
        return
    fi

    # 显示当前密码
    local current_password
    current_password=$(systemctl show -p ExecStart anytls-server 2>/dev/null | grep -oP '\-p\s+\S+' | head -1 | sed 's/-p //')
    echo "当前密码: $current_password"
    echo ""

    # 新密码
    echo "请选择新密码方式:"
    echo "  1. 自动生成随机密码（推荐）"
    echo "  2. 手动输入密码"
    read -r -p "请选择 [1-2]: " pwd_choice
    local new_password
    case "$pwd_choice" in
        2)
            read -r -p "请输入新密码: " new_password
            while [[ -z "$new_password" ]]; do
                log_error "密码不能为空"
                read -r -p "请输入新密码: " new_password
            done
            ;;
        *)
            new_password=$(gen_password)
            echo -e "${GREEN}新密码: $new_password${NC}"
            ;;
    esac

    echo ""

    # 读取原服务文件，替换密码
    log_info "更新 systemd 服务文件..."
    local old_exec
    old_exec=$(grep '^ExecStart=' "$ANYTLS_SERVICE_FILE")
    local new_exec
    new_exec=$(echo "$old_exec" | sed "s/-p [^ ]*/-p $new_password/")
    sed -i "s|^ExecStart=.*|$new_exec|" "$ANYTLS_SERVICE_FILE"

    systemctl daemon-reload

    log_info "重启 anytls-server 服务..."
    systemctl restart anytls-server

    if systemctl is-active --quiet anytls-server; then
        log_success "密码已更新！"
    else
        log_error "服务重启失败，请检查日志: journalctl -u anytls-server -n 50"
    fi

    echo ""
    read -r -p "按 Enter 键返回主菜单..."
}

# ============================================
# 主菜单
# ============================================
main_menu() {
    while true; do
        clear
        echo ""
        echo -e "${CYAN}=========================================${NC}"
        echo -e "${CYAN}     AnyTLS-go 服务端安装管理脚本${NC}"
        echo -e "${CYAN}     v0.0.12${NC}"
        echo -e "${CYAN}=========================================${NC}"
        echo ""
        echo "  1. 安装 AnyTLS-go 服务端"
        echo "  2. 查看当前配置与状态"
        echo "  3. 卸载 AnyTLS-go 服务端"
        echo "  4. 修改密码"
        echo "  5. 退出"
        echo ""
        read -r -p "请选择 [1-5]: " choice
        case "$choice" in
            1) install_anytls ;;
            2) show_status ;;
            3) uninstall_anytls ;;
            4) change_password ;;
            5) echo ""; exit 0 ;;
            *) read -r -p "无效选择，按 Enter 键继续..." ;;
        esac
    done
}

# ============================================
# 入口
# ============================================
check_root
main_menu
