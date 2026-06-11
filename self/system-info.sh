#!/bin/bash

################################################################################
# 系统信息检查脚本
# 功能：快速检查设备型号、架构、发行版、CPU、GPU、内存等信息
# 兼容：Linux (x86/ARM/RISC-V)、macOS、WSL、树莓派 3/4/5
# 使用：
#   bash system-info.sh                 默认：硬件信息检查
#   bash system-info.sh --environment   环境检查（编程语言、工具、数据库、服务等）
#   bash system-info.sh --network       网络端口检查（监听端口及对应服务）
#   bash system-info.sh --all           全部检查（硬件 + 环境 + 网络）
################################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 分隔线
SEPARATOR="═══════════════════════════════════════════════════════════════"

# 打印标题
print_header() {
    echo -e "${BLUE}${SEPARATOR}${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}${SEPARATOR}${NC}"
}

# 打印键值对
print_info() {
    printf "  ${CYAN}%-30s${NC} : ${GREEN}%b${NC}\n" "$1" "$2"
}

# 打印错误信息
print_error() {
    printf "  ${RED}%-30s${NC} : ${YELLOW}%b${NC}\n" "$1" "$2"
}

# 打印警告信息（用于检测到但状态异常）
print_warn() {
    printf "  ${YELLOW}%-30s${NC} : ${YELLOW}%b${NC}\n" "$1" "$2"
}

# 检测命令是否存在，存在则打印版本
# 用法: check_cmd_version <cmd> [<args>] [<label>] [<version_filter>]
check_cmd_version() {
    local cmd="$1"
    local args="${2:---version}"
    local label="${3:-$cmd}"
    local filter="${4:-head -1}"
    if command -v "$cmd" &> /dev/null; then
        local ver
        ver=$(eval "$cmd $args" 2>&1 | eval "$filter" | tr '\n' ' ' | xargs | head -c 120)
        print_info "$label" "${ver:-已安装}"
    fi
}

# 检测命令是否存在，存在则用 print_info，不存在则不输出
check_cmd_present() {
    local cmd="$1"
    local label="${2:-$cmd}"
    if command -v "$cmd" &> /dev/null; then
        local which_path
        which_path=$(command -v "$cmd" 2>/dev/null)
        print_info "$label" "已安装 ($which_path)"
    fi
}

# 检测 systemd 服务状态
check_systemd_service() {
    local svc="$1"
    local label="${2:-$svc}"
    if command -v systemctl &> /dev/null; then
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            print_info "$label" "${GREEN}运行中${NC}"
            return 0
        elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then
            print_warn "$label" "已启用但未运行"
            return 1
        fi
    fi
    return 1
}

# 检测通过 ps 的进程是否在运行
check_process_running() {
    local proc="$1"
    local label="${2:-$proc}"
    if pgrep -x "$proc" > /dev/null 2>&1; then
        local pid
        pid=$(pgrep -x "$proc" | head -1)
        print_info "$label" "${GREEN}运行中${NC} (PID: $pid)"
        return 0
    fi
    return 1
}

################################################################################
# 参数解析
################################################################################
MODE_HARDWARE=1
MODE_ENVIRONMENT=0
MODE_NETWORK=0

for arg in "$@"; do
    case "$arg" in
        --environment|-e)
            MODE_HARDWARE=0
            MODE_ENVIRONMENT=1
            ;;
        --network|-n)
            MODE_HARDWARE=0
            MODE_NETWORK=1
            ;;
        --all|-a)
            MODE_HARDWARE=1
            MODE_ENVIRONMENT=1
            MODE_NETWORK=1
            ;;
        --help|-h)
            echo "用法: bash system-info.sh [选项]"
            echo ""
            echo "选项:"
            echo "  无参数               默认：硬件信息检查"
            echo "  --environment, -e    环境检查（编程语言、工具、数据库、服务等）"
            echo "  --network, -n        网络端口检查（监听端口及对应服务）"
            echo "  --all, -a            全部检查（硬件 + 环境 + 网络）"
            echo "  --help, -h           显示此帮助信息"
            exit 0
            ;;
        *)
            echo "未知参数: $arg (使用 --help 查看帮助)"
            exit 1
            ;;
    esac
done

################################################################################
# 平台检测（全局变量）
################################################################################
OS_NAME=$(uname -s)
OS_ARCH=$(uname -m)

# 是否为 macOS
IS_MAC=0
[ "$OS_NAME" = "Darwin" ] && IS_MAC=1

