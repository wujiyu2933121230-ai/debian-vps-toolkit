#!/bin/bash
# proxy/hysteria2.sh - Hysteria 2 服务端安装管理脚本
# 版本: v1.0.0

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
    local chars='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local pass=""
    for _ in $(seq 1 16); do
        pass="${pass}${chars:$((RANDOM % ${#chars})):1}"
    done
    echo "$pass"
}

detect_avx() {
    if grep -q ' avx ' /proc/cpuinfo 2>/dev/null; then
        return 0
    fi
    return 1
}

random_masquerade_domain() {
    local domains=("update.microsoft.com" "assets.msn.com")
    echo "${domains[$RANDOM % ${#domains[@]}]}"
}

check_port_used() {
    local port=$1
    if ss -tuln 2>/dev/null | grep -q ":$port "; then
        return 0
    fi
    return 1
}

get_fingerprint() {
    local cert_path=$1
    openssl x509 -noout -fingerprint -sha256 -inform pem -in "$cert_path" 2>/dev/null | cut -d= -f2
}

# ============================================
# 配置变量
# ============================================
HY2_BIN="/usr/local/bin/hysteria"
HY2_CONFIG_DIR="/etc/hysteria"
HY2_CERT="$HY2_CONFIG_DIR/cert.pem"
HY2_KEY="$HY2_CONFIG_DIR/key.pem"
HY2_CONFIG="$HY2_CONFIG_DIR/config.yaml"
HY2_SERVICE_FILE="/etc/systemd/system/hysteria-server.service"
HY2_DOWNLOAD_BASE="https://download.hysteria.network/app/latest"

# ============================================
# 检查是否已安装
# ============================================
is_installed() {
    [[ -f "$HY2_BIN" ]]
}
# ============================================
# 安装 Hysteria 2 服务端
# ============================================
install_hysteria2() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  安装 Hysteria 2 服务端${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""

    # ---- 步骤 1: 检测系统环境 ----
    log_info "检测系统环境..."
    if ! grep -qi 'debian' /etc/os-release 2>/dev/null; then
        log_error "仅支持 Debian 系统"
        exit 1
    fi
    log_info "安装依赖: openssl, curl, wget, iptables..."
    apt update -qq
    apt install -y -qq openssl curl wget iptables 2>/dev/null

    # ---- 步骤 2: 输入服务器 IP ----
    echo ""
    local server_ip
    read -r -p "请输入服务器公网 IP: " server_ip
    while [[ -z "$server_ip" ]]; do
        log_error "IP 不能为空"
        read -r -p "请输入服务器公网 IP: " server_ip
    done

    # ---- 步骤 3: 交互式输入参数 ----
    echo ""
    echo -e "${CYAN}--- 配置参数 ---${NC}"

    # 密码
    local password
    echo ""
    echo "服务端密码:"
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
            echo -e "  生成的密码: ${GREEN}$password${NC}"
            ;;
    esac

    # 监听端口
    read -r -p "请输入监听端口 [默认: 9443]: " port
    port=${port:-9443}
    if check_port_used "$port"; then
        log_error "端口 $port 已被占用"
        exit 1
    fi

    # 端口跳跃范围
    read -r -p "请输入端口跳跃范围 [默认: 25000-26000]: " hop_range
    hop_range=${hop_range:-25000-26000}

    # 混淆密码
    local obfs_password
    echo ""
    echo "混淆密码 (salamander):"
    echo "  1. 自动生成随机密码（推荐）"
    echo "  2. 手动输入密码"
    read -r -p "请选择 [1-2]: " obfs_choice
    case "$obfs_choice" in
        2)
            read -r -p "请输入混淆密码: " obfs_password
            while [[ -z "$obfs_password" ]]; do
                log_error "混淆密码不能为空"
                read -r -p "请输入混淆密码: " obfs_password
            done
            ;;
        *)
            obfs_password=$(gen_password)
            echo -e "  生成的混淆密码: ${GREEN}$obfs_password${NC}"
            ;;
    esac

    # 确认
    echo ""
    echo "确认安装："
    echo "  服务器 IP:   $server_ip"
    echo "  监听端口:    $port"
    echo "  端口跳跃:    $hop_range"
    echo "  密码:        $password"
    echo "  混淆密码:    $obfs_password"
    read -r -p "继续安装？[Y/n]: " confirm
    confirm=${confirm:-Y}
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "安装已取消"
        return
    fi

    # ---- 步骤 4: 检测 AVX 并下载二进制 ----
    echo ""
    log_info "检测 CPU 指令集..."
    local arch_suffix=""
    if detect_avx; then
        log_info "CPU 支持 AVX，下载 AVX 优化版本"
        arch_suffix="-avx"
    else
        log_info "CPU 不支持 AVX，下载普通版本"
    fi

    local download_url="${HY2_DOWNLOAD_BASE}/hysteria-linux-amd64${arch_suffix}"
    log_info "下载 Hysteria 2..."
    log_info "下载地址: $download_url"
    if ! wget -q --show-progress "$download_url" -O /tmp/hysteria; then
        log_error "下载失败"
        exit 1
    fi

    log_info "安装到 $HY2_BIN..."
    mv /tmp/hysteria "$HY2_BIN"
    chmod +x "$HY2_BIN"

    # ---- 步骤 5: 随机选择伪装域名 ----
    local masquerade_domain
    masquerade_domain=$(random_masquerade_domain)
    log_info "伪装域名: $masquerade_domain"

    # ---- 步骤 6: 生成自签名证书 ----
    log_info "生成自签名证书..."
    mkdir -p "$HY2_CONFIG_DIR"
    openssl req -x509 -newkey rsa:2048 -keyout "$HY2_KEY" -out "$HY2_CERT" -days 36500 \
        -nodes -subj "/CN=$masquerade_domain" 2>/dev/null
    log_success "证书已生成 (有效期 100 年)"

    # 提取指纹
    local fingerprint
    fingerprint=$(get_fingerprint "$HY2_CERT")
    log_info "证书指纹 (SHA-256): $fingerprint"

    # ---- 步骤 7: 生成服务端 config.yaml ----
    log_info "生成服务端配置..."
    cat > "$HY2_CONFIG" << YAMLEOF
