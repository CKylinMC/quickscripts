#!/bin/bash
# =============================================
#  CentOS 7.9 一键安装 PHP 7.3.33 + Nginx
#  可断点续装 / 自动清理旧环境
#  增强版：包含错误处理和详细日志
# =============================================
set -euo pipefail
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

################  仅 root 可执行  ################
[[ $EUID -ne 0 ]] && echo "请用 root 执行" && exit 1

################  全局变量  ################
LOCK_DIR=/opt/lnmp73
LOCK_FILE=$LOCK_DIR/.lock
LOG_FILE="/tmp/php_install_$(date +%Y%m%d_%H%M%S).log"
PHP_VER=73          # Remi 仓库版本号
PHP_RT_VER=7.3.33   # 运行时真正版本
NGINX_REPO=/etc/yum.repos.d/nginx.repo

mkdir -p "$LOCK_DIR"
touch "$LOCK_FILE"

# 日志函数
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$LOG_FILE" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" | tee -a "$LOG_FILE"
}

# 错误处理
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "脚本在第 $line_number 行失败，退出码: $exit_code"
    log_error "查看详细日志: $LOG_FILE"
    exit $exit_code
}

trap 'handle_error $? $LINENO' ERR

log_info "PHP 7.3.33 + Nginx 安装开始，日志文件: $LOG_FILE"

function mark(){
    echo "$1" >> "$LOCK_FILE"
    log_info "步骤完成: $1"
}

function done_step(){
    grep -qx "$1" "$LOCK_FILE"
}

# 检查服务状态
check_service() {
    local service=$1
    if systemctl is-active --quiet "$service"; then
        log_success "$service 服务运行正常"
        return 0
    else
        log_error "$service 服务未运行"
        log_info "查看服务状态: systemctl status $service"
        log_info "查看服务日志: journalctl -u $service --since '10 minutes ago'"
        return 1
    fi
}

# 诊断 PHP-FPM 问题
diagnose_php_fpm() {
    log_info "诊断 PHP-FPM 问题..."
    
    echo "=== PHP-FPM 服务状态 ===" | tee -a "$LOG_FILE"
    systemctl status php-fpm --no-pager -l | tee -a "$LOG_FILE" || true
    
    echo "=== PHP-FPM 配置文件检查 ===" | tee -a "$LOG_FILE"
    if [[ -f /etc/php-fpm.conf ]]; then
        log_info "主配置文件存在: /etc/php-fpm.conf"
    else
        log_error "主配置文件不存在: /etc/php-fpm.conf"
    fi
    
    if [[ -f /etc/php-fpm.d/www.conf ]]; then
        log_info "www 池配置存在: /etc/php-fpm.d/www.conf"
        echo "=== www.conf 关键配置 ===" | tee -a "$LOG_FILE"
        grep -E '^(user|group|listen)' /etc/php-fpm.d/www.conf | tee -a "$LOG_FILE" || true
    else
        log_error "www 池配置不存在: /etc/php-fpm.d/www.conf"
    fi
    
    echo "=== PHP-FPM 近期日志 ===" | tee -a "$LOG_FILE"
    journalctl -u php-fpm --since "10 minutes ago" --no-pager | tee -a "$LOG_FILE" || true
    
    echo "=== nginx 用户检查 ===" | tee -a "$LOG_FILE"
    if id nginx &>/dev/null; then
        log_info "nginx 用户存在: $(id nginx)"
    else
        log_error "nginx 用户不存在，需要先安装 nginx 或创建用户"
    fi
}

################  1. 卸载旧环境  ################
if ! done_step "remove_old"; then
    log_info "移除旧版 Nginx / PHP ..."
    systemctl stop nginx php-fpm php73-php-fpm 2>/dev/null || true
    yum remove -y nginx* php* *-php* 2>/dev/null || true
    rm -rf /etc/php* /usr/lib64/php /var/lib/php /etc/nginx
    mark "remove_old"
fi

################  2. 配置清华源  ################
# if ! done_step "repo"; then
#     echo "==> 写入 CentOS 7 清华源 ..."
#     curl -s -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.tuna.tsinghua.edu.cn/repo/centos7.repo
#     sed -i 's|^#baseurl=http://mirror.centos.org|baseurl=https://mirrors.tuna.tsinghua.edu.cn|g;
#             s|^mirrorlist=|#mirrorlist=|g' /etc/yum.repos.d/CentOS-Base.repo
#     yum makecache fast
#     mark "repo"
# fi

################  3. EPEL / Remi  ################
if ! done_step "remi"; then
    log_info "安装 EPEL & Remi 仓库 ..."
    yum install -y epel-release
    yum install -y https://mirrors.tuna.tsinghua.edu.cn/remi/enterprise/remi-release-7.rpm
    yum-config-manager --disable 'remi-php*'
    yum-config-manager --enable remi-php${PHP_VER}
    yum makecache fast
    mark "remi"
fi

################  4. 安装 PHP 7.3.33  ################
if ! done_step "php"; then
    log_info "安装 PHP ${PHP_RT_VER} 及扩展 ..."
    yum install -y \
        php php-cli php-fpm php-common php-devel php-mysqlnd \
        php-gd php-json php-xml php-zip php-bcmath php-mbstring \
        php-snmp php-opcache php-pdo php-process php-pear
    # 锁定版本，防止误升级
    yum versionlock add php-* || true
    
    # 验证安装
    php_version=$(php -v 2>/dev/null | head -n1 || echo "PHP 版本检测失败")
    log_success "PHP 安装完成: $php_version"
    mark "php"
