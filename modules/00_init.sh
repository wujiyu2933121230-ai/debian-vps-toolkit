#!/bin/bash
# modules/00_init.sh - Debian VPS 初始化脚本
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

# ============================================
# 1. 系统更新
# ============================================
system_update() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  1. 系统更新${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""

    log_info "更新软件源..."
    apt update

    log_info "升级已安装软件包..."
    apt upgrade -y

    log_success "系统更新完成"
}

# ============================================
# 2. 安装基础工具
# ============================================
install_tools() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  2. 安装基础工具${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""

    local tools=(
        curl wget net-tools dnsutils mtr traceroute
        htop lsof vim rsync zip unzip tmux git
    )

    log_info "安装基础工具: ${tools[*]}"
    apt install -y "${tools[@]}"

    log_success "基础工具安装完成"
}

# ============================================
# 3. 系统清理
# ============================================
system_cleanup() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  3. 系统清理${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""

    log_info "移除无用依赖包..."
    apt autoremove -y

    log_info "清理本地缓存..."
    apt autoclean -y

    log_info "限制 journal 日志大小为 50M..."
    mkdir -p /etc/systemd/journald.conf.d
    cat > /etc/systemd/journald.conf.d/50-size.conf << 'EOF'
[Journal]
SystemMaxUse=50M
EOF
    systemctl restart systemd-journald

    log_success "系统清理完成"
}

# ============================================
# 4. 配置 Swap（与内存等大）
# ============================================
setup_swap() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  4. 配置 Swap${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""

    # 检查是否已有 swap
    if swapon --show 2>/dev/null | grep -q .; then
        log_info "检测到已有 Swap，跳过创建"
        swapon --show
        return
    fi

    # 获取内存大小（MB）
    local mem_mb
    mem_mb=$(free -m | awk '/^Mem:/ {print $2}')
    local swap_size="${mem_mb}M"

    log_info "物理内存: ${mem_mb}MB，创建等大 Swap: ${swap_size}"

    # 创建 swap 文件
    dd if=/dev/zero of=/swapfile bs=1M count="$mem_mb" status=progress
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    # 写入 fstab
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    log_success "Swap 配置完成"
    free -h | grep -E '^Swap|^Mem'
}

# ============================================
# 5. 设置时区
# ============================================
set_timezone() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  5. 设置时区${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""

    log_info "设置时区为 Asia/Shanghai..."
    timedatectl set-timezone Asia/Shanghai

    log_success "时区已设置: $(timedatectl | grep 'Time zone')"
}

# ============================================
# 6. 优化 DNS
# ============================================
setup_dns() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  6. 优化 DNS${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""

    # 检查是否被 systemd-resolved 管理
    if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
        log_info "检测到 systemd-resolved，配置 DNS..."

        cat > /etc/systemd/resolved.conf << 'EOF'
[Resolve]
DNS=8.8.8.8 1.1.1.1 2001:4860:4860::8888 2606:4700:4700::1111
FallbackDNS=8.8.4.4 2001:4860:4860::8844
EOF

        systemctl restart systemd-resolved
    else
        log_info "配置 /etc/resolv.conf..."

        chattr -i /etc/resolv.conf 2>/dev/null
        cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 2001:4860:4860::8888
nameserver 2606:4700:4700::1111
EOF
        chattr +i /etc/resolv.conf 2>/dev/null || true
    fi

    log_success "DNS 配置完成"
}

# ============================================
# 7. IPv4 优先
# ============================================
prefer_ipv4() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  7. IPv4 优先${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""

    local gai_conf="/etc/gai.conf"
    local rule="precedence ::ffff:0:0/96  100"

    if grep -q "^${rule}" "$gai_conf" 2>/dev/null; then
        log_info "IPv4 优先已配置，跳过"
    else
        log_info "配置 IPv4 优先..."
        # 如果存在被注释的规则，取消注释
        if grep -q "^#${rule}" "$gai_conf" 2>/dev/null; then
            sed -i "s/^#${rule}/${rule}/" "$gai_conf"
        else
            echo "$rule" >> "$gai_conf"
        fi
        log_success "IPv4 优先已启用"
    fi
}

# ============================================
# 主流程
# ============================================
main() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  Debian VPS 初始化${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""
    echo "  将执行以下操作："
    echo "    1. 系统更新         — apt update && apt upgrade"
    echo "    2. 安装基础工具     — curl, wget, htop 等 14 个工具"
    echo "    3. 系统清理         — 移除无用包，journal 日志限制 50M"
    echo "    4. 配置 Swap        — 与内存等大（已有则跳过）"
    echo "    5. 设置时区         — Asia/Shanghai"
    echo "    6. 优化 DNS         — 8.8.8.8 / 1.1.1.1 + IPv6"
    echo "    7. IPv4 优先        — 修改 gai.conf"
    echo ""
    read -r -p "  是否继续初始化？[Y/n]: " confirm
    confirm=${confirm:-Y}
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_warn "初始化已取消"
        exit 0
    fi
    echo ""

    system_update
    install_tools
    system_cleanup
    setup_swap
    set_timezone
    setup_dns
    prefer_ipv4

    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${GREEN}  所有初始化步骤已完成！${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""
}

# ============================================
# 入口
# ============================================
check_root
main
