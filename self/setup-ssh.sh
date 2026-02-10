#!/bin/sh

# --- Variables with Env Overrides ---
SSH_PORT=${SSH_PORT:-29}
CONFIG_FILE=${CONFIG_FILE:-/etc/ssh/sshd_config}
OS_TYPE=$(uname -s)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

log() { printf "${GREEN}[INFO]${NC} %s\n" "$1"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; exit 1; }

# Privilege Check
if [ "$OS_TYPE" != "Darwin" ] && [ "$(id -u)" -ne 0 ]; then
    error "Must run as root or use sudo."
fi

# 1. Update sshd_config
log "Configuring sshd_config..."
cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"

update_conf() {
    key="$1"
    value="$2"
    # Handling sed -i differences safely
    if [ "$OS_TYPE" = "Darwin" ]; then
        sed -i '' "/^#\?${key}.*/d" "$CONFIG_FILE"
    else
        sed -i "/^#\?${key}.*/d" "$CONFIG_FILE"
    fi
    echo "${key} ${value}" >> "$CONFIG_FILE"
}

update_conf "Port" "$SSH_PORT"
update_conf "PermitRootLogin" "yes"
update_conf "PubkeyAuthentication" "yes"
update_conf "PasswordAuthentication" "no"

# 2. Fix Ubuntu 24.04 Socket Activation
if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files | grep -q ssh.socket; then
        log "Detected ssh.socket (Ubuntu 22.10+). Overriding ports..."
        mkdir -p /etc/systemd/system/ssh.socket.d
        cat <<EOF > /etc/systemd/system/ssh.socket.d/override.conf
[Socket]
ListenStream=
ListenStream=${SSH_PORT}
EOF
        systemctl daemon-reload
    fi
fi

# 3. Handle Public Keys
PUBKEY=""
for arg in "$@"; do
    case "$arg" in
        --add-pubkey=*) PUBKEY="${arg#*=}" ;;
    esac
done

if [ -n "$PUBKEY" ]; then
    # Cross-platform home directory resolution
    if [ "$OS_TYPE" = "Darwin" ]; then
        USER_HOME="$HOME"
    else
        [ "$(id -u)" -eq 0 ] && USER_HOME="/root" || USER_HOME="$HOME"
    fi
    
    mkdir -p "$USER_HOME/.ssh" && chmod 700 "$USER_HOME/.ssh"
    printf "\n%s\n" "$PUBKEY" >> "$USER_HOME/.ssh/authorized_keys"
    chmod 600 "$USER_HOME/.ssh/authorized_keys"
    log "Public key installed to $USER_HOME/.ssh/authorized_keys"
fi

# 4. Restart services
log "Restarting services..."
if [ "$OS_TYPE" = "Darwin" ]; then
    sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist 2>/dev/null
    sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist
else
    # Aggressive restart to clear Socket Activation locks
    systemctl stop ssh.socket 2>/dev/null
    systemctl restart ssh 2>/dev/null || systemctl restart sshd
    systemctl start ssh.socket 2>/dev/null
fi