# 是否为 WSL（Windows Subsystem for Linux）
IS_WSL=0
if [ "$OS_NAME" = "Linux" ]; then
    if grep -qi "microsoft\|WSL" /proc/version 2>/dev/null; then
        IS_WSL=1
    elif [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
        IS_WSL=1
    elif [ -n "$WSL_DISTRO_NAME" ]; then
        IS_WSL=1
    fi
fi

# 是否为树莓派
IS_RPI=0
if [ "$OS_NAME" = "Linux" ] && [ -f /proc/cpuinfo ]; then
    if grep -qi "BCM2\|BCM2708\|BCM2709\|BCM2710\|BCM2711\|BCM2712\|Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
        IS_RPI=1
    fi
fi

# 平台类型（用于显示）
if [ $IS_MAC -eq 1 ]; then
    PLATFORM_TYPE="macOS"
elif [ $IS_WSL -eq 1 ]; then
    PLATFORM_TYPE="WSL (Windows Subsystem for Linux)"
elif [ $IS_RPI -eq 1 ]; then
    PLATFORM_TYPE="树莓派 (Raspberry Pi)"
else
    PLATFORM_TYPE="原生 Linux"
fi

################################################################################
# ===== 环境检查函数 =====
################################################################################

# ── 编程语言环境 ──
check_languages() {
    print_header "💻 编程语言环境"

    # PHP + Composer
    if command -v php &> /dev/null; then
        check_cmd_version "php" "-v" "PHP" "head -1"
        check_cmd_version "composer" "--version" "Composer"
        # PHP 扩展
        local php_exts
        php_exts=$(php -m 2>/dev/null | tr '\n' ' ' | xargs | head -c 160)
        [ -n "$php_exts" ] && print_info "PHP 扩展" "$php_exts"
    fi

    # Go
    if command -v go &> /dev/null; then
        check_cmd_version "go" "version" "Go"
        # GOPATH / GOROOT
        [ -n "$GOPATH" ] && print_info "Go GOPATH" "$GOPATH"
        [ -n "$GOROOT" ] && print_info "Go GOROOT" "$GOROOT"
    fi

    # Rust (Cargo)
    check_cmd_version "rustc" "--version" "Rust (rustc)"
    check_cmd_version "cargo" "--version" "Cargo"

    # Node.js 生态: node / npm / pnpm / yarn / fnm
    if command -v node &> /dev/null; then
        check_cmd_version "node" "-v" "Node.js"
        check_cmd_version "npm" "-v" "npm"
        check_cmd_version "pnpm" "-v" "pnpm"
        check_cmd_version "yarn" "-v" "yarn"
        check_cmd_version "fnm" "--version" "fnm"
        # 全局安装的包数量
        if command -v npm &> /dev/null; then
            local pkg_count
            pkg_count=$(npm ls -g --depth=0 2>/dev/null | grep -c "├──\|└──" 2>/dev/null || echo "0")
            [ "$pkg_count" -gt 0 ] 2>/dev/null && print_info "npm 全局包数" "$pkg_count"
        fi
    fi

    # Bun
    check_cmd_version "bun" "--version" "Bun"

    # Deno
    if command -v deno &> /dev/null; then
        check_cmd_version "deno" "--version" "Deno" "head -1"
    fi

    # Java (JRE / JDK)
    # macOS 上 command -v java 会返回 /usr/bin/java 存根，需验证是否真正可用
    local java_ok=0
    if command -v java &> /dev/null; then
        if java -version 2>&1 | grep -qi "version"; then
            java_ok=1
            check_cmd_version "java" "-version" "Java (JRE)" "head -1"
        fi
    fi
    if command -v javac &> /dev/null; then
        if javac -version 2>&1 | grep -qi "javac"; then
            check_cmd_version "javac" "-version" "Java (JDK)"
        fi
    fi
    # JAVA_HOME
    [ -n "$JAVA_HOME" ] && print_info "Java JAVA_HOME" "$JAVA_HOME"

    # Python + venv + UV + PyTorch + TensorFlow
    local python_cmd=""
    if command -v python3 &> /dev/null; then
        python_cmd="python3"
    elif command -v python &> /dev/null; then
        python_cmd="python"
    fi
    if [ -n "$python_cmd" ]; then
        local pyver
        pyver=$("$python_cmd" --version 2>&1)
        print_info "Python" "$pyver"
        # pip
        check_cmd_version "pip3" "--version" "pip"
        check_cmd_version "pip" "--version" "pip"
        # venv 模块
        if "$python_cmd" -m venv --help &>/dev/null 2>&1; then
            print_info "Python venv" "可用"
        fi
        # UV
        check_cmd_version "uv" "--version" "UV"
        # PyTorch（仅导入成功时显示版本）
        local torch_ver
        torch_ver=$("$python_cmd" -c "import torch; print(torch.__version__)" 2>/dev/null)
        [ -n "$torch_ver" ] && print_info "PyTorch" "$torch_ver"
        # TensorFlow（仅导入成功时显示版本）
        local tf_ver
        tf_ver=$("$python_cmd" -c "import tensorflow as tf; print(tf.__version__)" 2>/dev/null)
        [ -n "$tf_ver" ] && print_info "TensorFlow" "$tf_ver"
    fi

    # Lua
    check_cmd_version "lua" "-v" "Lua"
    check_cmd_version "luajit" "-v" "LuaJIT"

    # Perl
    if command -v perl &> /dev/null; then
        local perlver
        perlver=$(perl -v 2>&1 | grep "This is perl" | head -1 | sed 's/.*(//' | sed 's/).*//' | xargs)
        print_info "Perl" "$perlver"
    fi

    # Ruby
    check_cmd_version "ruby" "--version" "Ruby"
    check_cmd_version "gem" "--version" "gem"

    # .NET
    check_cmd_version "dotnet" "--version" ".NET SDK"
    check_cmd_version "dotnet" "--list-runtimes" ".NET 运行时" "head -5"

    # C / C++ 编译器
    check_cmd_version "gcc" "--version" "GCC" "head -1"
    check_cmd_version "g++" "--version" "G++" "head -1"
    check_cmd_version "clang" "--version" "Clang" "head -1"
    check_cmd_version "clang++" "--version" "Clang++" "head -1"
    check_cmd_version "tcc" "-v" "TCC" "head -1"
    check_cmd_version "make" "--version" "Make" "head -1"
    check_cmd_version "cmake" "--version" "CMake" "head -1"

    # Flutter / Dart
    check_cmd_version "flutter" "--version" "Flutter" "head -1"
    check_cmd_version "dart" "--version" "Dart" "head -1"

    # Kotlin
    check_cmd_version "kotlin" "-version" "Kotlin"
    check_cmd_version "kotlinc" "-version" "Kotlin 编译器"

    # Gradle
    check_cmd_version "gradle" "--version" "Gradle" "head -2 | tail -1"
    check_cmd_version "gradlew" "--version" "Gradle Wrapper" "head -2 | tail -1"
}

# ── Linux 基础工具包 ──
check_basic_tools() {
    print_header "🔧 Linux 基础工具包"

    # 版本/环境管理
    check_cmd_version "mise" "--version" "mise"
    check_cmd_version "rbenv" "--version" "rbenv"
    check_cmd_version "pyenv" "--version" "pyenv"
    check_cmd_version "nvm" "--version" "nvm"

    # 网络工具
    check_cmd_version "curl" "--version" "curl" "head -1"
    check_cmd_version "wget" "--version" "wget" "head -1"
    check_cmd_version "rsync" "--version" "rsync" "head -1"
    check_cmd_present "nc" "netcat (nc)"

    # 加密/证书
    check_cmd_version "openssl" "version" "OpenSSL"
    check_cmd_version "gpg" "--version" "GnuPG" "head -1"

    # 压缩工具
    if command -v 7z &> /dev/null; then
        check_cmd_version "7z" "--help" "7-Zip" "head -1"
    elif command -v 7za &> /dev/null; then
        check_cmd_version "7za" "--help" "7-Zip (7za)" "head -1"
    fi
    check_cmd_version "tar" "--version" "tar" "head -1"
    check_cmd_version "gzip" "--version" "gzip" "head -1"
    check_cmd_version "unzip" "-v" "unzip" "head -1"

    # JSON / YAML 处理
    check_cmd_version "jq" "--version" "jq"
    check_cmd_version "yq" "--version" "yq"

    # 文本搜索
    check_cmd_version "rg" "--version" "ripgrep (rg)" "head -1"
    check_cmd_version "fd" "--version" "fd"
    check_cmd_version "fzf" "--version" "fzf" "head -1"

    # 进程/系统
    check_cmd_version "htop" "--version" "htop" "head -1"
    check_cmd_version "lsof" "-v" "lsof" "head -1"
    check_cmd_version "strace" "-V" "strace" "head -1"
    check_cmd_version "ltrace" "-V" "ltrace" "head -1"

    # 终端复用
    check_cmd_version "tmux" "-V" "tmux"

    # 其他常用
    check_cmd_version "git" "--version" "git" "head -1"
    check_cmd_version "vim" "--version" "Vim" "head -1"
    check_cmd_version "neovim" "--version" "Neovim" "head -1"
}

# ── 数据库工具 ──
check_databases() {
    print_header "🗄️  数据库工具"

    # MySQL / MariaDB
    if command -v mysql &> /dev/null; then
        check_cmd_version "mysql" "--version" "MySQL 客户端"
        check_cmd_version "mysqld" "--version" "MySQL 服务端" "head -1"
        check_process_running "mysqld" "MySQL 服务"
        check_process_running "mariadbd" "MariaDB 服务"
        check_process_running "mysql" "MySQL 服务"
    fi

    # PostgreSQL
    check_cmd_version "psql" "--version" "PostgreSQL 客户端"
    check_cmd_version "pg_config" "--version" "PostgreSQL 配置"
    check_process_running "postgres" "PostgreSQL 服务"

    # SQLite
    check_cmd_version "sqlite3" "--version" "SQLite"

    # Redis
    check_cmd_version "redis-cli" "--version" "Redis 客户端"
    check_process_running "redis-server" "Redis 服务"

    # MongoDB
    check_cmd_version "mongosh" "--version" "MongoDB Shell" "head -1"
    check_cmd_version "mongo" "--version" "MongoDB 客户端" "head -1"
    check_process_running "mongod" "MongoDB 服务"
}

# ── 防火墙 ──
check_firewall() {
    print_header "🔥 防火墙"

    local fw_found=0

    # firewalld (RHEL 系)
    if command -v firewall-cmd &> /dev/null; then
        fw_found=1
        local fw_state
        fw_state=$(firewall-cmd --state 2>&1)
        if echo "$fw_state" | grep -qi "running"; then
            print_info "firewalld" "${GREEN}运行中${NC}"
            local default_zone
            default_zone=$(firewall-cmd --get-default-zone 2>/dev/null)
            [ -n "$default_zone" ] && print_info "firewalld 默认区域" "$default_zone"
        else
            print_warn "firewalld" "未运行"
        fi
    fi

    # ufw (Ubuntu 系)
    if command -v ufw &> /dev/null; then
        fw_found=1
        local ufw_status
        ufw_status=$(ufw status 2>&1 | head -1)
        if echo "$ufw_status" | grep -qi "active"; then
            print_info "ufw" "${GREEN}已启用${NC}"
        else
            print_warn "ufw" "未启用"
        fi
    fi

    # iptables
    if command -v iptables &> /dev/null; then
        fw_found=1
        local ipt_rules
        ipt_rules=$(iptables -L -n 2>/dev/null | grep -c "DROP\|ACCEPT\|REJECT" 2>/dev/null || echo "0")
        if [ "$ipt_rules" -gt 0 ] 2>/dev/null; then
            print_info "iptables" "${GREEN}已配置${NC} ($ipt_rules 条规则)"
        else
            print_info "iptables" "已安装（无规则）"
        fi
    fi

    # pf (macOS / BSD)
    if command -v pfctl &> /dev/null; then
        fw_found=1
        local pf_state
        pf_state=$(pfctl -s info 2>/dev/null | grep "Status" | awk '{print $2}')
        if [ "$pf_state" = "Enabled" ]; then
            print_info "pf (BSD)" "${GREEN}已启用${NC}"
        else
            print_info "pf (BSD)" "未启用"
        fi
    fi

    [ $fw_found -eq 0 ] && print_info "防火墙" "未检测到已知防火墙"
}

# ── SSH 服务 ──
check_ssh() {
    print_header "🔐 SSH 服务"

    local ssh_found=0

    # 检测 SSH 服务运行状态
    if command -v systemctl &> /dev/null; then
        if systemctl is-active --quiet sshd 2>/dev/null; then
            ssh_found=1
            print_info "SSH 服务" "${GREEN}运行中${NC} (systemd)"
        elif systemctl is-active --quiet ssh 2>/dev/null; then
            ssh_found=1
            print_info "SSH 服务" "${GREEN}运行中${NC} (systemd)"
        fi
    fi

    if [ $ssh_found -eq 0 ] && command -v service &> /dev/null; then
        if service sshd status 2>/dev/null | grep -qi "running\|is running"; then
            ssh_found=1
            print_info "SSH 服务" "${GREEN}运行中${NC} (service)"
        elif service ssh status 2>/dev/null | grep -qi "running\|is running"; then
            ssh_found=1
            print_info "SSH 服务" "${GREEN}运行中${NC} (service)"
        fi
    fi

    # macOS: launchctl
    if [ $ssh_found -eq 0 ] && [ "$IS_MAC" -eq 1 ]; then
        if launchctl list 2>/dev/null | grep -q "sshd\|openssh"; then
            ssh_found=1
            print_info "SSH 服务" "${GREEN}运行中${NC} (launchctl)"
        fi
    fi

    # 回退: ps
    if [ $ssh_found -eq 0 ]; then
        if pgrep -x "sshd" > /dev/null 2>&1; then
            ssh_found=1
            local ssh_pid
            ssh_pid=$(pgrep -x "sshd" | head -1)
            print_info "SSH 服务" "${GREEN}运行中${NC} (PID: $ssh_pid)"
        fi
    fi

    [ $ssh_found -eq 0 ] && print_warn "SSH 服务" "未运行"

    # 检测 SSH 端口
    local ssh_port="22"
    if [ -f /etc/ssh/sshd_config ]; then
        ssh_port=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
        [ -z "$ssh_port" ] && ssh_port="22"
    elif [ -f /etc/ssh/ssh_config ]; then
        ssh_port=$(grep -E "^Port " /etc/ssh/ssh_config 2>/dev/null | awk '{print $2}')
        [ -z "$ssh_port" ] && ssh_port="22"
    fi
    print_info "SSH 端口" "$ssh_port"

    # 密码认证状态
    if [ -f /etc/ssh/sshd_config ]; then
        local pass_auth
        pass_auth=$(grep -E "^PasswordAuthentication " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
        if [ "$pass_auth" = "yes" ]; then
            print_warn "密码认证" "已启用"
        elif [ "$pass_auth" = "no" ]; then
            print_info "密码认证" "已禁用"
        else
            print_warn "密码认证" "未显式配置（默认可能为 yes）"
        fi

        # 密钥认证状态
        local pubkey_auth
        pubkey_auth=$(grep -E "^PubkeyAuthentication " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
        if [ "$pubkey_auth" = "yes" ]; then
            print_info "密钥认证" "已启用"
        elif [ "$pubkey_auth" = "no" ]; then
            print_warn "密钥认证" "已禁用"
        else
            print_info "密钥认证" "未显式配置（默认通常为 yes）"
        fi

        # PermitRootLogin
        local root_login
        root_login=$(grep -E "^PermitRootLogin " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
        if [ -n "$root_login" ]; then
            case "$root_login" in
                yes) print_warn "Root 登录" "已允许" ;;
                no) print_info "Root 登录" "已禁用" ;;
                prohibit-password|without-password) print_info "Root 登录" "仅密钥登录" ;;
                *) print_info "Root 登录" "$root_login" ;;
            esac
        fi
    fi
}

