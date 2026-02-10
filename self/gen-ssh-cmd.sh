#!/bin/bash

# --- 变量配置 ---
REMOTE_SCRIPT_URL="https://${SCRIPT_HOST:-run.ckyl.in}/self/setup_ssh.sh" 
# ----------------

# 颜色
BLUE='\033[0;34m'
NC='\033[0m'

PUBKEY_PATH=""
PROVIDED_KEY=""

# 参数解析
while [[ $# -gt 0 ]]; do
    case $1 in
        --pubkey=*)
            PUBKEY_PATH="${1#*=}"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# 密钥探测逻辑
if [ -n "$PUBKEY_PATH" ]; then
    if [ -f "$PUBKEY_PATH" ]; then
        PROVIDED_KEY=$(cat "$PUBKEY_PATH")
    else
        echo "Fatal: Pubkey file $PUBKEY_PATH not exists."
        exit 1
    fi
else
    # 自动探测默认密钥: 优先 ed25519，然后 rsa
    if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
        PROVIDED_KEY=$(cat "$HOME/.ssh/id_ed25519.pub")
    elif [ -f "$HOME/.ssh/id_rsa.pub" ]; then
        PROVIDED_KEY=$(cat "$HOME/.ssh/id_rsa.pub")
    else
        echo "Fatal: Default key (id_ed25519 或 id_rsa) not found，use --pubkey= to specific pubkey file."
        exit 1
    fi
fi

# 移除可能的换行符并转义单引号以便安全传输
PROVIDED_KEY=$(echo "$PROVIDED_KEY" | tr -d '\n\r')

echo -e "${BLUE}=== Generated command ===${NC}"
echo ""
echo "curl -sSL $REMOTE_SCRIPT_URL | sudo sh -s -- --add-pubkey=\"$PROVIDED_KEY\""
echo ""
echo -e "${BLUE}Tip：${NC}Copy and paste to your remote sever, and your server will be config as well."
