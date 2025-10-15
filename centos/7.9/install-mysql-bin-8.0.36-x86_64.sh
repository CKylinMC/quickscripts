#!/bin/bash
# MySQL 8.0.36 Binary Installation Script for CentOS 7.9
# Enhanced with logging, error handling, and failsafe mechanisms
# ref: https://www.cnblogs.com/wuzaipei/p/18940864

#==============================================================================
# CONFIGURATION VARIABLES
#==============================================================================
readonly MYSQL_VERSION="8.0.36"
readonly MYSQL_USER="mysql"
readonly MYSQL_GROUP="mysql"
readonly MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-RootPassw0rd.}"
readonly MYSQL_BASE_DIR="/usr/local/mysql"
readonly MYSQL_DATA_DIR="${MYSQL_BASE_DIR}/data"
readonly MYSQL_LOG_DIR="${MYSQL_BASE_DIR}/logs"
readonly MYSQL_TMP_DIR="${MYSQL_BASE_DIR}/tmp"
readonly MYSQL_BINLOG_DIR="${MYSQL_BASE_DIR}/binlog"
readonly MYSQL_SOCKET="/tmp/mysql.sock"
readonly MYSQL_CONFIG_FILE="/etc/my.cnf"
readonly MYSQL_SERVICE_FILE="/etc/systemd/system/mysqld.service"
readonly DOWNLOAD_URL="https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64.tar.xz"
readonly WORK_DIR="/opt"

# Generate unique log and backup directories
LOG_FILE="/tmp/mysql_install_$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/tmp/mysql_backup_$(date +%Y%m%d_%H%M%S)"
readonly LOG_FILE
readonly BACKUP_DIR

# Script execution control
set -euo pipefail
trap 'handle_error $? $LINENO' ERR
trap 'cleanup_on_exit' EXIT

#==============================================================================
# LOGGING AND ERROR HANDLING FUNCTIONS
#==============================================================================

# Initialize log file
init_log() {
    mkdir -p "$(dirname "$LOG_FILE")"
    exec 3>&1 4>&2
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
    log_info "MySQL installation started at $(date)"
    log_info "Log file: $LOG_FILE"
}

# Logging functions with timestamp
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" >&2
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $*"
}

# Progress indicator
show_progress() {
    local current=$1
    local total=$2
    local message=$3
    echo "[Step $current/$total] $message"
}

# Error handler
handle_error() {
    local exit_code=$1
    local line_number=$2
    log_error "Script failed with exit code $exit_code at line $line_number"
    log_error "Initiating cleanup and rollback..."
    rollback_installation
    exit $exit_code
}

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if service is running
is_service_running() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

# Backup existing files/directories
backup_if_exists() {
    local source="$1"
    local backup_name="$2"
    
    if [[ -e "$source" ]]; then
        log_info "Backing up existing $source to $BACKUP_DIR/$backup_name"
        mkdir -p "$BACKUP_DIR"
        cp -rf "$source" "$BACKUP_DIR/$backup_name" || {
            log_warn "Failed to backup $source, continuing..."
        }
    fi
}

# Verify checksum if available
verify_download() {
    local file="$1"
    if [[ -f "$file" ]]; then
        log_info "Verifying downloaded file integrity..."
        # Basic file size check (MySQL binary should be > 500MB)
        local file_size
        file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)
        if [[ $file_size -gt 524288000 ]]; then  # 500MB in bytes
            log_success "Downloaded file appears to be valid (size: $file_size bytes)"
            return 0
        else
            log_error "Downloaded file appears to be corrupted (size: $file_size bytes)"
            return 1
        fi
    else
        log_error "Downloaded file not found: $file"
        return 1
    fi
}

#==============================================================================
# CLEANUP AND ROLLBACK FUNCTIONS
#==============================================================================