# ── 网页服务 ──
check_web_services() {
    print_header "🌍 网页服务"

    local web_found=0

    # Apache (httpd / apache2)
    if command -v httpd &> /dev/null; then
        web_found=1
        check_cmd_version "httpd" "-v" "Apache (httpd)" "head -1"
        check_process_running "httpd" "Apache 进程"
        check_systemd_service "httpd" "Apache 服务"
    elif command -v apache2 &> /dev/null; then
        web_found=1
        check_cmd_version "apache2" "-v" "Apache (apache2)" "head -1"
        check_process_running "apache2" "Apache 进程"
        check_systemd_service "apache2" "Apache 服务"
    fi
    # 主目录
    if [ -f /etc/httpd/conf/httpd.conf ]; then
        local docroot
        docroot=$(grep -E "^DocumentRoot " /etc/httpd/conf/httpd.conf 2>/dev/null | awk '{print $2}' | tr -d '"')
        [ -n "$docroot" ] && print_info "Apache 主目录" "$docroot"
    elif [ -f /etc/apache2/sites-available/000-default.conf ]; then
        local docroot
        docroot=$(grep "DocumentRoot" /etc/apache2/sites-available/000-default.conf 2>/dev/null | awk '{print $2}' | head -1)
        [ -n "$docroot" ] && print_info "Apache 主目录" "$docroot"
    fi

    # Nginx
    if command -v nginx &> /dev/null; then
        web_found=1
        check_cmd_version "nginx" "-v" "Nginx" 2>&1
        if command -v nginx &> /dev/null; then
            local nginx_ver
            nginx_ver=$(nginx -v 2>&1 | head -1)
            print_info "Nginx" "$nginx_ver"
        fi
        check_process_running "nginx" "Nginx 进程"
        check_systemd_service "nginx" "Nginx 服务"
        # 主目录
        if [ -f /etc/nginx/nginx.conf ]; then
            local nginx_root
            nginx_root=$(grep -E "^\s*root " /etc/nginx/nginx.conf 2>/dev/null | head -1 | awk '{print $2}' | tr -d ';')
            [ -n "$nginx_root" ] && print_info "Nginx 主目录" "$nginx_root"
        fi
    fi

    # Caddy
    if command -v caddy &> /dev/null; then
        web_found=1
        check_cmd_version "caddy" "version" "Caddy"
        check_process_running "caddy" "Caddy 进程"
        check_systemd_service "caddy" "Caddy 服务"
    fi

    # lighttpd
    if command -v lighttpd &> /dev/null; then
        web_found=1
        check_cmd_version "lighttpd" "-v" "lighttpd" "head -1"
        check_process_running "lighttpd" "lighttpd 进程"
    fi

    # OpenResty
    if command -v openresty &> /dev/null; then
        web_found=1
        check_cmd_version "openresty" "-v" "OpenResty" 2>&1
        if command -v openresty &> /dev/null; then
            local or_ver
            or_ver=$(openresty -v 2>&1 | head -1)
            print_info "OpenResty" "$or_ver"
        fi
    fi

    # 通用: 检测监听 80/443 的进程
    if [ $web_found -eq 0 ]; then
        local web_proc
        if command -v ss &> /dev/null; then
            web_proc=$(ss -tlnp 2>/dev/null | grep -E ":(80|443|8080|8443) " | head -3 | awk '{print $NF}' | xargs)
        elif command -v lsof &> /dev/null; then
            web_proc=$(lsof -iTCP:80 -iTCP:443 -sTCP:LISTEN -nP 2>/dev/null | awk 'NR>1{print $1}' | sort -u | xargs)
        fi
        if [ -n "$web_proc" ]; then
            web_found=1
            print_info "网页进程" "$web_proc"
        fi
    fi

    [ $web_found -eq 0 ] && print_info "网页服务" "未检测到"
}

# ── 容器服务 ──
check_containers() {
    print_header "🐳 容器服务"

    # Docker
    if command -v docker &> /dev/null; then
        check_cmd_version "docker" "--version" "Docker"
        # Docker 运行状态
        if docker info &>/dev/null 2>&1; then
            print_info "Docker 状态" "${GREEN}运行中${NC}"
            local docker_info
            docker_info=$(docker info --format '{{.Containers}}容器 {{.Images}}镜像 {{.ServerVersion}}' 2>/dev/null)
            [ -n "$docker_info" ] && print_info "Docker 概要" "$docker_info"
        else
            print_warn "Docker 状态" "未运行或无权限"
        fi
        # Docker Compose
        check_cmd_version "docker-compose" "--version" "Docker Compose" "head -1"
        if docker compose version &>/dev/null 2>&1; then
            local compose_ver
            compose_ver=$(docker compose version 2>&1 | head -1)
            print_info "Docker Compose V2" "$compose_ver"
        fi
    fi

    # Kubernetes (kubectl)
    if command -v kubectl &> /dev/null; then
        # --short 已废弃，改用 --client
        local kube_ver
        kube_ver=$(kubectl version --client --output=json 2>/dev/null | grep -o '"gitVersion": "[^"]*"' | cut -d'"' -f4)
        [ -n "$kube_ver" ] && print_info "kubectl" "$kube_ver"

        # 检查集群连接：仅在有配置上下文时才尝试
        local kube_ctx
        kube_ctx=$(kubectl config current-context 2>/dev/null)
        if [ -n "$kube_ctx" ]; then
            print_info "K8s 当前上下文" "$kube_ctx"
            if kubectl cluster-info &>/dev/null 2>&1; then
                print_info "K8s 集群" "${GREEN}已连接${NC}"
            else
                print_warn "K8s 集群" "无法连接"
            fi
        else
            print_info "K8s 集群" "未配置上下文"
        fi

        check_cmd_version "helm" "version --template '{{.Version}}'" "Helm" "head -1"
        check_cmd_version "k9s" "version" "K9s" "head -1"
        check_cmd_version "minikube" "version" "Minikube" "head -1"
    fi
}

# ── CUDA 状态 ──
check_cuda() {
    print_header "🎯 CUDA 状态"

    local cuda_found=0

    # nvcc
    if command -v nvcc &> /dev/null; then
        cuda_found=1
        check_cmd_version "nvcc" "--version" "CUDA (nvcc)" "tail -1"
    fi

    # nvidia-smi
    if command -v nvidia-smi &> /dev/null; then
        cuda_found=1
        local nv_driver nv_cuda
        nv_driver=$(nvidia-smi 2>/dev/null | grep "Driver Version" | awk '{print $6}')
        nv_cuda=$(nvidia-smi 2>/dev/null | grep "CUDA Version" | awk '{print $9}')
        [ -n "$nv_driver" ] && print_info "NVIDIA 驱动" "$nv_driver"
        [ -n "$nv_cuda" ] && print_info "CUDA 版本" "$nv_cuda"
        # GPU 温度
        local nv_temp
        nv_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1)
        [ -n "$nv_temp" ] && print_info "GPU 温度" "${nv_temp}°C"
    fi

    # CUDA 路径
    [ -n "$CUDA_HOME" ] && print_info "CUDA_HOME" "$CUDA_HOME"
    [ -d "/usr/local/cuda" ] && print_info "CUDA 安装路径" "/usr/local/cuda"

    [ $cuda_found -eq 0 ] && print_info "CUDA" "未检测到"
}

