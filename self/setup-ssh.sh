#!/bin/sh

# --- Configuration with Env Overrides ---
# Use: SSH_PORT=2222 bash setup_ssh.sh
SSH_PORT=${SSH_PORT:-29}
CONFIG_FILE=${CONFIG_FILE:-/etc/ssh/sshd_config}
OS_TYPE=$(uname -s)

# Color Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; exit 1; }

# Privilege Check
if [ "$OS_TYPE" != "Darwin" ] && [ "$(id -u)" -ne 0 ]; then
    error "Please run as root or use sudo."
fi

# Backup Configuration
BACKUP_PATH="${CONFIG_FILE}.bak_$(date +%Y%m%d%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_PATH" || error "Failed to backup $CONFIG_FILE"
log "Configuration backed up to $BACKUP_PATH"

# Portable Config Update Function
update_config() {
    key="$1"
    value="$2"
    if [ "$OS_TYPE" = "Darwin" ]; then
        sed -i '' "/^#\?${key}.*/d" "$CONFIG_FILE"
    else
        sed -i "/^#\?${key}.*/d" "$CONFIG_FILE"
    fi
    echo "${key} ${value}" >> "$CONFIG_FILE"
}

log "Applying SSH configurations (Port: $SSH_PORT)..."
update_config "Port" "$SSH_PORT"
update_config "PermitRootLogin" "yes"
update_config "PubkeyAuthentication" "yes"
update_config "PasswordAuthentication" "no"
update_config "ChallengeResponseAuthentication" "no"

# Handle Public Key
PUBKEY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --input-pubkey)
            printf "${GREEN}[INPUT] Paste your public key:${NC} "
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
    # Determine target directory
    if [ "$OS_TYPE" = "Darwin" ]; then
        TARGET_DIR="$HOME/.ssh"
    else
        [ "$(id -u)" -eq 0 ] && TARGET_DIR="/root/.ssh" || TARGET_DIR="$HOME/.ssh"
    fi

    mkdir -p "$TARGET_DIR"
    chmod 700 "$TARGET_DIR"
    
    AUTH_FILE="$TARGET_DIR/authorized_keys"
    # Ensure newline before appending
    printf "\n%s\n" "$PUBKEY" >> "$AUTH_FILE"
    chmod 600 "$AUTH_FILE"
    
    # Fix ownership on Linux
    if [ "$OS_TYPE" != "Darwin" ] && [ "$(id -u)" -eq 0 ]; then
        chown -R root:root "$TARGET_DIR" 2>/dev/null || true
    fi
    log "Public key added to $AUTH_FILE"
else
    log "No public key provided. Skipping authorized_keys setup."
fi

# Restart SSH Service
log "Restarting SSH service..."
if [ "$OS_TYPE" = "Darwin" ]; then
    sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist 2>/dev/null
    sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist
elif command -v systemctl >/dev/null 2>&1; then
    systemctl restart ssh || systemctl restart sshd
else
    /etc/init.d/ssh restart || /etc/init.d/sshd restart
fi

log "Success! SSH is now running on port $SSH_PORT."
log "IMPORTANT: Do NOT close this session until you verify access in a new terminal!"