listen: :${port}

tls:
  cert: ${HY2_CERT}
  key: ${HY2_KEY}

auth:
  type: password
  password: ${password}

masquerade:
  type: proxy
  proxy:
    url: https://${masquerade_domain}/
    rewriteHost: true

congestion:
  type: bbr

obfs:
  type: salamander
  salamander:
    password: ${obfs_password}
YAMLEOF
    log_success "配置已生成: $HY2_CONFIG"

    # ---- 步骤 8: 配置端口跳跃 iptables DNAT ----
    log_info "配置端口跳跃 iptables 规则..."

    local hop_start
    local hop_end
    hop_start=${hop_range%-*}
    hop_end=${hop_range#*-}

    # IPv4
    iptables -t nat -A PREROUTING -p udp --dport "$hop_start:$hop_end" -j DNAT --to-destination ":$port"
    # IPv6
    ip6tables -t nat -A PREROUTING -p udp --dport "$hop_start:$hop_end" -j DNAT --to-destination ":$port" 2>/dev/null || true

    # 持久化
    log_info "持久化 iptables 规则..."
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
    ip6tables-save > /etc/iptables/rules.v6 2>/dev/null

    log_success "端口跳跃规则已配置: $hop_range -> :$port"

    # ---- 步骤 9: 创建 systemd 服务 ----
    log_info "创建 systemd 服务..."
    cat > "$HY2_SERVICE_FILE" << SERVICEEOF
[Unit]
Description=Hysteria 2 Server
After=network.target

[Service]
Type=simple
ExecStart=${HY2_BIN} server -c ${HY2_CONFIG}
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SERVICEEOF

    log_info "启动服务..."
    systemctl daemon-reload
    systemctl enable --now hysteria-server

    # 检查状态
    sleep 2
    if systemctl is-active --quiet hysteria-server; then
        log_success "Hysteria 2 服务端安装完成！"
    else
        log_error "服务启动失败，请检查日志: journalctl -u hysteria-server -n 50"
        read -r -p "按 Enter 键返回主菜单..."
        return
    fi

    # ---- 步骤 10: 输出客户端配置 ----
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  Hysteria 2 服务端安装完成！${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""
    echo "服务端信息:"
    echo "  监听端口: $port"
    echo "  端口跳跃: $hop_range"
    echo "  拥塞控制: BBR"
    echo "  混淆: salamander"
    echo ""
    echo "证书指纹 (SHA-256):"
    echo "  $fingerprint"
    echo ""
    echo "客户端配置 (mihomo):"
    echo "----------------------------------------"
    echo "proxies:"
    echo "  - name: \"hysteria2\""
    echo "    type: hysteria2"
    echo "    server: $server_ip"
    echo "    port: $port"
    echo "    ports: $hop_range"
    echo "    hop-interval: 30"
    echo "    password: $password"
    echo "    bbr-profile: \"standard\""
    echo "    obfs: salamander"
    echo "    obfs-password: $obfs_password"
    echo "    sni: $server_ip"
    echo "    skip-cert-verify: true"
    echo "    fingerprint: $fingerprint"
    echo "    alpn:"
    echo "      - h3"
    echo ""
    echo "URI:"
    echo "  hysteria2://${password}@${server_ip}:${port}/?obfs=salamander&obfs-password=${obfs_password}&insecure=1&pinSHA256=${fingerprint}&sni=${server_ip}"
    echo ""
    echo "管理命令:"
    echo "  启动: systemctl start hysteria-server"
    echo "  停止: systemctl stop hysteria-server"
    echo "  重启: systemctl restart hysteria-server"
    echo "  状态: systemctl status hysteria-server"
    echo "  日志: journalctl -u hysteria-server -e"
    echo ""
    read -r -p "按 Enter 键返回主菜单..."
}

# ============================================
# 查看状态
# ============================================
show_status() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  Hysteria 2 服务状态${NC}"
    echo -e "${CYAN}=========================================${NC}"

    if ! is_installed; then
        echo -e "  运行状态: ${YELLOW}未安装${NC}"
        echo ""
        read -r -p "按 Enter 键返回主菜单..."
        return
    fi

    # 运行状态
    if systemctl is-active --quiet hysteria-server; then
        local pid
        pid=$(systemctl show -p MainPID hysteria-server 2>/dev/null | cut -d= -f2)
        echo -e "  运行状态: ${GREEN}运行中${NC} (PID: ${pid:-N/A})"
    else
        echo -e "  运行状态: ${RED}已停止${NC}"
    fi

    # 监听端口
    if [[ -f "$HY2_CONFIG" ]]; then
        local listen_port
        listen_port=$(grep -oP 'listen:\s*:\K\d+' "$HY2_CONFIG" 2>/dev/null)
        echo "  监听端口: ${listen_port:-未知}"
    fi

    # 内存占用
    if systemctl is-active --quiet hysteria-server; then
        local mem
        mem=$(ps -o rss= -p "$(systemctl show -p MainPID hysteria-server 2>/dev/null | cut -d= -f2)" 2>/dev/null)
        mem=$((mem / 1024))
        echo "  内存占用: ${mem:-N/A} MB"
    fi

    # 开机自启
    if systemctl is-enabled --quiet hysteria-server 2>/dev/null; then
        echo -e "  开机自启: ${GREEN}已启用${NC}"
    else
        echo -e "  开机自启: ${RED}未启用${NC}"
    fi

    # 证书指纹
    if [[ -f "$HY2_CERT" ]]; then
        local fp
        fp=$(get_fingerprint "$HY2_CERT")
        echo "  证书指纹: $fp"
    fi

    # iptables 规则
    if [[ -f "$HY2_CONFIG" ]]; then
        local listen_port
        listen_port=$(grep -oP 'listen:\s*:\K\d+' "$HY2_CONFIG" 2>/dev/null)
        if [[ -n "$listen_port" ]] && iptables -t nat -C PREROUTING -p udp --dport 25000:26000 -j DNAT --to-destination ":$listen_port" 2>/dev/null; then
            echo -e "  端口跳跃: ${GREEN}已配置${NC}"
        else
            echo -e "  端口跳跃: ${YELLOW}未检测到${NC}"
        fi
    fi

    echo ""
    echo "  配置文件: $HY2_CONFIG"
    echo "  证书:     $HY2_CERT"
    echo "  二进制:   $HY2_BIN"
    echo "  服务文件: $HY2_SERVICE_FILE"
    echo -e "${CYAN}=========================================${NC}"
    echo ""
    read -r -p "按 Enter 键返回主菜单..."
}