# ── 代理状态 ──
check_proxy() {
    print_header "🔀 代理状态"

    local proxy_found=0

    for var in http_proxy https_proxy all_proxy no_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY; do
        local val
        eval "val=\$$var"
        if [ -n "$val" ]; then
            proxy_found=1
            print_info "$var" "$val"
        fi
    done

    [ $proxy_found -eq 0 ] && print_info "代理" "未设置"
}

# ── SELinux 状态 ──
check_selinux() {
    print_header "🛡️  SELinux 状态"

    if command -v getenforce &> /dev/null; then
        local sel_status
        sel_status=$(getenforce 2>/dev/null)
        case "$sel_status" in
            Enforcing) print_info "SELinux" "${RED}强制执行中${NC}" ;;
            Permissive) print_warn "SELinux" "宽容模式（仅记录）" ;;
            Disabled) print_info "SELinux" "已禁用" ;;
            *) print_info "SELinux" "$sel_status" ;;
        esac
    elif command -v sestatus &> /dev/null; then
        local sel_mode
        sel_mode=$(sestatus 2>/dev/null | grep "Current mode" | awk '{print $3}')
        [ -n "$sel_mode" ] && print_info "SELinux 模式" "$sel_mode"
    elif [ -f /etc/selinux/config ]; then
        local sel_config
        sel_config=$(grep -E "^SELINUX=" /etc/selinux/config 2>/dev/null | cut -d= -f2)
        [ -n "$sel_config" ] && print_info "SELinux 配置" "$sel_config"
    else
        print_info "SELinux" "未检测到"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════
# 环境检查主函数
# ═══════════════════════════════════════════════════════════════════════════
run_environment_check() {
    echo ""
    print_header "🔍 环境检查"
    check_languages
    check_basic_tools
    check_databases
    check_firewall
    check_ssh
    check_web_services
    check_containers
    check_cuda
    check_proxy
    check_selinux
    echo ""
}

################################################################################
# ===== 网络端口检查 =====
################################################################################

# 端口号 → 服务名映射表
port_to_service() {
    local port="$1"
    case "$port" in
        21)     echo "FTP" ;;
        22)     echo "SSH" ;;
        23)     echo "Telnet" ;;
        25)     echo "SMTP" ;;
        53)     echo "DNS" ;;
        80)     echo "HTTP" ;;
        88)     echo "Kerberos" ;;
        110)    echo "POP3" ;;
        123)    echo "NTP" ;;
        135)    echo "MSRPC" ;;
        137|138|139) echo "NetBIOS" ;;
        143)    echo "IMAP" ;;
        389)    echo "LDAP" ;;
        443)    echo "HTTPS" ;;
        445)    echo "SMB" ;;
        465)    echo "SMTPS" ;;
        514)    echo "Syslog" ;;
        543)    echo "KPasswd" ;;
        587)    echo "SMTP-Submit" ;;
        636)    echo "LDAPS" ;;
        873)    echo "rsync" ;;
        993)    echo "IMAPS" ;;
        995)    echo "POP3S" ;;
        1080)   echo "SOCKS" ;;
        1194)   echo "OpenVPN" ;;
        1433)   echo "MS-SQL" ;;
        1521)   echo "Oracle" ;;
        1701)   echo "L2TP" ;;
        1723)   echo "PPTP" ;;
        2049)   echo "NFS" ;;
        2082)   echo "cPanel" ;;
        2083)   echo "cPanel-SSL" ;;
        2181)   echo "ZooKeeper" ;;
        2375)   echo "Docker-TCP" ;;
        2376)   echo "Docker-TLS" ;;
        3000)   echo "Grafana/Node" ;;
        3128)   echo "Squid" ;;
        3306)   echo "MySQL" ;;
        3389)   echo "RDP" ;;
        3479)   echo "STUN" ;;
        4000)   echo "Jupyter/Phoenix" ;;
        4369)   echo "RabbitMQ-EPMD" ;;
        4567)   echo "Sinatra" ;;
        5000)   echo "Flask/Synology" ;;
        5044)   echo "Logstash" ;;
        5353)   echo "mDNS" ;;
        5432)   echo "PostgreSQL" ;;
        5601)   echo "Kibana" ;;
        5672)   echo "RabbitMQ" ;;
        5900|5901|5902|5903) echo "VNC" ;;
        5985)   echo "WinRM-HTTP" ;;
        5986)   echo "WinRM-HTTPS" ;;
        6379)   echo "Redis" ;;
        6443)   echo "kube-apiserver" ;;
        7077)   echo "Spark" ;;
        7474)   echo "Neo4j" ;;
        7687)   echo "Neo4j-Bolt" ;;
        8000)   echo "Django/HTTP-Dev" ;;
        8080)   echo "HTTP-Alt/Jenkins" ;;
        8086)   echo "InfluxDB" ;;
        8123)   echo "Home-Assistant" ;;
        8443)   echo "K8s-API/HTTPS-Alt" ;;
        8888)   echo "Jupyter" ;;
        8983)   echo "Solr" ;;
        9000)   echo "PHP-FPM/MinIO" ;;
        9090)   echo "Prometheus" ;;
        9092)   echo "Kafka" ;;
        9100)   echo "Node-Exporter" ;;
        9200)   echo "Elasticsearch" ;;
        9300)   echo "ES-Transport" ;;
        9411)   echo "Zipkin" ;;
        9600)   echo "Logstash-metrics" ;;
        11211)  echo "Memcached" ;;
        15672)  echo "RabbitMQ-Mgmt" ;;
        27017)  echo "MongoDB" ;;
        27018)  echo "MongoDB-Shard" ;;
        *)      echo "" ;;
    esac
}

# 尝试从进程名推断服务
proc_to_service() {
    local proc="$1"
    case "$proc" in
        sshd)           echo "SSH" ;;
        nginx)          echo "Nginx" ;;
        httpd|apache2)  echo "Apache" ;;
        caddy)          echo "Caddy" ;;
        mysqld|mariadbd) echo "MySQL" ;;
        postgres)       echo "PostgreSQL" ;;
        redis-server)   echo "Redis" ;;
        mongod)         echo "MongoDB" ;;
        docker-proxy)   echo "Docker-Proxy" ;;
        java)           echo "Java" ;;
        node)           echo "Node.js" ;;
        python*|uvicorn|gunicorn) echo "Python" ;;
        *)              echo "" ;;
    esac
}

run_network_check() {
    echo ""
    print_header "🌐 网络端口检查"

    # 打印表头
    printf "  ${CYAN}%-8s %-4s %-22s %-20s %s${NC}\n" "端口" "协议" "服务名" "进程" "PID"

    if command -v ss &> /dev/null; then
        # Linux: ss -tlnp
        ss -tlnp 2>/dev/null | grep "LISTEN" | while read -r line; do
            local port proto proc_info
            proto=$(echo "$line" | awk '{print $1}')
            # 提取端口（IPv4 和 IPv6）
            port=$(echo "$line" | awk '{print $4}' | rev | cut -d: -f1 | rev)
            # 跳过非数字端口
            if ! echo "$port" | grep -qE '^[0-9]+$' 2>/dev/null; then
                continue
            fi
            # 提取进程信息
            proc_info=$(echo "$line" | awk '{print $NF}')
            local proc_name proc_pid service_label
            proc_name=$(echo "$proc_info" | sed 's/.*"\(.*\)".*/\1/' | cut -d, -f1 2>/dev/null)
            proc_pid=$(echo "$proc_info" | grep -oE 'pid=[0-9]+' | cut -d= -f2)
            [ -z "$proc_name" ] && proc_name=$(echo "$proc_info" | cut -d, -f2 | xargs)

            service_label=$(port_to_service "$port")
            [ -z "$service_label" ] && service_label=$(proc_to_service "$proc_name")
            [ -z "$service_label" ] && service_label="未知"

            printf "  ${GREEN}%-8s${NC} %-4s ${GREEN}%-22s${NC} %-20s %s\n" \
                "$port" "$proto" "$service_label" "${proc_name:-?}" "${proc_pid:-?}"
        done

    elif command -v lsof &> /dev/null; then
        # macOS / BSD: lsof
        lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | awk 'NR>1' | sort -u -k9,9 | while read -r line; do
            local proc_name proc_pid port
            proc_name=$(echo "$line" | awk '{print $1}')
            proc_pid=$(echo "$line" | awk '{print $2}')
            port=$(echo "$line" | awk '{print $9}' | rev | cut -d: -f1 | rev)
            if ! echo "$port" | grep -qE '^[0-9]+$' 2>/dev/null; then
                continue
            fi

            local service_label
            service_label=$(port_to_service "$port")
            [ -z "$service_label" ] && service_label=$(proc_to_service "$proc_name")
            [ -z "$service_label" ] && service_label="未知"

            printf "  ${GREEN}%-8s${NC} %-4s ${GREEN}%-22s${NC} %-20s %s\n" \
                "$port" "TCP" "$service_label" "$proc_name" "$proc_pid"
        done

    elif command -v netstat &> /dev/null; then
        # 回退: netstat
        netstat -tln 2>/dev/null | grep "LISTEN" | while read -r line; do
            local proto port
            proto=$(echo "$line" | awk '{print $1}')
            port=$(echo "$line" | awk '{print $4}' | rev | cut -d: -f1 | rev)
            if ! echo "$port" | grep -qE '^[0-9]+$' 2>/dev/null; then
                continue
            fi

            local service_label
            service_label=$(port_to_service "$port")
            [ -z "$service_label" ] && service_label="未知"

            printf "  ${GREEN}%-8s${NC} %-4s ${GREEN}%-22s${NC} %-20s %s\n" \
                "$port" "$proto" "$service_label" "?" "?"
        done
    else
        print_error "端口检测" "无法检测（缺少 ss / lsof / netstat）"
    fi

    echo ""
}