fi

################  5. 配置 PHP-FPM  ################
if ! done_step "php_fpm_conf"; then
    log_info "配置 PHP-FPM ..."
    
    # 检查配置文件是否存在
    if [[ ! -f /etc/php-fpm.d/www.conf ]]; then
        log_error "PHP-FPM 配置文件不存在: /etc/php-fpm.d/www.conf"
        log_info "尝试重新安装 php-fpm..."
        yum reinstall -y php-fpm
    fi
    
    # 备份原配置
    cp /etc/php-fpm.d/www.conf /etc/php-fpm.d/www.conf.backup
    
    # 检查 nginx 用户是否存在，如果不存在则创建
    if ! id nginx &>/dev/null; then
        log_info "创建 nginx 用户..."
        useradd -r -s /sbin/nologin nginx
    fi
    
    # 配置 PHP-FPM 使用 nginx 用户和 9000 端口
    log_info "更新 PHP-FPM 配置..."
    sed -i 's/^user = .*/user = nginx/;
            s/^group = .*/group = nginx/;
            s/^listen =.*/listen = 127.0.0.1:9000/' /etc/php-fpm.d/www.conf
    
    # 检查配置语法
    log_info "检查 PHP-FPM 配置语法..."
    if php-fpm -t; then
        log_success "PHP-FPM 配置语法正确"
    else
        log_error "PHP-FPM 配置语法错误"
        diagnose_php_fpm
        exit 1
    fi
    
    # 启用并启动服务
    systemctl enable php-fpm
    
    log_info "启动 PHP-FPM 服务..."
    if systemctl start php-fpm; then
        log_success "PHP-FPM 启动成功"
        sleep 2
        if check_service php-fpm; then
            mark "php_fpm_conf"
        else
            log_error "PHP-FPM 启动后状态异常"
            diagnose_php_fpm
            exit 1
        fi
    else
        log_error "PHP-FPM 启动失败"
        diagnose_php_fpm
        exit 1
    fi
fi

################  6. 安装 Nginx  ################
if ! done_step "nginx"; then
    log_info "安装官方 Nginx ..."
    cat > "$NGINX_REPO" <<'NGX'
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/7/$basearch/
gpgcheck=0
enabled=1
NGX
    yum install -y nginx
    systemctl enable nginx
    
    # 检查并启动 nginx
    log_info "启动 Nginx 服务..."
    if systemctl start nginx; then
        log_success "Nginx 启动成功"
        if check_service nginx; then
            mark "nginx"
        else
            log_error "Nginx 启动后状态异常"
            systemctl status nginx --no-pager -l
            exit 1
        fi
    else
        log_error "Nginx 启动失败"
        systemctl status nginx --no-pager -l
        exit 1
    fi
fi

################  7. 验证和测试  ################
if ! done_step "verify"; then
    log_info "验证安装结果..."
    
    echo "======================================" | tee -a "$LOG_FILE"
    echo "PHP 版本：$(php -v | head -n1)" | tee -a "$LOG_FILE"
    echo "PHP-FPM 状态：$(systemctl is-active php-fpm)" | tee -a "$LOG_FILE"
    echo "Nginx 状态：$(systemctl is-active nginx)" | tee -a "$LOG_FILE"
    
    echo "已加载扩展：" | tee -a "$LOG_FILE"
    php -m | grep -E 'zip|snmp|gd|json|xml|mysql|pdo_mysql|bcmath|mbstring|opcache' | tee -a "$LOG_FILE"
    
    echo "端口监听状态：" | tee -a "$LOG_FILE"
    ss -tlnp | grep -E ':80|:9000' | tee -a "$LOG_FILE" || log_warn "未检测到端口监听"
    
    echo "进程状态：" | tee -a "$LOG_FILE"
    ps aux | grep -E 'nginx|php-fpm' | grep -v grep | tee -a "$LOG_FILE" || log_warn "未检测到相关进程"
    
    # 创建测试 PHP 文件
    log_info "创建 PHP 测试文件..."
    cat > /usr/share/nginx/html/info.php << 'EOF'
<?php
phpinfo();
?>
EOF
    
    cat > /usr/share/nginx/html/test.php << 'EOF'
<?php
echo "PHP 工作正常！\n";
echo "当前时间: " . date('Y-m-d H:i:s') . "\n";
echo "PHP 版本: " . PHP_VERSION . "\n";
?>
EOF
    
    echo "======================================" | tee -a "$LOG_FILE"
    log_success "验证完成！详细日志保存在: $LOG_FILE"
    mark "verify"
fi

echo "All done! 环境已就绪，Web 根目录：/usr/share/nginx/html"
log_success "PHP 7.3.33 + Nginx 安装完成！"
echo
echo "测试 URLs："
echo "  - PHP 信息页面: http://YOUR_SERVER_IP/info.php"
echo "  - PHP 测试页面: http://YOUR_SERVER_IP/test.php"
echo
echo "服务管理命令："
echo "  - 重启 PHP-FPM: systemctl restart php-fpm"
echo "  - 重启 Nginx:   systemctl restart nginx"
echo "  - 查看状态:     systemctl status php-fpm nginx"
echo
echo "配置文件位置："
echo "  - PHP 配置:     /etc/php.ini"
echo "  - PHP-FPM 配置: /etc/php-fpm.d/www.conf"
echo "  - Nginx 配置:   /etc/nginx/"
echo
echo "日志文件: $LOG_FILE"