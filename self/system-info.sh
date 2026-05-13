#!/bin/bash

################################################################################
# 系统信息检查脚本
# 功能：快速检查设备型号、架构、发行版、CPU、GPU、内存等信息
# 使用：bash system_info.sh
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
    printf "  ${CYAN}%-30s${NC} : ${GREEN}%s${NC}\n" "$1" "$2"
}

# 打印错误信息
print_error() {
    printf "  ${RED}%-30s${NC} : ${YELLOW}%s${NC}\n" "$1" "$2"
}

################################################################################
# 0. 硬件厂商和设备信息
################################################################################
print_header "🏭 硬件厂商和设备信息"

# 系统厂商
if [ -f /sys/class/dmi/id/sys_vendor ]; then
    SYS_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
    [ -n "$SYS_VENDOR" ] && print_info "系统厂商" "$SYS_VENDOR"
fi

# 产品名称
if [ -f /sys/class/dmi/id/product_name ]; then
    PRODUCT_NAME=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
    [ -n "$PRODUCT_NAME" ] && print_info "产品型号" "$PRODUCT_NAME"
fi

# 产品版本
if [ -f /sys/class/dmi/id/product_version ]; then
    PRODUCT_VERSION=$(cat /sys/class/dmi/id/product_version 2>/dev/null)
    [ -n "$PRODUCT_VERSION" ] && print_info "产品版本" "$PRODUCT_VERSION"
fi

# 产品序列号
if [ -f /sys/class/dmi/id/product_serial ]; then
    PRODUCT_SERIAL=$(cat /sys/class/dmi/id/product_serial 2>/dev/null)
    if [ -n "$PRODUCT_SERIAL" ] && [ "$PRODUCT_SERIAL" != "System Serial Number" ]; then
        print_info "序列号" "$PRODUCT_SERIAL"
    fi
fi

# 主板厂商
if [ -f /sys/class/dmi/id/board_vendor ]; then
    BOARD_VENDOR=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null)
    [ -n "$BOARD_VENDOR" ] && print_info "主板厂商" "$BOARD_VENDOR"
fi

# 主板型号
if [ -f /sys/class/dmi/id/board_name ]; then
    BOARD_NAME=$(cat /sys/class/dmi/id/board_name 2>/dev/null)
    [ -n "$BOARD_NAME" ] && print_info "主板型号" "$BOARD_NAME"
fi

# BIOS 厂商
if [ -f /sys/class/dmi/id/bios_vendor ]; then
    BIOS_VENDOR=$(cat /sys/class/dmi/id/bios_vendor 2>/dev/null)
    [ -n "$BIOS_VENDOR" ] && print_info "BIOS 厂商" "$BIOS_VENDOR"
fi

# BIOS 版本
if [ -f /sys/class/dmi/id/bios_version ]; then
    BIOS_VERSION=$(cat /sys/class/dmi/id/bios_version 2>/dev/null)
    [ -n "$BIOS_VERSION" ] && print_info "BIOS 版本" "$BIOS_VERSION"
fi

# BIOS 发布日期
if [ -f /sys/class/dmi/id/bios_date ]; then
    BIOS_DATE=$(cat /sys/class/dmi/id/bios_date 2>/dev/null)
    [ -n "$BIOS_DATE" ] && print_info "BIOS 发布日期" "$BIOS_DATE"
fi

# 机箱厂商
if [ -f /sys/class/dmi/id/chassis_vendor ]; then
    CHASSIS_VENDOR=$(cat /sys/class/dmi/id/chassis_vendor 2>/dev/null)
    [ -n "$CHASSIS_VENDOR" ] && print_info "机箱厂商" "$CHASSIS_VENDOR"
fi

# 机箱型号
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

################################################################################
# 1. 系统基本信息
################################################################################
print_header "📱 系统基本信息"

# 主机名
HOSTNAME=$(hostname)
print_info "主机名" "$HOSTNAME"

# 系统架构
ARCH=$(uname -m)
print_info "系统架构" "$ARCH"

# 内核版本
KERNEL=$(uname -r)
print_info "内核版本" "$KERNEL"

# 操作系统
OS_NAME=$(uname -s)
print_info "操作系统" "$OS_NAME"

################################################################################
# 2. 发行版信息
################################################################################
print_header "🐧 发行版信息"

if [ -f /etc/os-release ]; then
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
UPTIME=$(uptime -p 2>/dev/null || uptime | awk -F'up' '{print $2}' | awk -F',' '{print $1}')
print_info "运行时间" "$UPTIME"

################################################################################
# 3. CPU 信息
################################################################################
print_header "⚙️  CPU 信息"