################################################################################
# ===== 硬件检查 =====
################################################################################
if [ $MODE_HARDWARE -eq 1 ]; then

################################################################################
# 0. 硬件厂商和设备信息
################################################################################
print_header "🏭 硬件厂商和设备信息"
print_info "平台类型" "$PLATFORM_TYPE"

# ── macOS 硬件检测 ──
if [ $IS_MAC -eq 1 ]; then
    # 使用 system_profiler 获取详细硬件信息
    if command -v system_profiler &> /dev/null; then
        MAC_MODEL=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Model Name" | cut -d: -f2 | xargs)
        MAC_MODEL_ID=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Model Identifier" | cut -d: -f2 | xargs)
        MAC_CHIP=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Chip" | cut -d: -f2 | xargs)
        MAC_SERIAL=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Serial Number" | cut -d: -f2 | xargs)

        [ -n "$MAC_MODEL" ] && print_info "产品型号" "$MAC_MODEL"
        [ -n "$MAC_MODEL_ID" ] && print_info "型号标识符" "$MAC_MODEL_ID"
        [ -n "$MAC_CHIP" ] && print_info "芯片" "$MAC_CHIP"
        [ -n "$MAC_SERIAL" ] && print_info "序列号" "$MAC_SERIAL"
        PRODUCT_NAME="$MAC_MODEL"
    fi

# ── WSL 环境检测 ──
elif [ $IS_WSL -eq 1 ]; then
    # WSL 版本
    if grep -qi "WSL2" /proc/version 2>/dev/null; then
        WSL_VER="WSL 2"
    elif grep -qi "microsoft" /proc/version 2>/dev/null; then
        WSL_VER="WSL 1"
    else
        WSL_VER="WSL (未知版本)"
    fi
    print_info "WSL 版本" "$WSL_VER"

    # 尝试获取 Windows 主机信息
    if command -v powershell.exe &> /dev/null; then
        WIN_OS=$(powershell.exe -Command "(Get-CimInstance Win32_OperatingSystem).Caption" 2>/dev/null | tr -d '\r')
        WIN_VER=$(powershell.exe -Command "[Environment]::OSVersion.VersionString" 2>/dev/null | tr -d '\r')
        [ -n "$WIN_OS" ] && print_info "Windows 版本" "$WIN_OS"
        [ -n "$WIN_VER" ] && print_info "Windows 构建" "$WIN_VER"
    elif command -v wmic.exe &> /dev/null; then
        WIN_OS=$(wmic.exe os get Caption 2>/dev/null | grep -v "Caption" | head -1 | xargs)
        [ -n "$WIN_OS" ] && print_info "Windows 版本" "$WIN_OS"
    fi

# ── Linux 硬件检测（DMI / 设备树 / /proc/cpuinfo）──
else
    # DMI 信息（x86/x86_64 PC）
    if [ -f /sys/class/dmi/id/sys_vendor ]; then
        SYS_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
        [ -n "$SYS_VENDOR" ] && print_info "系统厂商" "$SYS_VENDOR"
    fi

    if [ -f /sys/class/dmi/id/product_name ]; then
        PRODUCT_NAME=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
        [ -n "$PRODUCT_NAME" ] && print_info "产品型号" "$PRODUCT_NAME"
    fi

    if [ -f /sys/class/dmi/id/product_version ]; then
        PRODUCT_VERSION=$(cat /sys/class/dmi/id/product_version 2>/dev/null)
        [ -n "$PRODUCT_VERSION" ] && print_info "产品版本" "$PRODUCT_VERSION"
    fi

    if [ -f /sys/class/dmi/id/product_serial ]; then
        PRODUCT_SERIAL=$(cat /sys/class/dmi/id/product_serial 2>/dev/null)
        if [ -n "$PRODUCT_SERIAL" ] && [ "$PRODUCT_SERIAL" != "System Serial Number" ]; then
            print_info "序列号" "$PRODUCT_SERIAL"
        fi
    fi

    if [ -f /sys/class/dmi/id/board_vendor ]; then
        BOARD_VENDOR=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null)
        [ -n "$BOARD_VENDOR" ] && print_info "主板厂商" "$BOARD_VENDOR"
    fi

    if [ -f /sys/class/dmi/id/board_name ]; then
        BOARD_NAME=$(cat /sys/class/dmi/id/board_name 2>/dev/null)
        [ -n "$BOARD_NAME" ] && print_info "主板型号" "$BOARD_NAME"
    fi

    if [ -f /sys/class/dmi/id/bios_vendor ]; then
        BIOS_VENDOR=$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null)
        [ -n "$BIOS_VENDOR" ] && print_info "BIOS 厂商" "$BIOS_VENDOR"
    fi

    if [ -f /sys/class/dmi/id/bios_version ]; then
        BIOS_VERSION=$(cat /sys/class/dmi/id/bios_version 2>/dev/null)
        [ -n "$BIOS_VERSION" ] && print_info "BIOS 版本" "$BIOS_VERSION"
    fi

    if [ -f /sys/class/dmi/id/bios_date ]; then
        BIOS_DATE=$(cat /sys/class/dmi/id/bios_date 2>/dev/null)
        [ -n "$BIOS_DATE" ] && print_info "BIOS 发布日期" "$BIOS_DATE"
    fi

    if [ -f /sys/class/dmi/id/chassis_vendor ]; then
        CHASSIS_VENDOR=$(cat /sys/class/dmi/id/chassis_vendor 2>/dev/null)
        [ -n "$CHASSIS_VENDOR" ] && print_info "机箱厂商" "$CHASSIS_VENDOR"
    fi

    if [ -f /sys/class/dmi/id/chassis_type ]; then
        CHASSIS_TYPE=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)
        case "$CHASSIS_TYPE" in
            1) CHASSIS_NAME="台式机" ;;
            2) CHASSIS_NAME="笔记本" ;;
            3) CHASSIS_NAME="一体机" ;;
            4) CHASSIS_NAME="服务器" ;;
            5) CHASSIS_NAME="工作站" ;;
            *) CHASSIS_NAME="其他 ($CHASSIS_TYPE)" ;;
        esac
        [ -n "$CHASSIS_TYPE" ] && print_info "机箱类型" "$CHASSIS_NAME"
    fi

    # ── 树莓派专用检测（/proc/cpuinfo）──
    if [ $IS_RPI -eq 1 ]; then
        RPI_HARDWARE=$(grep -m1 "Hardware" /proc/cpuinfo | cut -d: -f2 | xargs)
        RPI_REVISION=$(grep -m1 "Revision" /proc/cpuinfo | cut -d: -f2 | xargs)
        RPI_MODEL=$(grep -m1 "Model" /proc/cpuinfo | cut -d: -f2 | xargs)
        RPI_SERIAL=$(grep -m1 "Serial" /proc/cpuinfo | cut -d: -f2 | xargs)

        # 根据 Revision 解析具体型号
        # 参考: https://www.raspberrypi.com/documentation/computers/raspberry-pi.html
        case "$RPI_REVISION" in
            900021) RPI_REV_NAME="Model A+ 1.1" ;;
            900032) RPI_REV_NAME="Model B+ 1.2" ;;
            900092) RPI_REV_NAME="Pi Zero 1.2" ;;
            900093) RPI_REV_NAME="Pi Zero 1.3" ;;
            9000c1) RPI_REV_NAME="Pi Zero W 1.1" ;;
            9020e0) RPI_REV_NAME="Model 3A+ 1.0" ;;
            920021) RPI_REV_NAME="Pi Zero 2 W 1.0" ;;
            a02082) RPI_REV_NAME="Model 3B 1.2" ;;
            a020a0) RPI_REV_NAME="Compute Module 3 1.0" ;;
            a020d3) RPI_REV_NAME="Model 3B+ 1.3" ;;
            a02100) RPI_REV_NAME="Compute Module 3+ 1.0" ;;
            a03111) RPI_REV_NAME="Model 4B 1.1" ;;
            b03111) RPI_REV_NAME="Model 4B 1.1" ;;
            b03112) RPI_REV_NAME="Model 4B 1.2" ;;
            b03114) RPI_REV_NAME="Model 4B 1.4" ;;
            b03115) RPI_REV_NAME="Model 4B 1.5" ;;
            c03111) RPI_REV_NAME="Model 4B 1.3" ;;
            c03112) RPI_REV_NAME="Model 4B 1.4" ;;
            c03114) RPI_REV_NAME="Model 4B 1.5" ;;
            c03115) RPI_REV_NAME="Model 4B 1.6" ;;
            d03114) RPI_REV_NAME="Model 4B 1.4" ;;
            d03115) RPI_REV_NAME="Model 4B 1.6" ;;
            c04170) RPI_REV_NAME="Model 5B 1.0" ;;
            d04170) RPI_REV_NAME="Model 5B 1.0" ;;
        esac

        [ -n "$RPI_MODEL" ] && print_info "树莓派型号" "$RPI_MODEL" && PRODUCT_NAME="$RPI_MODEL"
        [ -n "$RPI_REVISION" ] && print_info "版本代码" "$RPI_REVISION${RPI_REV_NAME:+ → $RPI_REV_NAME}"
        [ -n "$RPI_HARDWARE" ] && print_info "SoC" "$RPI_HARDWARE"
        if [ -n "$RPI_SERIAL" ] && [ "$RPI_SERIAL" != "0000000000000000" ]; then
            print_info "序列号" "$RPI_SERIAL"
        fi
    fi

    # ── 设备树回退（ARM / RISC-V / 嵌入式板卡）──
    if [ -z "$PRODUCT_NAME" ] && [ -f /proc/device-tree/model ]; then
        DT_MODEL=$(tr '\0' '\n' < /proc/device-tree/model 2>/dev/null)
        if [ -n "$DT_MODEL" ]; then
            print_info "设备型号 (DT)" "$DT_MODEL"
            PRODUCT_NAME="$DT_MODEL"
        fi
    fi

    if [ -f /proc/device-tree/compatible ]; then
        DT_COMPAT=$(tr '\0' ',' < /proc/device-tree/compatible 2>/dev/null | sed 's/,$//')
        if [ -n "$DT_COMPAT" ]; then
            print_info "兼容平台 (DT)" "$DT_COMPAT"
        fi
    fi

    if [ -z "$PRODUCT_SERIAL" ] && [ -f /proc/device-tree/serial-number ]; then
        DT_SERIAL=$(tr '\0' '\n' < /proc/device-tree/serial-number 2>/dev/null)
        if [ -n "$DT_SERIAL" ] && [ "$DT_SERIAL" != "0" ] && [ "$DT_SERIAL" != "0000000000000000" ]; then
            print_info "序列号 (DT)" "$DT_SERIAL"
        fi
    fi