# Cleanup on exit
cleanup_on_exit() {
    log_info "Performing cleanup on exit..." 2>/dev/null || echo "Performing cleanup on exit..."
    # Restore file descriptors safely
    if [[ -t 3 ]] 2>/dev/null; then
        exec 1>&3 2>&4
        exec 3>&- 4>&-
    fi
}

# Rollback installation
rollback_installation() {
    log_info "Starting rollback process..."
    
    # Stop MySQL service if running
    if is_service_running mysqld; then
        log_info "Stopping MySQL service..."
        systemctl stop mysqld 2>/dev/null || true
    fi
    
    # Disable MySQL service
    systemctl disable mysqld 2>/dev/null || true
    
    # Remove service file
    [[ -f "$MYSQL_SERVICE_FILE" ]] && rm -f "$MYSQL_SERVICE_FILE"
    
    # Remove MySQL installation directory
    [[ -d "$MYSQL_BASE_DIR" ]] && rm -rf "$MYSQL_BASE_DIR"
    
    # Remove MySQL user and group
    if id "$MYSQL_USER" &>/dev/null; then
        userdel "$MYSQL_USER" 2>/dev/null || true
    fi
    if getent group "$MYSQL_GROUP" &>/dev/null; then
        groupdel "$MYSQL_GROUP" 2>/dev/null || true
    fi
    
    # Remove configuration file
    [[ -f "$MYSQL_CONFIG_FILE" ]] && rm -f "$MYSQL_CONFIG_FILE"
    
    # Restore backed up files if they exist
    if [[ -d "$BACKUP_DIR" ]]; then
        log_info "Restoring backed up files..."
        for backup in "$BACKUP_DIR"/*; do
            if [[ -f "$backup" ]]; then
                local original_name
                original_name=$(basename "$backup")
                case "$original_name" in
                    "my.cnf_backup")
                        cp "$backup" "$MYSQL_CONFIG_FILE" 2>/dev/null || true
                        ;;
                    "mysqld.service_backup")
                        cp "$backup" "$MYSQL_SERVICE_FILE" 2>/dev/null || true
                        ;;
                esac
            fi
        done
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    log_info "Rollback completed"
}

#==============================================================================
# MAIN INSTALLATION FUNCTIONS
#==============================================================================

# Initialize logging
init_log

#==============================================================================
# PREREQUISITE CHECKS
#==============================================================================

check_prerequisites() {
    show_progress 1 8 "Performing prerequisite checks"
    log_info "Starting prerequisite checks..."
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
    
    # Check operating system
    if ! grep -q "CentOS Linux release 7" /etc/redhat-release 2>/dev/null; then
        log_warn "This script is designed for CentOS 7.9. Current OS: $(cat /etc/redhat-release 2>/dev/null || echo 'Unknown')"
        read -p "Do you want to continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installation cancelled by user"
            exit 0
        fi
    fi
    
    # Check available disk space (need at least 5GB)
    local available_space
    available_space=$(df /usr/local 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)
    local required_space=5242880  # 5GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        log_error "Insufficient disk space. Required: 5GB, Available: $((available_space/1024/1024))GB"
        exit 1
    fi
    
    log_success "Disk space check passed. Available: $((available_space/1024/1024))GB"
    
    # Check network connectivity
    log_info "Checking network connectivity..."
    if ! curl -s --connect-timeout 10 "https://dev.mysql.com" > /dev/null; then
        log_error "Cannot reach MySQL download server. Please check your internet connection."
        exit 1
    fi
    log_success "Network connectivity check passed"
    
    # Check for required commands
    local required_commands=("wget" "tar" "systemctl" "groupadd" "useradd")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "Required command not found: $cmd"
            exit 1
        fi
    done
    log_success "All required commands are available"
    
    # Check if MySQL is already running
    if is_service_running mysqld; then
        log_warn "MySQL service is currently running"
    fi
    
    # Check if MariaDB is already running
    if is_service_running mariadb; then
        log_warn "MariaDB service is currently running"
    fi
    
    log_success "Prerequisite checks completed successfully"
}

stop_existing_services() {
    show_progress 2 8 "Stopping existing MySQL/MariaDB services"
    log_info "Attempting to stop existing MySQL/MariaDB services..."

    # Stop existing services safely
    for service in mysqld mariadb mysql; do
        if is_service_running "$service"; then
            log_info "Stopping $service service..."
            systemctl stop "$service" || log_warn "Failed to stop $service service"
        else
            log_info "$service service is not running"
        fi
    done
}

remove_existing_mysql() {
    show_progress 3 8 "Removing existing MySQL/MariaDB installations"
    log_info "Starting removal of existing MySQL/MariaDB installations..."
    
    # Backup existing configurations before removal
    backup_if_exists "$MYSQL_CONFIG_FILE" "my.cnf_backup"
    backup_if_exists "$MYSQL_SERVICE_FILE" "mysqld.service_backup"
    backup_if_exists "/var/lib/mysql" "var_lib_mysql_backup"
    
    # Remove packages
    log_info "Removing MySQL/MariaDB packages..."
    yum remove -y mariadb* mysql* 2>/dev/null || {
        log_warn "Some packages could not be removed (may not be installed)"
    }
    
    # Clean up directories and files
    local cleanup_paths=(
        "/var/lib/mysql"
        "/etc/my.cnf"
        "/etc/my.cnf.d"
        "/etc/mysql"
        "/var/log/mysqld.log"
        "/var/log/mysql"
        "/run/mysqld"
        "/tmp/mysql.sock"
        "/tmp/mysqld.sock"
    )
    
    for path in "${cleanup_paths[@]}"; do
        if [[ -e "$path" ]]; then
            log_info "Removing $path..."
            rm -rf "$path" || log_warn "Failed to remove $path"
        fi
    done
    
    # Remove existing MySQL user and group if they exist
    if id "$MYSQL_USER" &>/dev/null; then
        log_info "Removing existing MySQL user..."
        userdel "$MYSQL_USER" 2>/dev/null || log_warn "Failed to remove MySQL user"
    fi
    
    if getent group "$MYSQL_GROUP" &>/dev/null; then
        log_info "Removing existing MySQL group..."
        groupdel "$MYSQL_GROUP" 2>/dev/null || log_warn "Failed to remove MySQL group"
    fi
    
    log_success "Existing MySQL/MariaDB removal completed"
}

create_mysql_user_and_directories() {
    show_progress 4 8 "Creating MySQL user and directories"
    log_info "Creating MySQL user and group..."
    
    # Create MySQL group
    if ! getent group "$MYSQL_GROUP" &>/dev/null; then
        groupadd "$MYSQL_GROUP" || {
            log_error "Failed to create MySQL group"
            return 1
        }
        log_success "MySQL group created successfully"
    else
        log_info "MySQL group already exists"
    fi
    
    # Create MySQL user
    if ! id "$MYSQL_USER" &>/dev/null; then
        useradd -r -g "$MYSQL_GROUP" -s /bin/false "$MYSQL_USER" || {
            log_error "Failed to create MySQL user"
            return 1
        }
        log_success "MySQL user created successfully"
    else
        log_info "MySQL user already exists"
    fi
    
    # Create MySQL directories
    log_info "Creating MySQL directories..."
    local mysql_dirs=(
        "$MYSQL_BASE_DIR"
        "$MYSQL_DATA_DIR"
        "$MYSQL_LOG_DIR"
        "$MYSQL_TMP_DIR"
        "$MYSQL_BINLOG_DIR"
    )
    
    for dir in "${mysql_dirs[@]}"; do
        if ! mkdir -p "$dir"; then
            log_error "Failed to create directory: $dir"
            return 1
        fi
        log_info "Created directory: $dir"
    done
    
    # Set proper ownership
    chown -R "$MYSQL_USER:$MYSQL_GROUP" "$MYSQL_BASE_DIR" || {
        log_error "Failed to set ownership for MySQL directories"
        return 1
    }
    
    log_success "MySQL user and directories created successfully"
}

install_dependencies() {
    show_progress 5 8 "Installing required dependencies"
    log_info "Installing required dependencies..."
    
    local dependencies=("wget" "libaio" "numactl-libs" "openssl-devel")
    
    for dep in "${dependencies[@]}"; do
        log_info "Installing $dep..."
        if ! yum install -y "$dep"; then
            log_error "Failed to install dependency: $dep"
            return 1
        fi
    done
    
    log_success "All dependencies installed successfully"
}

download_and_install_mysql() {
    show_progress 6 8 "Downloading and installing MySQL"
    log_info "Starting MySQL download and installation..."
    
    # Change to work directory
    cd "$WORK_DIR" || {
        log_error "Failed to change to work directory: $WORK_DIR"
        return 1
    }
    
    local mysql_archive="mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64.tar.xz"
    
    # Download MySQL if not already present
    if [[ ! -f "$mysql_archive" ]]; then
        log_info "Downloading MySQL $MYSQL_VERSION..."
        log_info "Download URL: $DOWNLOAD_URL"
        
        # Download with progress and retry on failure
        local download_attempts=3
        local attempt=1
        
        while [[ $attempt -le $download_attempts ]]; do
            log_info "Download attempt $attempt/$download_attempts"
            
            if wget --progress=bar:force "$DOWNLOAD_URL" -O "$mysql_archive"; then
                log_success "MySQL download completed"
                break
            else
                log_warn "Download attempt $attempt failed"
                if [[ $attempt -eq $download_attempts ]]; then
                    log_error "All download attempts failed"
                    return 1
                fi
                ((attempt++))
                sleep 5
            fi
        done
    else
        log_info "MySQL archive already exists, skipping download"
    fi
    
    # Verify download
    if ! verify_download "$mysql_archive"; then
        log_error "Downloaded file verification failed"
        return 1
    fi
    
    # Extract MySQL
    log_info "Extracting MySQL archive..."
    if ! tar -xf "$mysql_archive" -C /usr/local/; then
        log_error "Failed to extract MySQL archive"
        return 1
    fi
    
    # Move to standard location
    cd /usr/local || {
        log_error "Failed to change to /usr/local directory"
        return 1
    }
    
    local extracted_dir="mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64"
    if [[ ! -d "$extracted_dir" ]]; then
        log_error "Extracted directory not found: $extracted_dir"
        return 1
    fi
    
    # Remove existing mysql directory if it exists
    if [[ -d "mysql" ]]; then
        log_info "Removing existing mysql directory..."
        rm -rf mysql
    fi
    
    # Move extracted directory to mysql
    if ! mv "$extracted_dir" mysql; then
        log_error "Failed to move MySQL directory"
        return 1
    fi
    
    # Recreate MySQL data directories (they may have been overwritten)
    log_info "Creating/recreating MySQL data directories..."
    local mysql_dirs=(
        "$MYSQL_DATA_DIR"
        "$MYSQL_LOG_DIR"
        "$MYSQL_TMP_DIR"
        "$MYSQL_BINLOG_DIR"
    )
    
    for dir in "${mysql_dirs[@]}"; do
        if ! mkdir -p "$dir"; then
            log_error "Failed to create directory: $dir"
            return 1
        fi
        log_info "Created/verified directory: $dir"
    done
    
    # Set proper ownership for entire MySQL directory
    chown -R "$MYSQL_USER:$MYSQL_GROUP" mysql || {
        log_error "Failed to set ownership for MySQL installation"
        return 1
    }
    
    # Add MySQL bin to PATH
    log_info "Adding MySQL to system PATH..."
    if ! grep -q "/usr/local/mysql/bin" /etc/profile; then
        echo "export PATH=\$PATH:/usr/local/mysql/bin" >> /etc/profile
        log_success "MySQL added to system PATH"
    else
        log_info "MySQL already in system PATH"
    fi
    
    # Source the profile for current session
    export PATH=$PATH:/usr/local/mysql/bin

    # Remove downloaded archive file if it exists (cleanup)
    if [[ -f "$WORK_DIR/$mysql_archive" ]]; then
        log_info "Removing downloaded MySQL archive: $WORK_DIR/$mysql_archive"
        rm -f "$WORK_DIR/$mysql_archive"
    fi
    
    log_success "MySQL installation completed successfully"
}

create_mysql_configuration() {
    show_progress 7 8 "Creating MySQL configuration files"
    log_info "Creating MySQL configuration file..."
    
    # Backup existing configuration if it exists
    backup_if_exists "$MYSQL_CONFIG_FILE" "my.cnf_existing"
    
    # Create optimized MySQL configuration
    cat > "$MYSQL_CONFIG_FILE" << EOF
[mysqld]
# Basic settings
basedir=$MYSQL_BASE_DIR
datadir=$MYSQL_DATA_DIR
socket=$MYSQL_SOCKET
port=3306
user=$MYSQL_USER

# Logging
log-error=$MYSQL_LOG_DIR/mysql.err
pid-file=$MYSQL_BASE_DIR/mysql.pid
slow_query_log=1
slow_query_log_file=$MYSQL_LOG_DIR/mysql-slow.log
long_query_time=2

# Binary logging
log-bin=$MYSQL_BINLOG_DIR/mysql-bin
binlog_format=ROW
server-id=1
binlog_expire_logs_seconds=604800  # 7 days in seconds

# Character set and collation
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci

# Case sensitivity
lower_case_table_names=1

# InnoDB settings
innodb_buffer_pool_size=256M
innodb_log_file_size=64M
innodb_flush_log_at_trx_commit=1
innodb_lock_wait_timeout=50

# Network settings
max_connections=200
max_connect_errors=100
bind-address=0.0.0.0

# Temporary directory
tmpdir=$MYSQL_TMP_DIR

[client]
socket=$MYSQL_SOCKET
default-character-set=utf8mb4

[mysql]
default-character-set=utf8mb4
EOF

    if [[ $? -eq 0 ]]; then
        log_success "MySQL configuration file created successfully"
    else
        log_error "Failed to create MySQL configuration file"
        return 1
    fi
    
    # Create systemd service file
    log_info "Creating MySQL systemd service file..."
    
    backup_if_exists "$MYSQL_SERVICE_FILE" "mysqld.service_existing"
    
    # First, try to create a service file using mysqld_safe
    cat > "$MYSQL_SERVICE_FILE" << EOF
[Unit]
Description=MySQL Community Server
Documentation=man:mysqld(8)
Documentation=http://dev.mysql.com/doc/refman/en/using-systemd.html
After=network.target
After=syslog.target

[Install]
WantedBy=multi-user.target

[Service]
User=$MYSQL_USER
Group=$MYSQL_GROUP
Type=forking
PIDFile=$MYSQL_BASE_DIR/mysql.pid
TimeoutSec=0
PermissionsStartOnly=true
ExecStart=/usr/local/mysql/bin/mysqld_safe --defaults-file=$MYSQL_CONFIG_FILE --pid-file=$MYSQL_BASE_DIR/mysql.pid
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartPreventExitStatus=1
LimitNOFILE=65535
LimitNPROC=65535
PrivateTmp=false
EOF

    # Verify if mysqld_safe exists, if not create alternative service
    if [[ ! -x "/usr/local/mysql/bin/mysqld_safe" ]]; then
        log_warn "mysqld_safe not found, creating alternative service configuration..."
        cat > "$MYSQL_SERVICE_FILE" << EOF
[Unit]
Description=MySQL Community Server
Documentation=man:mysqld(8)
After=network.target
After=syslog.target

[Install]
WantedBy=multi-user.target

[Service]
User=$MYSQL_USER
Group=$MYSQL_GROUP
Type=simple
ExecStart=/usr/local/mysql/bin/mysqld --defaults-file=$MYSQL_CONFIG_FILE --user=$MYSQL_USER
Restart=on-failure
RestartPreventExitStatus=1
LimitNOFILE=65535
LimitNPROC=65535
PrivateTmp=false
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=mysqld
EOF
    fi

    if [[ $? -eq 0 ]]; then
        log_success "MySQL systemd service file created successfully"
    else
        log_error "Failed to create MySQL systemd service file"
        return 1
    fi
    
    # Reload systemd daemon
    systemctl daemon-reload || {
        log_error "Failed to reload systemd daemon"
        return 1
    }
    
    log_success "MySQL configuration completed successfully"
}

initialize_mysql_database() {
    show_progress 8 8 "Initializing MySQL database"
    log_info "Initializing MySQL database..."
    
    # Change to work directory
    cd "$WORK_DIR" || {
        log_error "Failed to change to work directory"
        return 1
    }
    
    # Initialize MySQL database
    log_info "Running MySQL initialization..."
    if ! /usr/local/mysql/bin/mysqld --initialize-insecure --user="$MYSQL_USER" --lower-case-table-names=1; then
        log_error "Failed to initialize MySQL database"
        return 1
    fi
    
    log_success "MySQL database initialized successfully"
    
    # Start MySQL service
    log_info "Starting MySQL service..."
    if ! systemctl start mysqld; then
        log_error "Failed to start MySQL service"
        return 1
    fi
    
    log_success "MySQL service started successfully"
    
    # Enable MySQL service
    log_info "Enabling MySQL service for auto-start..."
    if ! systemctl enable mysqld; then
        log_error "Failed to enable MySQL service"
        return 1
    fi
    
    log_success "MySQL service enabled successfully"
    
    # Wait for MySQL to be ready
    log_info "Waiting for MySQL to be ready..."
    local wait_count=0
    local max_wait=30
    
    while [[ $wait_count -lt $max_wait ]]; do
        if /usr/local/mysql/bin/mysqladmin ping --silent 2>/dev/null; then
            log_success "MySQL is ready"
            break
        fi
        ((wait_count++))
        echo -n "."
        sleep 1
    done
    
    if [[ $wait_count -eq $max_wait ]]; then
        log_error "MySQL failed to start within $max_wait seconds"
        return 1
    fi
    
    # Configure MySQL security
    log_info "Configuring MySQL security settings..."
    
    /usr/local/mysql/bin/mysql -uroot --connect-expired-password <<-EOSQL
        -- Set root password
        ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';
        
        -- Create root user for remote access
        CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';
        GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
        
        -- Remove anonymous users
        DELETE FROM mysql.user WHERE User='';
        
        -- Remove test database
        DROP DATABASE IF EXISTS test;
        
        -- Remove test database permissions
        DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
        
        -- Reload privileges
        FLUSH PRIVILEGES;
EOSQL

    if [[ $? -eq 0 ]]; then
        log_success "MySQL security configuration completed"
    else
        log_warn "Some security configurations may have failed, but MySQL is running"
    fi
}

validate_installation() {
    log_info "Validating MySQL installation..."
    
    # Check if service is running
    if ! is_service_running mysqld; then
        log_error "MySQL service is not running"
        return 1
    fi
    log_success "MySQL service is running"
    
    # Check MySQL version
    local mysql_version
    mysql_version=$(/usr/local/mysql/bin/mysqld --version 2>/dev/null | grep -oP 'Ver \K[\d.]+')
    if [[ -n "$mysql_version" ]]; then
        log_success "MySQL version: $mysql_version"
    else
        log_warn "Could not determine MySQL version"
    fi
    
    # Test database connection
    if /usr/local/mysql/bin/mysql -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" &>/dev/null; then
        log_success "Database connection test passed"
    else
        log_error "Database connection test failed"
        return 1
    fi
    
    log_success "MySQL installation validation completed successfully"
}

# Diagnostic function for troubleshooting
diagnose_mysql_issues() {
    echo "=========================================="
    echo "MySQL Installation Diagnostic Report"
    echo "=========================================="
    echo "Generated at: $(date)"
    echo
    
    echo "1. Service Status:"
    systemctl status mysqld --no-pager || echo "MySQL service not found"
    echo
    
    echo "2. Recent systemd logs:"
    journalctl -u mysqld --since "30 minutes ago" --no-pager | tail -20
    echo
    
    echo "3. MySQL Error Log:"
    if [[ -f "$MYSQL_LOG_DIR/mysql.err" ]]; then
        echo "Last 20 lines of $MYSQL_LOG_DIR/mysql.err:"
        tail -20 "$MYSQL_LOG_DIR/mysql.err"
    else
        echo "MySQL error log not found at $MYSQL_LOG_DIR/mysql.err"
        # Check alternative locations
        for log_path in "/var/log/mysqld.log" "/var/log/mysql/error.log"; do
            if [[ -f "$log_path" ]]; then
                echo "Found alternative log at $log_path:"
                tail -10 "$log_path"
                break
            fi
        done
    fi
    echo
    
    echo "4. Directory Structure:"
    echo "MySQL base directory: $MYSQL_BASE_DIR"
    ls -la "$MYSQL_BASE_DIR" 2>/dev/null || echo "Base directory not found"
    echo
    
    echo "Required directories:"
    for dir in "$MYSQL_DATA_DIR" "$MYSQL_LOG_DIR" "$MYSQL_TMP_DIR" "$MYSQL_BINLOG_DIR"; do
        if [[ -d "$dir" ]]; then
            echo "✓ $dir ($(ls -ld "$dir" | awk '{print $1, $3, $4}'))"
        else
            echo "✗ $dir (missing)"
        fi
    done
    echo
    
    echo "5. Configuration File:"
    if [[ -f "$MYSQL_CONFIG_FILE" ]]; then
        echo "Configuration file exists: $MYSQL_CONFIG_FILE"
        echo "File permissions: $(ls -l "$MYSQL_CONFIG_FILE" | awk '{print $1, $3, $4}')"
    else
        echo "Configuration file missing: $MYSQL_CONFIG_FILE"
    fi
    echo
    
    echo "6. MySQL User and Permissions:"
    if id "$MYSQL_USER" &>/dev/null; then
        echo "MySQL user exists: $(id "$MYSQL_USER")"
    else
        echo "MySQL user not found: $MYSQL_USER"
    fi
    echo
    
    echo "7. Process Information:"
    ps aux | grep mysqld | grep -v grep || echo "No MySQL processes running"
    echo
    
    echo "8. Service Configuration Check:"
    if [[ -f "$MYSQL_SERVICE_FILE" ]]; then
        echo "Service file exists: $MYSQL_SERVICE_FILE"
        echo "Service file contents:"
        cat "$MYSQL_SERVICE_FILE"
        echo
        
        # Check if executables exist
        echo "Executable checks:"
        if [[ -x "/usr/local/mysql/bin/mysqld" ]]; then
            echo "✓ mysqld executable exists"
        else
            echo "✗ mysqld executable missing or not executable"
        fi
        
        if [[ -x "/usr/local/mysql/bin/mysqld_safe" ]]; then
            echo "✓ mysqld_safe executable exists"
        else
            echo "✗ mysqld_safe executable missing or not executable"
        fi
    else
        echo "Service file missing: $MYSQL_SERVICE_FILE"
    fi
    echo
    
    echo "9. Port Status:"
    ss -tlnp | grep :3306 || echo "Port 3306 not in use"
    echo
    
    echo "9. Port Status:"
    ss -tlnp | grep :3306 || echo "Port 3306 not in use"
    echo
    
    echo "10. Disk Space:"
    df -h /usr/local
    echo
    
    echo "11. Configuration Validation:"
    if [[ -x "/usr/local/mysql/bin/mysqld" ]]; then
        /usr/local/mysql/bin/mysqld --defaults-file="$MYSQL_CONFIG_FILE" --validate-config 2>&1 || echo "Configuration validation failed"
    else
        echo "mysqld binary not found or not executable"
    fi
    
    echo "=========================================="
    echo "Diagnostic Report Complete"
    echo "=========================================="
}

generate_installation_report() {
    local report_file
    report_file="/tmp/mysql_installation_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
MySQL Installation Report
========================
Installation Date: $(date)
MySQL Version: $MYSQL_VERSION
Installation Directory: $MYSQL_BASE_DIR
Data Directory: $MYSQL_DATA_DIR
Configuration File: $MYSQL_CONFIG_FILE
Service File: $MYSQL_SERVICE_FILE
Log File: $LOG_FILE

Service Status:
$(systemctl status mysqld --no-pager -l)

MySQL Process:
$(ps aux | grep mysqld | grep -v grep)

Port Status:
$(ss -tlnp | grep :3306 || echo "Port 3306 not found")

Installation Log: $LOG_FILE
Backup Directory: $BACKUP_DIR

Security Notes:
- Root password has been set
- Anonymous users have been removed
- Test database has been removed
- Remote root access has been enabled

Next Steps:
1. Test the MySQL connection: mysql -uroot -p
2. Create application-specific databases and users
3. Configure firewall if needed: firewall-cmd --add-port=3306/tcp --permanent
4. Review and adjust MySQL configuration in $MYSQL_CONFIG_FILE
5. Set up regular backups

EOF

    log_success "Installation report generated: $report_file"
    echo "Installation report saved to: $report_file"
}

#==============================================================================
# MAIN EXECUTION
#==============================================================================

main() {
    # Initialize logging first
    init_log
    
    log_info "Starting MySQL installation process..."
    
    # Execute installation steps
    check_prerequisites
    stop_existing_services
    remove_existing_mysql
    create_mysql_user_and_directories
    install_dependencies
    download_and_install_mysql
    create_mysql_configuration
    initialize_mysql_database
    validate_installation
    generate_installation_report
    
    log_success "MySQL installation completed successfully!"
    echo
    echo "MySQL installation and configuration completed."
    echo "Root password: $MYSQL_ROOT_PASSWORD"
    echo "To connect: mysql -uroot -p"
    echo
    systemctl status mysqld --no-pager
}

# Run main function
if [[ "${1:-}" == "--diagnose" || "${1:-}" == "-d" ]]; then
    # Initialize basic variables for diagnosis
    MYSQL_BASE_DIR="/usr/local/mysql"
    MYSQL_DATA_DIR="${MYSQL_BASE_DIR}/data"
    MYSQL_LOG_DIR="${MYSQL_BASE_DIR}/logs"
    MYSQL_TMP_DIR="${MYSQL_BASE_DIR}/tmp"
    MYSQL_BINLOG_DIR="${MYSQL_BASE_DIR}/binlog"
    MYSQL_CONFIG_FILE="/etc/my.cnf"
    MYSQL_USER="mysql"
    
    echo "Running MySQL diagnostic mode..."
    diagnose_mysql_issues
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "MySQL Installation Script"
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -d, --diagnose    Run diagnostic mode to troubleshoot issues"
    echo "  -h, --help        Show this help message"
    echo "  (no options)      Run full MySQL installation"
    echo ""
    echo "Environment variables:"
    echo "  MYSQL_ROOT_PASSWORD   Set custom root password (default: Byrszkys.)"
    echo ""
    echo "Examples:"
    echo "  sudo $0                              # Install MySQL"
    echo "  sudo $0 --diagnose                   # Diagnose installation issues"
    echo "  sudo MYSQL_ROOT_PASSWORD='mypass' $0 # Install with custom password"
else
    main "$@"
fi
