#!/bin/bash
# =============================================
#  CentOS 7.9 一键安装 PHP 7.3.33 + Nginx
#  可断点续装 / 自动清理旧环境
# =============================================
set -e
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

################  仅 root 可执行  ################
[[ $EUID -ne 0 ]] && echo "请用 root 执行" && exit 1

################  全局变量  ################
LOCK_DIR=/opt/lnmp73
LOCK_FILE=$LOCK_DIR/.lock
PHP_VER=73          # Remi 仓库版本号
PHP_RT_VER=7.3.33   # 运行时真正版本
NGINX_REPO=/etc/yum.repos.d/nginx.repo

mkdir -p "$LOCK_DIR"
touch "$LOCK_FILE"

function mark(){
    echo "$1" >> "$LOCK_FILE"
}

function done_step(){
    grep -qx "$1" "$LOCK_FILE"
}

################  1. 卸载旧环境  ################
if ! done_step "remove_old"; then
    echo "==> 移除旧版 Nginx / PHP ..."
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
    echo "==> 安装 EPEL & Remi 仓库 ..."
    yum install -y epel-release
    yum install -y https://mirrors.tuna.tsinghua.edu.cn/remi/enterprise/remi-release-7.rpm
    yum-config-manager --disable 'remi-php*'
    yum-config-manager --enable remi-php${PHP_VER}
    yum makecache fast
    mark "remi"
fi

################  4. 安装 PHP 7.3.33  ################
if ! done_step "php"; then
    echo "==> 安装 PHP ${PHP_RT_VER} 及扩展 ..."
    yum install -y \
        php php-cli php-fpm php-common php-devel php-mysqlnd \
        php-gd php-json php-xml php-zip php-bcmath php-mbstring \
        php-snmp php-opcache php-pdo php-process php-pear
    # 锁定版本，防止误升级
    yum versionlock add php-* || true
    mark "php"
fi

################  5. 配置 PHP-FPM  ################
if ! done_step "php_fpm_conf"; then
    echo "==> 配置 PHP-FPM ..."
    # 使用 9000 端口，nginx 用户
    sed -i 's/^user = .*/user = nginx/;
            s/^group = .*/group = nginx/;
            s/^listen =.*/listen = 127.0.0.1:9000/' /etc/php-fpm.d/www.conf
    systemctl enable php-fpm
    systemctl restart php-fpm
    mark "php_fpm_conf"
fi

################  6. 安装 Nginx  ################
if ! done_step "nginx"; then
    echo "==> 安装官方 Nginx ..."
    cat > "$NGINX_REPO" <<'NGX'
[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/7/$basearch/
gpgcheck=0
enabled=1
NGX
    yum install -y nginx
    systemctl enable nginx
    # 默认配置已带 php-fpm 引用，这里无需额外改动
    systemctl restart nginx
    mark "nginx"
fi

################  7. 验证  ################
if ! done_step "verify"; then
    echo "======================================"
    echo "PHP 版本：$(php -v | head -n1)"
    echo "PHP-FPM 状态：$(systemctl is-active php-fpm)"
    echo "Nginx 状态：$(systemctl is-active nginx)"
    echo "已加载扩展："
    php -m | grep -E 'zip|snmp|gd|json|xml|mysql|pdo_mysql|bcmath|mbstring|opcache'
    echo "======================================"
    mark "verify"
fi

echo "All done! 环境已就绪，Web 根目录：/usr/share/nginx/html"