fi

################################################################################
# 1. 系统基本信息
################################################################################
print_header "📱 系统基本信息"

# 主机名
HOSTNAME=$(hostname)
print_info "主机名" "$HOSTNAME"

# 系统架构
print_info "系统架构" "$OS_ARCH"

# 内核版本
KERNEL=$(uname -r)
print_info "内核版本" "$KERNEL"

# 操作系统
print_info "操作系统" "$OS_NAME"

# macOS 版本号
if [ $IS_MAC -eq 1 ]; then
    MACOS_VER=$(sw_vers -productVersion 2>/dev/null)
    [ -n "$MACOS_VER" ] && print_info "macOS 版本" "$MACOS_VER"
fi

################################################################################
# 2. 发行版信息
################################################################################
print_header "🐧 发行版信息"

if [ $IS_MAC -eq 1 ]; then
    # macOS: 用 sw_vers 或 system_profiler
    if command -v sw_vers &> /dev/null; then
        print_info "产品名称" "$(sw_vers -productName 2>/dev/null)"
        print_info "产品版本" "$(sw_vers -productVersion 2>/dev/null)"
        print_info "构建版本" "$(sw_vers -buildVersion 2>/dev/null)"
    fi
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    print_info "发行版名称" "${PRETTY_NAME:-$NAME}"
    print_info "版本号" "${VERSION_ID:-$VERSION}"
    [ -n "$HOME_URL" ] && print_info "官方网站" "$HOME_URL"
elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    print_info "发行版名称" "$DISTRIB_DESCRIPTION"
    print_info "版本号" "$DISTRIB_RELEASE"
elif [ -f /etc/redhat-release ]; then
    DISTRO=$(cat /etc/redhat-release)
    print_info "发行版信息" "$DISTRO"
else
    print_error "发行版信息" "无法检测"
fi

# 系统启动时间
if [ $IS_MAC -eq 1 ]; then
    # macOS 的 uptime 不支持 -p
    UPTIME=$(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}' | xargs)
else
    UPTIME=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')
fi
print_info "运行时间" "$UPTIME"

################################################################################
# 3. CPU 信息
################################################################################
print_header "⚙️  CPU 信息"

if [ $IS_MAC -eq 1 ]; then
    # ── macOS CPU 检测 ──
    CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
    print_info "CPU 型号" "$CPU_MODEL"

    CPU_PHYSICAL=$(sysctl -n hw.physicalcpu 2>/dev/null)
    CPU_LOGICAL=$(sysctl -n hw.logicalcpu 2>/dev/null)
    print_info "物理核心数" "$CPU_PHYSICAL"
    print_info "逻辑核心数" "$CPU_LOGICAL"

    CPU_FREQ_RAW=$(sysctl -n hw.cpufrequency 2>/dev/null)
    if [ -n "$CPU_FREQ_RAW" ] && [ "$CPU_FREQ_RAW" -gt 0 ] 2>/dev/null; then
        CPU_FREQ=$(awk -v freq="$CPU_FREQ_RAW" 'BEGIN {printf "%.2f GHz", freq/1000000000}')
        print_info "CPU 频率" "$CPU_FREQ"
    fi

    CPU_CACHE=$(sysctl -n hw.l3cachesize 2>/dev/null)
    if [ -n "$CPU_CACHE" ] && [ "$CPU_CACHE" -gt 0 ] 2>/dev/null; then
        print_info "L3 缓存" "$(awk -v c="$CPU_CACHE" 'BEGIN {printf "%d KB", c/1024}')"
    fi

    print_info "CPU 架构" "$(sysctl -n machdep.cpu.vendor 2>/dev/null) / $(uname -m)"

elif [ -f /proc/cpuinfo ]; then
    # ── Linux CPU 检测 ──
    # CPU 型号
    CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
    # 树莓派等 ARM 设备使用不同字段
    [ -z "$CPU_MODEL" ] && CPU_MODEL=$(grep -m1 "Model" /proc/cpuinfo | cut -d: -f2 | xargs)
    # 其他 ARM aarch64 设备（手机、部分 SBC 等）
    [ -z "$CPU_MODEL" ] && CPU_MODEL=$(grep -m1 "^Processor" /proc/cpuinfo | cut -d: -f2 | xargs)
    [ -z "$CPU_MODEL" ] && CPU_MODEL=$(grep -m1 "^Hardware" /proc/cpuinfo | cut -d: -f2 | xargs)
    # lscpu 后备（部分 ARM 设备 /proc/cpuinfo 无型号字段）
    [ -z "$CPU_MODEL" ] && CPU_MODEL=$(lscpu 2>/dev/null | grep "Model name" | cut -d: -f2 | xargs)
    print_info "CPU 型号" "$CPU_MODEL"

    # CPU 核心数
    CPU_CORES=$(grep -c "^processor" /proc/cpuinfo)
    print_info "CPU 核心数" "$CPU_CORES"

    # CPU 线程数
    CPU_THREADS=$(grep "siblings" /proc/cpuinfo | head -1 | awk '{print $3}')
    [ -z "$CPU_THREADS" ] && CPU_THREADS=$CPU_CORES
    print_info "CPU 线程数" "$CPU_THREADS"

    # CPU 频率
    CPU_FREQ=$(grep "cpu MHz" /proc/cpuinfo | head -1 | awk '{printf "%.2f GHz", $4/1000}')
    [ -z "$CPU_FREQ" ] && CPU_FREQ=$(lscpu 2>/dev/null | grep "CPU max MHz" | awk '{printf "%.2f GHz", $4/1000}')
    [ -n "$CPU_FREQ" ] && print_info "CPU 频率" "$CPU_FREQ"

    # CPU 缓存
    CPU_CACHE=$(grep "cache size" /proc/cpuinfo | head -1 | awk '{print $4}')
    [ -n "$CPU_CACHE" ] && print_info "L3 缓存" "$CPU_CACHE"

    # CPU 架构
    if command -v lscpu &> /dev/null; then
        CPU_ARCH=$(lscpu | grep "Architecture" | awk -F: '{print $2}' | xargs)
        [ -n "$CPU_ARCH" ] && print_info "CPU 架构" "$CPU_ARCH"
    else
        print_info "CPU 架构" "$(uname -m)"
    fi
else
    print_error "CPU 信息" "无法读取 CPU 信息"
fi

# CPU 使用率（兼容 Linux / macOS / WSL）
if [ $IS_MAC -eq 1 ]; then
    # macOS: top -l1 -n0 获取 1 次采样、不显示进程
    CPU_USAGE=$(top -l1 -n0 2>/dev/null | grep "CPU usage" | awk '{print $3}' | cut -d'%' -f1)
    [ -z "$CPU_USAGE" ] && CPU_USAGE=$(ps aux | awk 'BEGIN {sum=0} {sum+=$3} END {printf "%.1f", sum}')
