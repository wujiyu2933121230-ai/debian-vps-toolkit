#!/bin/bash
# modules/01_ssh.sh - SSH 管理脚本
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

ssh_config="/etc/ssh/sshd_config"
ssh_config_bak="/etc/ssh/sshd_config.bak"

# ============================================
# 读取当前配置值
# ============================================
get_config_value() {
    local key="$1"
    # 先找未被注释的配置行，取最后一个有效值
    grep -E "^\s*${key}\s+" "$ssh_config" 2>/dev/null | tail -1 | awk '{print $2}'
}

# ============================================
# 显示系统状态
# ============================================
show_status() {
    local port
    local password_auth
    local pubkey_auth

    port=$(get_config_value "Port")
    port=${port:-22}

    password_auth=$(get_config_value "PasswordAuthentication")
    password_auth=${password_auth:-yes}

    pubkey_auth=$(get_config_value "PubkeyAuthentication")
    pubkey_auth=${pubkey_auth:-yes}

    echo ""
    echo -e "${CYAN}========== 系统状态 ==========${NC}"
    echo -e "  当前用户:     ${GREEN}$(whoami)${NC}"
    echo -e "  SSH 端口:     ${GREEN}${port}${NC}"
    echo -e "  密码登录:     $( [[ "$password_auth" == "yes" ]] && echo -e "${GREEN}已开启${NC}" || echo -e "${RED}已关闭${NC}" )"
    echo -e "  密钥登录:     $( [[ "$pubkey_auth" == "yes" ]] && echo -e "${GREEN}已开启${NC}" || echo -e "${RED}已关闭${NC}" )"
    echo -e "${CYAN}==============================${NC}"
    echo ""
}

# ============================================
# 备份配置
# ============================================
backup_config() {
    if [[ ! -f "$ssh_config_bak" ]]; then
        cp "$ssh_config" "$ssh_config_bak"
        log_info "已备份原配置到 $ssh_config_bak"
    fi
}

# ============================================
# 修改配置项
# ============================================
set_config_value() {
    local key="$1"
    local value="$2"

    backup_config

    if grep -qE "^\s*${key}\s+" "$ssh_config"; then
        sed -i "s/^\s*${key}\s\+.*/${key} ${value}/" "$ssh_config"
    else
        echo "${key} ${value}" >> "$ssh_config"
    fi

    log_success "已设置 ${key} ${value}"
    log_warn "请手动执行: systemctl restart sshd"
}

# ============================================
# 1. 修改 SSH 端口
# ============================================
set_port() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  修改 SSH 端口${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""

    local current_port
    current_port=$(get_config_value "Port")
    current_port=${current_port:-22}

    echo -e "  当前端口: ${GREEN}${current_port}${NC}"
    echo ""

    read -r -p "  请输入新端口 (1-65535): " new_port

    # 校验端口号
    if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 ]] || [[ "$new_port" -gt 65535 ]]; then
        log_error "端口号无效，请输入 1-65535 之间的数字"
        return
    fi

    if [[ "$new_port" -eq "$current_port" ]]; then
        log_warn "新端口与当前端口相同，无需修改"
        return
    fi

    set_config_value "Port" "$new_port"
    echo ""
    log_warn "请手动执行: systemctl restart sshd"
    log_warn "然后用新端口 ${new_port} 重新登录"
}

# ============================================
# 2. 密码管理
# ============================================
password_menu() {
    while true; do
        echo ""
        echo -e "${CYAN}=========================================${NC}"
        echo -e "${CYAN}  密码管理${NC}"
        echo -e "${CYAN}=========================================${NC}"
        echo ""
        echo "  1. 开启密码登录"
        echo "  2. 关闭密码登录"
        echo "  3. 修改当前用户密码"
        echo "  0. 返回主菜单"
        echo ""
        read -r -p "  请选择 [0-3]: " choice

        case "$choice" in
            1)
                set_config_value "PasswordAuthentication" "yes"
                ;;
            2)
                set_config_value "PasswordAuthentication" "no"
                ;;
            3)
                change_password
                ;;
            0)
                break
                ;;
            *)
                log_error "无效选项，请重新选择"
                ;;
        esac
    done
}

# ============================================
# 2.3 修改当前用户密码
# ============================================
change_password() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  修改当前用户密码${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""

    local user
    user=$(whoami)

    echo -e "  当前用户: ${GREEN}${user}${NC}"
    echo ""

    read -r -s -p "  请输入新密码: " password1
    echo ""

    # 密码非空校验
    if [[ -z "$password1" ]]; then
        log_error "密码不能为空"
        return
    fi

    read -r -s -p "  请再次输入新密码: " password2
    echo ""

    if [[ "$password1" != "$password2" ]]; then
        log_error "两次输入的密码不一致"
        return
    fi

    if echo "${user}:${password1}" | chpasswd; then
        log_success "密码修改成功"
    else
        log_error "密码修改失败"
    fi
}