# CPU 型号
if [ -f /proc/cpuinfo ]; then
    CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)
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
    [ -z "$CPU_FREQ" ] && CPU_FREQ=$(lscpu | grep "CPU max MHz" | awk '{printf "%.2f GHz", $4/1000}')
    [ -n "$CPU_FREQ" ] && print_info "CPU 频率" "$CPU_FREQ"
    
    # CPU 缓存
    CPU_CACHE=$(grep "cache size" /proc/cpuinfo | head -1 | awk '{print $4}')
    [ -n "$CPU_CACHE" ] && print_info "L3 缓存" "$CPU_CACHE"
    
    # CPU 架构
    if command -v lscpu &> /dev/null; then
        CPU_ARCH=$(lscpu | grep "Architecture" | awk -F: '{print $2}' | xargs)
        [ -n "$CPU_ARCH" ] && print_info "CPU 架构" "$CPU_ARCH"
    fi
else
    print_error "CPU 信息" "无法读取 /proc/cpuinfo"
fi

# CPU 使用率
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
if [ -z "$CPU_USAGE" ]; then
    CPU_USAGE=$(ps aux | awk 'BEGIN {sum=0} {sum+=$3} END {print sum "%"}')
fi
print_info "CPU 使用率" "$CPU_USAGE"

################################################################################
# 4. GPU 信息
################################################################################
print_header "🎮 GPU 信息"

GPU_FOUND=0

# 检查 NVIDIA GPU
if command -v nvidia-smi &> /dev/null; then
    GPU_FOUND=1
    echo -e "  ${CYAN}NVIDIA GPU:${NC}"
    nvidia-smi --query-gpu=index,name,driver_version,memory.total,memory.used \
        --format=csv,noheader,nounits | while IFS=',' read -r idx name driver mem_total mem_used; do
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

# 检查 Intel GPU
if lspci 2>/dev/null | grep -i "intel.*graphics" > /dev/null; then
    GPU_FOUND=1
    INTEL_GPU=$(lspci | grep -i "intel.*graphics" | head -1 | cut -d: -f3)
    print_info "Intel GPU" "$INTEL_GPU"
fi

# 通用 GPU 检查
if ! command -v lspci &> /dev/null; then
    if [ $GPU_FOUND -eq 0 ]; then
        print_error "GPU 信息" "未检测到独立 GPU 或 lspci 不可用"
    fi
else
    if [ $GPU_FOUND -eq 0 ]; then
        GPU_COUNT=$(lspci | grep -iE "VGA|3D|Display" | wc -l)
        if [ $GPU_COUNT -gt 0 ]; then
            echo -e "  ${CYAN}其他 GPU 设备:${NC}"
            lspci | grep -iE "VGA|3D|Display" | while read -r line; do
                GPU_NAME=$(echo "$line" | cut -d: -f3)
                printf "    ${GREEN}%s${NC}\n" "$GPU_NAME"
            done
        else
            print_error "GPU 信息" "未检测到独立 GPU (集成显卡)"
        fi
    fi
fi

################################################################################
# 5. 内存信息
################################################################################
print_header "💾 内存信息"

if [ -f /proc/meminfo ]; then
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
    print_error "内存信息" "无法读取 /proc/meminfo"
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
    
    # 显示其他主要挂载点
    df -h | grep -E "^/dev/" | grep -v "^/dev/loop" | tail -n +2 | while read -r line; do
        MOUNT=$(echo "$line" | awk '{print $NF}')
        USAGE=$(echo "$line" | awk '{print $5}')
        SIZE=$(echo "$line" | awk '{print $2}')
        printf "    ${GREEN}%s${NC} - 大小: ${GREEN}%s${NC}, 使用率: ${GREEN}%s${NC}\n" "$MOUNT" "$SIZE" "$USAGE"
    done
else
    print_error "存储信息" "df 命令不可用"
fi

# 磁盘设备信息
if command -v lsblk &> /dev/null; then
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

if command -v ip &> /dev/null; then
    echo -e "  ${CYAN}网络接口:${NC}"
    ip link show | grep "^[0-9]" | while read -r line; do
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
    ifconfig | grep "^[a-z]" | awk '{print $1}' | while read -r iface; do
        IP=$(ifconfig "$iface" 2>/dev/null | grep "inet " | awk '{print $2}')
        if [ -n "$IP" ]; then
            printf "    ${GREEN}%s${NC}: ${GREEN}%s${NC}\n" "$iface" "$IP"
        fi
    done
else
    print_error "网络信息" "ip/ifconfig 命令不可用"
fi

################################################################################
# 总结
################################################################################
echo ""
print_header "✅ 系统信息检查完成"
echo ""
