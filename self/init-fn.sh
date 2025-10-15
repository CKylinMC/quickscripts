#!/bin/bash

# Cross-platform system initialization script
# Supports macOS and Linux systems
# Auto-detects shell (bash/zsh) with fallback to sh

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Utility functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect operating system
detect_os() {
    case "$(uname -s)" in
        Darwin*)    echo "macos" ;;
        Linux*)     echo "linux" ;;
        *)          echo "unknown" ;;
    esac
}

# Detect available shell
detect_shell() {
    if command -v zsh >/dev/null 2>&1; then
        echo "zsh"
    elif command -v bash >/dev/null 2>&1; then
        echo "bash"
    else
        echo "sh"
    fi
}

# Get shell configuration files based on OS and shell
get_shell_config_files() {
    local os="$1"
    local shell="$2"
    
    if [ "$os" = "macos" ]; then
        if [ "$shell" = "zsh" ]; then
            echo "$HOME/.zprofile"
        else
            echo "$HOME/.bash_profile $HOME/.profile"
        fi
    else  # linux
        echo "$HOME/.bashrc $HOME/.profile"
    fi
}

# Check if function block already exists in file
function_block_exists() {
    local file="$1"
    [ -f "$file" ] && grep -q "###### fn utils v00001" "$file"
}

# Add function loading block to shell config file
add_function_block() {
    local file="$1"
    
    if function_block_exists "$file"; then
        log_warning "Function block already exists in $file, skipping..."
        return 0
    fi
    
    log_info "Adding function loading block to $file"
    
    # Create file if it doesn't exist
    touch "$file"
    
    # Add the function loading block
    cat >> "$file" << 'EOF'

###### fn utils v00001
# Load custom shell functions from a directory
FUNCTIONS_DIR="$HOME/.functions.d"
if [ -d "$FUNCTIONS_DIR" ]; then
    for fn_file in "$FUNCTIONS_DIR"/*.fn; do
        if [ -f "$fn_file" ]; then
            . "$fn_file"
        fi
    done
fi
###### fn utils end
EOF
    
    log_success "Function loading block added to $file"
}

# Create proxy function file
create_proxy_function() {
    local proxy_file="$HOME/.functions.d/proxy.fn"
    
    log_info "Creating proxy function file: $proxy_file"
    
    cat > "$proxy_file" << 'EOF'
__set_proxy_fn() {
    local proxy_addr=""
    if [ -z "$1" ]; then
        proxy_addr="http://127.0.0.1:10809"
    elif [[ "$1" =~ ^: ]]; then
        proxy_addr="http://127.0.0.1$1"
    elif [[ ! "$1" =~ ^https?:// ]]; then
        proxy_addr="http://$1"
    else
        proxy_addr="$1"
    fi

    export http_proxy="$proxy_addr" \
           https_proxy="$proxy_addr" \
           socks_proxy="$proxy_addr" \
           socks5_proxy="$proxy_addr" \
           HTTP_PROXY="$proxy_addr" \
           HTTPS_PROXY="$proxy_addr" \
           SOCKS_PROXY="$proxy_addr" \
           SOCKS5_PROXY="$proxy_addr"

    echo "✅ Proxy variables set to: $proxy_addr"
    echo "Use 'unsetproxy' to unset the proxy variables"
    __curl_test_addr_for_proxy "$proxy_addr"
}
__curl_test_addr_for_proxy(){
    echo -ne "Checking for availablity...\r"
    if curl -sS --connect-timeout 5 "$1" > /dev/null; then
        echo -e "✅ [Check OK] The proxy at $1 is accepting connections."
    else
        echo -e "❌ [Check Failed] The proxy at $1 is not responding."
    fi
}
__unset_proxy_fn() {
    unset http_proxy https_proxy socks_proxy socks5_proxy HTTP_PROXY HTTPS_PROXY SOCKS_PROXY SOCKS5_PROXY
    echo "❌ Proxy variables removed."
}


alias setproxy='__set_proxy_fn'
alias unsetproxy='__unset_proxy_fn'
EOF
    
    chmod +x "$proxy_file"
    log_success "Proxy function file created and made executable"
}

# Create reloadenv function file
create_reloadenv_function() {
    local os="$1"
    local shell="$2"
    local reloadenv_file="$HOME/.functions.d/reloadenv.fn"
    
    log_info "Creating reloadenv function file: $reloadenv_file"
    
    if [ "$os" = "macos" ]; then
        if [ "$shell" = "zsh" ]; then
            cat > "$reloadenv_file" << 'EOF'
reloadenv(){
    . ~/.zprofile
}
EOF
        else
            cat > "$reloadenv_file" << 'EOF'
reloadenv(){
    . ~/.bash_profile
    . ~/.profile
}
EOF
        fi
    else  # linux
        cat > "$reloadenv_file" << 'EOF'
reloadenv(){
    . ~/.bashrc
    . ~/.profile
}
EOF
    fi
    
    chmod +x "$reloadenv_file"
    log_success "Reloadenv function file created and made executable"
}

# Source the configuration files
reload_environment() {
    local os="$1"
    local shell="$2"
    
    log_info "Reloading environment configuration..."
    
    local config_files
    config_files=$(get_shell_config_files "$os" "$shell")
    
    for config_file in $config_files; do
        if [ -f "$config_file" ]; then
            log_info "Sourcing $config_file"
            # Use current shell to source the file
            if [ "$shell" = "zsh" ]; then
                zsh -c ". '$config_file'" 2>/dev/null || true
            elif [ "$shell" = "bash" ]; then
                bash -c ". '$config_file'" 2>/dev/null || true
            else
                sh -c ". '$config_file'" 2>/dev/null || true
            fi
        fi
    done
    
    log_success "Environment configuration reloaded"
}

# Main execution
main() {
    log_info "Starting system initialization..."
    
    # Detect system environment
    local os
    os=$(detect_os)
    log_info "Detected operating system: $os"
    
    if [ "$os" = "unknown" ]; then
        log_error "Unsupported operating system"
        exit 1
    fi
    
    local shell
    shell=$(detect_shell)
    log_info "Detected shell: $shell"
    
    # Create functions directory
    log_info "Creating ~/.functions.d directory"
    mkdir -p "$HOME/.functions.d"
    log_success "Functions directory created"
    
    # Get shell configuration files
    local config_files
    config_files=$(get_shell_config_files "$os" "$shell")
    
    # Add function loading block to each config file
    for config_file in $config_files; do
        add_function_block "$config_file"
    done
    
    # Create function files
    create_proxy_function
    create_reloadenv_function "$os" "$shell"
    
    # Reload environment
    reload_environment "$os" "$shell"
    
    log_success "System initialization completed successfully!"
    echo
    log_info "Available commands after restarting your shell or running 'reloadenv':"
    echo "  - setproxy [address]  : Set proxy variables (default: http://127.0.0.1:10809)"
    echo "  - unsetproxy         : Remove proxy variables"
    echo "  - reloadenv          : Reload shell environment"
    echo
    log_info "Please restart your shell or run 'source ~/.$(basename "$SHELL")rc' to use the new functions"
}

# Execute main function
main "$@"
