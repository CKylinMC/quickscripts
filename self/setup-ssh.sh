#!/bin/bash

# 配置变量
SSH_PORT=${SSH_PORT:-29}
CONFIG_FILE=${SSHD_CONFIG_FILE:-"/etc/ssh/sshd_config"}
# macOS 的配置路径通常一致，但重启命令不同
OS_TYPE=$(uname -s)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 权限检查 (Linux 需要 root, macOS 视情况而定)
if [ "$OS_TYPE" != "Darwin" ] && [ "$EUID" -ne 0 ]; then
    error "Please execute with root user, or run with sudo."
fi

# 备份原始配置
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak_$(date +%Y%m%d%H%M%S)"
log "Configuration backup to ${CONFIG_FILE}.bak_..."

# 修改 sshd_config 的函数
update_config() {
    local key=$1
    local value=$2
    # 先删除已存在的相同配置项（不论是否被注释），然后追加到末尾
    sed -i.tmp -e "/^#\?${key}.*/d" "$CONFIG_FILE"
    echo "${key} ${value}" >> "$CONFIG_FILE"
    rm -f "${CONFIG_FILE}.tmp"
}

# 针对 macOS 的 sed 兼容处理
if [ "$OS_TYPE" == "Darwin" ]; then
    update_config() {
        local key=$1
        local value=$2
        sed -i '' "/^#\?${key}.*/d" "$CONFIG_FILE"
        echo "${key} ${value}" >> "$CONFIG_FILE"
    }
fi

# 开始执行配置
log "Configuration SSH..."
update_config "Port" "$SSH_PORT"
update_config "PermitRootLogin" "yes"
update_config "PubkeyAuthentication" "yes"
update_config "PasswordAuthentication" "no"
update_config "ChallengeResponseAuthentication" "no"

# 处理公钥逻辑
PUBKEY=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --input-pubkey)
            echo -e "${GREEN}Paste your pubkey here(ssh-rsa/ssh-ed25519 ...):${NC}"
            read -r PUBKEY
            shift
            ;;
        --add-pubkey=*)
            PUBKEY="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

if [ -n "$PUBKEY" ]; then
    TARGET_DIR="$HOME/.ssh"
    [ "$OS_TYPE" != "Darwin" ] && [ "$USER" == "root" ] && TARGET_DIR="/root/.ssh"
    
    mkdir -p "$TARGET_DIR"
    chmod 700 "$TARGET_DIR"
    
    AUTH_FILE="$TARGET_DIR/authorized_keys"
    echo "$PUBKEY" >> "$AUTH_FILE"
    chmod 600 "$AUTH_FILE"
    
    # 修正属主 (如果是以 sudo 执行且为 root)
    if [ "$OS_TYPE" != "Darwin" ] && [ "$EUID" -eq 0 ]; then
        chown -R root:root "$TARGET_DIR" 2>/dev/null || true
    fi
    log "Pubkey saved to $AUTH_FILE"
else
    log "Pubkey not provided, keeping authorized_keys not modified."
fi

# 重启 SSH 服务
log "Restarting SSH service..."
if [ "$OS_TYPE" == "Darwin" ]; then
    sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist
    sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist
elif command -v systemctl >/dev/null 2>&1; then
    systemctl restart ssh || systemctl restart sshd
else
    service ssh restart || service sshd restart
fi

log "配置完成！新端口: $SSH_PORT"
log "注意：请确保防火墙已放行 $SSH_PORT 端口。请保留当前终端窗口，在另一窗口测试连接！"