else
    # Linux / WSL: top -bn1 批处理模式
    CPU_USAGE=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    # 备选：从 /proc/stat 计算（更精确）
    if [ -z "$CPU_USAGE" ] && [ -f /proc/stat ]; then
        CPU_LINE1=$(head -1 /proc/stat)
        sleep 0.3
        CPU_LINE2=$(head -1 /proc/stat)
        IDLE1=$(echo "$CPU_LINE1" | awk '{print $5}')
        TOTAL1=$(echo "$CPU_LINE1" | awk '{for(i=2;i<=NF;i++) sum+=$i; print sum}')
        IDLE2=$(echo "$CPU_LINE2" | awk '{print $5}')
        TOTAL2=$(echo "$CPU_LINE2" | awk '{for(i=2;i<=NF;i++) sum+=$i; print sum}')
        if [ -n "$TOTAL1" ] && [ -n "$TOTAL2" ] && [ "$TOTAL2" != "$TOTAL1" ]; then
            CPU_USAGE=$(awk -v i1="$IDLE1" -v i2="$IDLE2" -v t1="$TOTAL1" -v t2="$TOTAL2" \
                'BEGIN {printf "%.1f", 100 - (i2-i1)/(t2-t1)*100}')
        fi
    fi
    [ -z "$CPU_USAGE" ] && CPU_USAGE=$(ps aux | awk 'BEGIN {sum=0} {sum+=$3} END {printf "%.1f", sum}')
fi
print_info "CPU 使用率" "${CPU_USAGE}%"

################################################################################
# 4. GPU 信息
################################################################################
print_header "🎮 GPU 信息"

GPU_FOUND=0

if [ $IS_MAC -eq 1 ]; then
    # ── macOS GPU 检测 ──
    if command -v system_profiler &> /dev/null; then
        GPU_FOUND=1
        echo -e "  ${CYAN}GPU (Apple):${NC}"
        system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset Model|VRAM|Vendor|Display Type|Resolution" | while read -r line; do
            KEY=$(echo "$line" | cut -d: -f1 | xargs)
            VAL=$(echo "$line" | cut -d: -f2- | xargs)
            case "$KEY" in
                "Chipset Model") printf "    ${GREEN}%s${NC}: %s\n" "GPU 型号" "$VAL" ;;
                "VRAM"*)         printf "    ${CYAN}  └─ VRAM${NC}: ${GREEN}%s${NC}\n" "$VAL" ;;
                "Vendor")        printf "    ${CYAN}  └─ 厂商${NC}: ${GREEN}%s${NC}\n" "$VAL" ;;
            esac
        done
        # 显示器分辨率
        RES=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Resolution" | head -1 | cut -d: -f2 | xargs)
        [ -n "$RES" ] && printf "    ${CYAN}  └─ 分辨率${NC}: ${GREEN}%s${NC}\n" "$RES"
    fi
else
    # ── Linux / WSL GPU 检测 ──
    # 检查 NVIDIA GPU
    if command -v nvidia-smi &> /dev/null; then
        GPU_FOUND=1
        echo -e "  ${CYAN}NVIDIA GPU:${NC}"
        nvidia-smi --query-gpu=index,name,driver_version,memory.total,memory.used \
            --format=csv,noheader,nounits 2>/dev/null | while IFS=',' read -r idx name driver mem_total mem_used; do
            printf "    ${GREEN}GPU %s${NC}: %s\n" "$idx" "$name"
            printf "    ${CYAN}  ├─ 驱动版本${NC}: ${GREEN}%s${NC}\n" "$driver"
            printf "    ${CYAN}  ├─ 总内存${NC}: ${GREEN}%s MB${NC}\n" "$mem_total"
            printf "    ${CYAN}  └─ 已用内存${NC}: ${GREEN}%s MB${NC}\n" "$mem_used"
        done
    fi

    # 检查 AMD GPU
    if command -v rocm-smi &> /dev/null; then
        GPU_FOUND=1
        echo -e "  ${CYAN}AMD GPU (ROCm):${NC}"
        rocm-smi --showproductname --showmeminfo --json 2>/dev/null | grep -q "product_name" && \
            print_info "AMD GPU" "已检测到 (使用 rocm-smi 查看详情)"
    fi

    # 树莓派 GPU（VideoCore）
    if [ $IS_RPI -eq 1 ]; then
        GPU_FOUND=1
        echo -e "  ${CYAN}树莓派 GPU:${NC}"
        RPI_GPU="VideoCore"
        # 根据 SoC 判断 GPU 版本
        case "$RPI_HARDWARE" in
            BCM2835*) RPI_GPU="VideoCore IV" ;;
            BCM2836*) RPI_GPU="VideoCore IV" ;;
            BCM2837*) RPI_GPU="VideoCore IV" ;;
            BCM2711*) RPI_GPU="VideoCore VI" ;;
            BCM2712*) RPI_GPU="VideoCore VII" ;;
        esac
        print_info "GPU 型号" "$RPI_GPU"
        # GPU 内存（树莓派特有）
        if command -v vcgencmd &> /dev/null; then
            GPU_MEM=$(vcgencmd get_mem gpu 2>/dev/null | cut -d= -f2)
            [ -n "$GPU_MEM" ] && print_info "GPU 内存" "$GPU_MEM"
        fi
    fi

    # 检查 Intel GPU
    if command -v lspci &> /dev/null; then
        if lspci 2>/dev/null | grep -i "intel.*graphics" > /dev/null; then
            GPU_FOUND=1
            INTEL_GPU=$(lspci 2>/dev/null | grep -i "intel.*graphics" | head -1 | cut -d: -f3)
            print_info "Intel GPU" "$INTEL_GPU"
        fi
    fi

    # 通用 GPU 检查（lspci）
    if ! command -v lspci &> /dev/null; then
        if [ $GPU_FOUND -eq 0 ]; then
            # 检查 DRM 设备（无 lspci 时的回退）
            if [ -d /sys/class/drm ]; then
                GPU_FOUND=1
                echo -e "  ${CYAN}DRM 设备:${NC}"
                for card in /sys/class/drm/card*; do
                    if [ -f "$card/device/vendor" ] && [ -f "$card/device/device" ]; then
                        VENDOR_ID=$(cat "$card/device/vendor" 2>/dev/null)
                        DEVICE_ID=$(cat "$card/device/device" 2>/dev/null)
                        CARD_NAME=$(basename "$card")
                        printf "    ${GREEN}%s${NC}: vendor=%s device=%s\n" "$CARD_NAME" "$VENDOR_ID" "$DEVICE_ID"
                    fi
                done
            fi
            if [ $GPU_FOUND -eq 0 ]; then
                print_error "GPU 信息" "未检测到 GPU 设备"
            fi
        fi
    else
        if [ $GPU_FOUND -eq 0 ]; then
            GPU_COUNT=$(lspci 2>/dev/null | grep -iE "VGA|3D|Display" | wc -l)
            if [ $GPU_COUNT -gt 0 ]; then
                echo -e "  ${CYAN}其他 GPU 设备:${NC}"
                lspci 2>/dev/null | grep -iE "VGA|3D|Display" | while read -r line; do
                    GPU_NAME=$(echo "$line" | cut -d: -f3)
                    printf "    ${GREEN}%s${NC}\n" "$GPU_NAME"
                done
            else
                print_error "GPU 信息" "未检测到独立 GPU (集成显卡)"
            fi
        fi
    fi
fi

################################################################################
# 5. 内存信息
################################################################################
print_header "💾 内存信息"

if [ $IS_MAC -eq 1 ]; then
    # ── macOS 内存检测 ──
    MEM_TOTAL_BYTES=$(sysctl -n hw.memsize 2>/dev/null)
    if [ -n "$MEM_TOTAL_BYTES" ]; then
        MEM_TOTAL=$(awk -v b="$MEM_TOTAL_BYTES" 'BEGIN {printf "%.2f GB", b/1024/1024/1024}')
        print_info "总内存" "$MEM_TOTAL"
    fi

    # 使用 vm_stat 获取内存使用情况（macOS 页面大小 = 16384 在 Apple Silicon 上，4096 在 Intel 上）
    PAGE_SIZE=$(vm_stat 2>/dev/null | grep "page size" | awk '{print $8}')
    [ -z "$PAGE_SIZE" ] && PAGE_SIZE=4096

    if command -v vm_stat &> /dev/null; then
        VM_STAT=$(vm_stat)
        PAGES_FREE=$(echo "$VM_STAT" | grep "Pages free" | awk '{print $3}' | tr -d '.')
        PAGES_ACTIVE=$(echo "$VM_STAT" | grep "Pages active" | awk '{print $3}' | tr -d '.')
        PAGES_INACTIVE=$(echo "$VM_STAT" | grep "Pages inactive" | awk '{print $3}' | tr -d '.')
        PAGES_WIRED=$(echo "$VM_STAT" | grep "Pages wired" | awk '{print $4}' | tr -d '.')
        PAGES_SPECULATIVE=$(echo "$VM_STAT" | grep "Pages speculative" | awk '{print $3}' | tr -d '.')

        if [ -n "$PAGES_FREE" ] && [ -n "$PAGE_SIZE" ]; then
            MEM_FREE=$(awk -v p="$PAGES_FREE" -v s="$PAGE_SIZE" 'BEGIN {printf "%.2f GB", p*s/1024/1024/1024}')
            print_info "空闲内存" "$MEM_FREE"
        fi
        if [ -n "$PAGES_WIRED" ] && [ -n "$PAGE_SIZE" ]; then
            MEM_WIRED=$(awk -v p="$PAGES_WIRED" -v s="$PAGE_SIZE" 'BEGIN {printf "%.2f GB", p*s/1024/1024/1024}')
            print_info "已锁定内存" "$MEM_WIRED"
        fi

        # 计算内存压力
        if command -v memory_pressure &> /dev/null; then
            MEM_PRESSURE=$(memory_pressure 2>/dev/null | grep "System-wide memory free percentage" | awk '{print $5}' | tr -d '%')
            if [ -n "$MEM_PRESSURE" ]; then
                print_info "可用内存占比" "${MEM_PRESSURE}%"
            fi
        fi
    fi

    # Swap 信息
    if command -v sysctl &> /dev/null; then
        SWAP_USAGE=$(sysctl -n vm.swapusage 2>/dev/null)
        if [ -n "$SWAP_USAGE" ]; then
            # 格式: "total = 1024.00M  used = 512.00M  free = 512.00M"
            SWAP_TOTAL=$(echo "$SWAP_USAGE" | grep -o 'total = [^ ]*' | awk '{print $3}')
            SWAP_USED=$(echo "$SWAP_USAGE" | grep -o 'used = [^ ]*' | awk '{print $3}')
            print_info "Swap 总大小" "$SWAP_TOTAL"
            print_info "Swap 已用" "$SWAP_USED"
        fi
    fi