# ============================================
# 3. 密钥管理
# ============================================
key_menu() {
    while true; do
        echo ""
        echo -e "${CYAN}=========================================${NC}"
        echo -e "${CYAN}  密钥管理${NC}"
        echo -e "${CYAN}=========================================${NC}"
        echo ""
        echo "  1. 开启密钥登录"
        echo "  2. 关闭密钥登录"
        echo "  3. 添加公钥"
        echo "  4. 查看已添加公钥"
        echo "  0. 返回主菜单"
        echo ""
        read -r -p "  请选择 [0-4]: " choice

        case "$choice" in
            1)
                set_config_value "PubkeyAuthentication" "yes"
                ;;
            2)
                set_config_value "PubkeyAuthentication" "no"
                ;;
            3)
                add_ssh_key
                ;;
            4)
                view_ssh_keys
                ;;
            0)
                break
                ;;
            *)
                log_error "无效选项，请重新选择"
                ;;
        esac
    done
}

# ============================================
# 3.3 添加公钥
# ============================================
add_ssh_key() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  添加公钥${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""
    echo "  请选择添加方式："
    echo "    1. 直接粘贴公钥内容"
    echo "    2. 输入公钥 URL 下载"
    echo "    0. 返回"
    echo ""
    read -r -p "  请选择 [0-2]: " method

    local ssh_dir="$HOME/.ssh"
    local auth_keys="${ssh_dir}/authorized_keys"
    local pubkey=""

    case "$method" in
        1)
            echo ""
            echo "  请粘贴公钥内容（以 ssh-rsa / ssh-ed25519 / ecdsa-sha2-* 开头），"
            echo -n "  粘贴后按 Ctrl+D 结束: "
            echo ""
            pubkey=$(cat)
            ;;
        2)
            echo ""
            read -r -p "  请输入公钥 URL: " key_url
            if [[ -z "$key_url" ]]; then
                log_error "URL 不能为空"
                return
            fi
            if ! pubkey=$(curl -fsSL "$key_url" 2>/dev/null) || [[ -z "$pubkey" ]]; then
                log_error "下载公钥失败，请检查 URL"
                return
            fi
            ;;
        0)
            return
            ;;
        *)
            log_error "无效选项"
            return
            ;;
    esac

    if [[ -z "$pubkey" ]]; then
        log_error "公钥内容不能为空"
        return
    fi

    # 检查是否为有效的公钥格式
    if ! echo "$pubkey" | grep -qE "^(ssh-rsa|ssh-ed25519|ecdsa-sha2|sk-ssh-ed25519|sk-ecdsa-sha2)"; then
        log_error "无效的公钥格式，请确认以 ssh-rsa / ssh-ed25519 / ecdsa-sha2-* 开头"
        return
    fi

    # 创建目录和文件
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"

    touch "$auth_keys"
    chmod 600 "$auth_keys"

    # 检查是否已存在相同的公钥（按内容去重）
    local key_fingerprint
    key_fingerprint=$(echo "$pubkey" | awk '{print $2}')
    if grep -q "$key_fingerprint" "$auth_keys" 2>/dev/null; then
        log_warn "该公钥已存在，跳过添加"
        return
    fi

    echo "$pubkey" >> "$auth_keys"
    log_success "公钥已添加到 ${auth_keys}"
}

# ============================================
# 3.4 查看已添加公钥
# ============================================
view_ssh_keys() {
    echo ""
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  已添加公钥${NC}"
    echo -e "${CYAN}=========================================${NC}"
    echo ""

    local auth_keys="$HOME/.ssh/authorized_keys"

    if [[ ! -f "$auth_keys" ]]; then
        log_info "尚未添加任何公钥"
        return
    fi

    local count
    count=$(wc -l < "$auth_keys")

    if [[ "$count" -eq 0 ]]; then
        log_info "尚未添加任何公钥"
        return
    fi

    echo -e "  文件: ${auth_keys}"
    echo -e "  数量: ${GREEN}${count}${NC} 个公钥"
    echo ""
    echo -e "${CYAN}------------------------------${NC}"
    awk '{
        type=$1
        fingerprint=substr($2,1,20)
        comment=$3
        printf "  [%d] %s %s... %s\n", NR, type, fingerprint, comment
    }' "$auth_keys"
    echo -e "${CYAN}------------------------------${NC}"
}

# ============================================
# 主菜单
# ============================================
main() {
    while true; do
        echo ""
        echo -e "${CYAN}=========================================${NC}"
        echo -e "${CYAN}  SSH 管理${NC}"
        echo -e "${CYAN}=========================================${NC}"

        show_status

        echo "  请选择操作："
        echo "    1. 修改 SSH 端口"
        echo "    2. 密码管理"
        echo "    3. 密钥管理"
        echo "    0. 退出"
        echo ""
        read -r -p "  请选择 [0-3]: " choice

        case "$choice" in
            1)
                set_port
                ;;
            2)
                password_menu
                ;;
            3)
                key_menu
                ;;
            0)
                echo ""
                log_info "退出 SSH 管理"
                echo ""
                exit 0
                ;;
            *)
                log_error "无效选项，请重新选择"
                ;;
        esac
    done
}

# ============================================
# 入口
# ============================================
check_root
main
