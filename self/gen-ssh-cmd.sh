#!/bin/bash

# --- Configuration with Env Overrides ---
# Use: REMOTE_SCRIPT_URL="https://my.domain/s.sh" bash gen_install.sh
REMOTE_HOST=${REMOTE_HOST:-"run.ckyl.in"}
REMOTE_SCRIPT_URL="https://${REMOTE_HOST}/self/setup-ssh.sh"

BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

find_local_pubkey() {
    # Search order: ed25519 -> rsa
    if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
        cat "$HOME/.ssh/id_ed25519.pub"
    elif [ -f "$HOME/.ssh/id_rsa.pub" ]; then
        cat "$HOME/.ssh/id_rsa.pub"
    else
        return 1
    fi
}

PUBKEY_CONTENT=""

# Argument Parsing
for arg in "$@"; do
    case $arg in
        --pubkey=*)
            FILE_PATH="${arg#*=}"
            if [ -f "$FILE_PATH" ]; then
                PUBKEY_CONTENT=$(cat "$FILE_PATH")
            else
                echo -e "${RED}Error: File $FILE_PATH not found.${NC}"
                exit 1
            fi
            ;;
    esac
done

# Auto-detect if not provided
if [ -z "$PUBKEY_CONTENT" ]; then
    PUBKEY_CONTENT=$(find_local_pubkey)
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: No default keys found (id_ed25519 or id_rsa).${NC}"
        echo "Please use --pubkey=/path/to/key.pub"
        exit 1
    fi
fi

# Clean up key (remove newlines)
SAFE_KEY=$(echo "$PUBKEY_CONTENT" | tr -d '\n\r')

echo -e "${BLUE}=== Generated One-Line Command ===${NC}"
echo ""
# Note: Explicitly using 'sudo bash -s' to handle Dash/Bash compatibility
printf "curl -sSL %s | sudo bash -s -- --add-pubkey=\"%s\"\n" "$REMOTE_SCRIPT_URL" "$SAFE_KEY"
echo ""