# ============================================
# 卸载
# ============================================
uninstall_hysteria2() {
    echo ""
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}  卸载 Hysteria 2 服务端${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo ""
    echo "将执行以下操作:"
    echo "  - 停止并禁用 systemd 服务"
    echo "  - 删除 $HY2_BIN"
    echo "  - 删除 $HY2_CONFIG_DIR/"
    echo "  - 删除 $HY2_SERVICE_FILE"
    echo "  - 清理 iptables 端口跳跃规则"
    echo ""
    read -r -p "确认卸载？[y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "卸载已取消"
        return
    fi

    echo ""

    # 停止服务
    if systemctl is-active --quiet hysteria-server 2>/dev/null; then
        log_info "停止服务..."
        systemctl stop hysteria-server
    fi

    if systemctl is-enabled --quiet hysteria-server 2>/dev/null; then
        log_info "禁用开机自启..."
        systemctl disable hysteria-server
    fi

    # 清理 iptables 规则
    if [[ -f "$HY2_CONFIG" ]]; then
        local listen_port
        listen_port=$(grep -oP 'listen:\s*:\K\d+' "$HY2_CONFIG" 2>/dev/null)
        if [[ -n "$listen_port" ]]; then
            log_info "清理 iptables 端口跳跃规则..."
            # 尝试从 iptables 中查找并删除规则
            iptables -t nat -L PREROUTING -n --line-numbers 2>/dev/null | grep "dpt:25000:26000" | awk '{print $1}' | sort -rn | while read -r line; do
                iptables -t nat -D PREROUTING "$line" 2>/dev/null
            done
            ip6tables -t nat -L PREROUTING -n --line-numbers 2>/dev/null | grep "dpt:25000:26000" | awk '{print $1}' | sort -rn | while read -r line; do
                ip6tables -t nat -D PREROUTING "$line" 2>/dev/null
            done
        fi
    fi

    log_info "删除服务文件..."
    rm -f "$HY2_SERVICE_FILE"
    systemctl daemon-reload

    log_info "删除二进制文件..."
    rm -f "$HY2_BIN"

    log_info "删除配置目录..."
    rm -rf "$HY2_CONFIG_DIR"

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
        log_error "Hysteria 2 未安装，请先安装"
        read -r -p "按 Enter 键返回主菜单..."
        return
    fi

    if [[ ! -f "$HY2_CONFIG" ]]; then
        log_error "配置文件不存在: $HY2_CONFIG"
        read -r -p "按 Enter 键返回主菜单..."
        return
    fi

    # 显示当前密码
    local current_password
    current_password=$(grep -oP '^password:\s*\K.*' "$HY2_CONFIG" 2>/dev/null)
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

    # 更新 config.yaml
    log_info "更新配置文件..."
    sed -i "s/^password:.*/password: ${new_password}/" "$HY2_CONFIG"

    log_info "重启 hysteria-server 服务..."
    systemctl restart hysteria-server

    if systemctl is-active --quiet hysteria-server; then
        log_success "密码已更新！"
    else
        log_error "服务重启失败，请检查日志: journalctl -u hysteria-server -n 50"
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
        echo -e "${CYAN}     Hysteria 2 服务端安装管理脚本${NC}"
        echo -e "${CYAN}=========================================${NC}"
        echo ""
        echo "  1. 安装 Hysteria 2 服务端"
        echo "  2. 查看当前配置与状态"
        echo "  3. 卸载 Hysteria 2 服务端"
        echo "  4. 修改密码"
        echo "  5. 退出"
        echo ""
        read -r -p "请选择 [1-5]: " choice
        case "$choice" in
            1) install_hysteria2 ;;
            2) show_status ;;
            3) uninstall_hysteria2 ;;
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