elif [ -f /proc/meminfo ]; then
    # ── Linux / WSL 内存检测 ──
    # 总内存
    MEM_TOTAL=$(grep "MemTotal" /proc/meminfo | awk '{printf "%.2f GB", $2/1024/1024}')
    print_info "总内存" "$MEM_TOTAL"

    # 可用内存
    MEM_AVAILABLE=$(grep "MemAvailable" /proc/meminfo | awk '{printf "%.2f GB", $2/1024/1024}')
    print_info "可用内存" "$MEM_AVAILABLE"

    # 已用内存
    MEM_USED=$(grep "MemTotal\|MemAvailable" /proc/meminfo | awk 'NR==1{total=$2} NR==2{avail=$2} END{printf "%.2f GB", (total-avail)/1024/1024}')
    print_info "已用内存" "$MEM_USED"

    # 内存使用率
    MEM_PERCENT=$(grep "MemTotal\|MemAvailable" /proc/meminfo | awk 'NR==1{total=$2} NR==2{avail=$2} END{printf "%.1f%%", (total-avail)/total*100}')
    print_info "内存使用率" "$MEM_PERCENT"

    # Swap 内存
    SWAP_TOTAL=$(grep "SwapTotal" /proc/meminfo | awk '{printf "%.2f GB", $2/1024/1024}')
    print_info "Swap 总大小" "$SWAP_TOTAL"

    SWAP_USED=$(grep "SwapTotal\|SwapFree" /proc/meminfo | awk 'NR==1{total=$2} NR==2{free=$2} END{printf "%.2f GB", (total-free)/1024/1024}')
    print_info "Swap 已用" "$SWAP_USED"
else
    print_error "内存信息" "无法读取内存信息"
fi

################################################################################
# 6. 存储信息
################################################################################
print_header "💿 存储信息"

if command -v df &> /dev/null; then
    echo -e "  ${CYAN}磁盘使用情况:${NC}"

    # 根分区信息
    ROOT_INFO=$(df -h / | tail -1)
    ROOT_SIZE=$(echo "$ROOT_INFO" | awk '{print $2}')
    ROOT_USED=$(echo "$ROOT_INFO" | awk '{print $3}')
    ROOT_AVAIL=$(echo "$ROOT_INFO" | awk '{print $4}')
    ROOT_PERCENT=$(echo "$ROOT_INFO" | awk '{print $5}')

    echo -e "    ${GREEN}根分区 (/)${NC}"
    echo -e "    ${CYAN}  ├─ 总大小${NC}: ${GREEN}${ROOT_SIZE}${NC}"
    echo -e "    ${CYAN}  ├─ 已用${NC}: ${GREEN}${ROOT_USED}${NC}"
    echo -e "    ${CYAN}  ├─ 可用${NC}: ${GREEN}${ROOT_AVAIL}${NC}"
    echo -e "    ${CYAN}  └─ 使用率${NC}: ${GREEN}${ROOT_PERCENT}${NC}"

    # 显示其他主要挂载点（Linux）
    if [ $IS_MAC -eq 0 ]; then
        df -h 2>/dev/null | grep -E "^/dev/" | grep -v "^/dev/loop" | tail -n +2 | while read -r line; do
            MOUNT=$(echo "$line" | awk '{print $NF}')
            USAGE=$(echo "$line" | awk '{print $5}')
            SIZE=$(echo "$line" | awk '{print $2}')
            printf "    ${GREEN}%s${NC} - 大小: ${GREEN}%s${NC}, 使用率: ${GREEN}%s${NC}\n" "$MOUNT" "$SIZE" "$USAGE"
        done
    fi
else
    print_error "存储信息" "df 命令不可用"
fi

# 磁盘设备信息
if [ $IS_MAC -eq 1 ]; then
    # macOS: 使用 diskutil
    if command -v diskutil &> /dev/null; then
        echo -e "  ${CYAN}磁盘设备:${NC}"
        diskutil list 2>/dev/null | grep "^/dev/disk" | grep -v "disk0s" | while read -r line; do
            DISK=$(echo "$line" | awk '{print $1}')
            SIZE=$(echo "$line" | awk '{for(i=4;i<=NF;i++) printf "%s ", $i; print ""}' | xargs)
            printf "    ${GREEN}%s${NC} - %s\n" "$DISK" "$SIZE"
        done
    fi
elif command -v lsblk &> /dev/null; then
    # Linux: 使用 lsblk
    echo -e "  ${CYAN}磁盘设备:${NC}"
    lsblk -d -n -o NAME,SIZE,TYPE,VENDOR,MODEL 2>/dev/null | while read -r name size type vendor model; do
        if [ "$type" = "disk" ]; then
            printf "    ${GREEN}/dev/%s${NC} - %s (%s %s)\n" "$name" "$size" "$vendor" "$model"
        fi
    done
fi

################################################################################
# 7. 网络信息
################################################################################
print_header "🌐 网络信息"

if [ $IS_MAC -eq 1 ]; then
    # macOS: 使用 ifconfig（ip 命令不可用）
    if command -v ifconfig &> /dev/null; then
        echo -e "  ${CYAN}网络接口:${NC}"
        ifconfig 2>/dev/null | grep "^[a-z]" | awk '{print $1}' | cut -d: -f1 | while read -r iface; do
            IP=$(ifconfig "$iface" 2>/dev/null | grep "inet " | awk '{print $2}')
            STATUS=$(ifconfig "$iface" 2>/dev/null | grep "status" | awk '{print $2}')
            if [ -n "$IP" ]; then
                printf "    ${GREEN}%s${NC} [${GREEN}%s${NC}]: ${GREEN}%s${NC}\n" "$iface" "${STATUS:-up}" "$IP"
            fi
        done
    fi
elif command -v ip &> /dev/null; then
    # Linux: 优先使用 ip 命令
    echo -e "  ${CYAN}网络接口:${NC}"
    ip link show 2>/dev/null | grep "^[0-9]" | while read -r line; do
        IFACE=$(echo "$line" | awk '{print $2}' | cut -d: -f1)
        if [ "$IFACE" != "lo" ]; then
            IP=$(ip addr show "$IFACE" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
            STATUS=$(echo "$line" | grep -o "UP\|DOWN" | head -1)
            if [ -n "$IP" ]; then
                printf "    ${GREEN}%s${NC} [${GREEN}%s${NC}]: ${GREEN}%s${NC}\n" "$IFACE" "$STATUS" "$IP"
            fi
        fi
    done
elif command -v ifconfig &> /dev/null; then
    echo -e "  ${CYAN}网络接口:${NC}"
    ifconfig 2>/dev/null | grep "^[a-z]" | awk '{print $1}' | while read -r iface; do
        IP=$(ifconfig "$iface" 2>/dev/null | grep "inet " | awk '{print $2}')
        if [ -n "$IP" ]; then
            printf "    ${GREEN}%s${NC}: ${GREEN}%s${NC}\n" "$iface" "$IP"
        fi
    done
else
    print_error "网络信息" "ip/ifconfig 命令不可用"
fi

# PCIe 网卡检测（有线 / 无线）
if command -v lspci &> /dev/null; then
    PCI_NET=$(lspci 2>/dev/null | grep -iE "Network controller|Ethernet controller")
    if [ -n "$PCI_NET" ]; then
        echo ""
        print_header "🔌 PCIe 网卡"
        echo "$PCI_NET" | while read -r line; do
            PCI_ADDR=$(echo "$line" | awk '{print $1}')
            PCI_DESC=$(echo "$line" | cut -d: -f2- | sed 's/^[[:space:]]*//')
            printf "  ${CYAN}%-30s${NC} : ${GREEN}%s${NC}\n" "$PCI_ADDR" "$PCI_DESC"
        done
    fi
fi

################################################################################
# 总结
################################################################################
echo ""
print_header "✅ 系统信息检查完成"
echo ""

fi  # MODE_HARDWARE

################################################################################
# 调度入口
################################################################################
if [ $MODE_ENVIRONMENT -eq 1 ]; then
    run_environment_check
    print_header "✅ 环境检查完成"
    echo ""
fi

if [ $MODE_NETWORK -eq 1 ]; then
    run_network_check
    print_header "✅ 网络端口检查完成"
    echo ""
fi
