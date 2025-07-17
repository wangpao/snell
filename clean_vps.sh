#!/bin/bash

# =================================================================
#               VPS 彻底清理脚本 for Ubuntu 22.04+
# =================================================================
#  本脚本会执行深度系统清理，包括删除日志、缓存、文档和语言包。
#  请仅在确认服务器上没有重要文件时使用！
# =================================================================

# --- 颜色定义 ---
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

# --- 辅助函数 ---
colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

# --- 检查Root权限 ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
       colorEcho $RED "错误：此脚本必须以root用户身份运行！"
       colorEcho $YELLOW "请尝试使用 'sudo ./clean_vps.sh' 来运行。"
       exit 1
    fi
}

# --- 获取可用磁盘空间 (单位: KB) ---
get_available_space_kb() {
    # 使用df -k确保单位统一为KB，并提取根分区的可用空间
    df -k / | awk 'NR==2 {print $4}'
}

# --- 清理任务函数 ---

# 1. 包管理器清理
clean_package_manager() {
    colorEcho $BLUE "\n[1/6] 正在执行包管理器清理..."
    apt-get update -y > /dev/null 2>&1
    colorEcho $GREEN "  -> 正在删除无用的包 (autoremove --purge)..."
    apt-get autoremove --purge -y > /dev/null 2>&1
    colorEcho $GREEN "  -> 正在清理apt缓存 (clean)..."
    apt-get clean -y > /dev/null 2>&1
    colorEcho $GREEN "  -> 正在清理过时的包 (autoclean)..."
    apt-get autoclean -y > /dev/null 2>&1
    colorEcho $GREEN "  -> 正在清理apt列表缓存..."
    rm -rf /var/lib/apt/lists/*
}

# 2. 系统日志清理
clean_system_logs() {
    colorEcho $BLUE "\n[2/6] 正在执行系统日志清理..."
    colorEcho $GREEN "  -> 正在清理 journald 日志, 保留最近2天..."
    journalctl --vacuum-time=2d > /dev/null 2>&1
    colorEcho $GREEN "  -> 正在清空 /var/log/ 下的所有 .log 文件..."
    find /var/log -type f -name "*.log" -exec sh -c '> "{}"' \;
    colorEcho $GREEN "  -> 正在删除旧的已轮转日志 (.gz, .1, .2...)..."
    find /var/log -type f -regex ".*\.\(gz\|[0-9]\)$" -delete
}

# 3. 临时文件和用户缓存清理
clean_temp_files() {
    colorEcho $BLUE "\n[3/6] 正在执行临时文件和用户缓存清理..."
    colorEcho $GREEN "  -> 正在清理 /tmp 和 /var/tmp..."
    rm -rf /tmp/* /var/tmp/*
    colorEcho $GREEN "  -> 正在清理所有用户的bash历史记录..."
    find /home -type f -name ".bash_history" -delete
    rm -f /root/.bash_history
    colorEcho $GREEN "  -> 正在清理所有用户的缓存目录..."
    rm -rf /root/.cache/*
    # 为避免删除重要结构，只清空.cache目录内容，不删除目录本身
    find /home -type d -name ".cache" -exec rm -rf {}/* \;
}

# 4. 系统缓存清理 (部分与包管理器重叠，但确保彻底)
clean_system_caches() {
    colorEcho $BLUE "\n[4/6] 正在执行系统缓存清理..."
    colorEcho $GREEN "  -> 正在清理已下载的deb包缓存..."
    rm -rf /var/cache/apt/archives/*.deb
}

# 5. 文档和手册清理
clean_docs_manuals() {
    colorEcho $BLUE "\n[5/6] 正在执行文档、手册和信息页清理..."
    colorEcho $GREEN "  -> 正在删除 /usr/share/doc..."
    rm -rf /usr/share/doc/*
    colorEcho $GREEN "  -> 正在删除 /usr/share/man..."
    rm -rf /usr/share/man/*
    colorEcho $GREEN "  -> 正在删除 /usr/share/info..."
    rm -rf /usr/share/info/*
}

# 6. 语言包清理
clean_language_packs() {
    colorEcho $BLUE "\n[6/6] 正在执行非中/英文语言包清理..."
    # 检查 localepurge 是否安装
    if ! command -v localepurge >/dev/null 2>&1; then
        colorEcho $YELLOW "  -> 未找到 localepurge，正在自动安装..."
        # 预先配置 debconf，避免安装时出现交互式提示
        echo "localepurge localepurge/nopurge multiselect en,en_US,en_US.UTF-8,zh,zh_CN,zh_CN.UTF-8" | debconf-set-selections
        apt-get install -y localepurge > /dev/null 2>&1
    fi
    colorEcho $GREEN "  -> 正在运行 localepurge 清理多余语言包..."
    localepurge
}

# --- 主函数 ---
main() {
    check_root
    clear
    
    colorEcho $YELLOW "========================================================"
    colorEcho $YELLOW "           欢迎使用 VPS 彻底清理脚本"
    colorEcho $YELLOW "========================================================"
    echo ""
    colorEcho $RED "警告：此脚本将执行破坏性操作，会删除大量系统文件！"
    colorEcho $RED "包括日志、缓存、文档、手册、部分语言包等。"
    colorEcho $RED "请确保您了解其后果，并且服务器上没有需要保留的数据。"
    echo ""

    # 获取并显示清理前的磁盘空间
    local space_before_kb=$(get_available_space_kb)
    local space_before_mb=$(echo "scale=2; $space_before_kb / 1024" | bc)
    colorEcho $BLUE "清理前可用空间: ${space_before_mb} MB"
    echo ""

    # 最终确认
    read -p $'请再次确认是否执行清理操作？请输入大写的 "YES" 继续: ' confirmation
    if [[ "$confirmation" != "YES" ]]; then
        colorEcho $YELLOW "操作已取消。"
        exit 0
    fi
    
    # 开始执行清理
    clean_package_manager
    clean_system_logs
    clean_temp_files
    clean_system_caches
    clean_docs_manuals
    clean_language_packs
    
    colorEcho $YELLOW "\n========================================================"
    colorEcho $GREEN "          所有清理任务已执行完毕！"
    colorEcho $YELLOW "========================================================"
    echo ""
    
    # 获取并显示清理后的磁盘空间
    local space_after_kb=$(get_available_space_kb)
    local space_after_mb=$(echo "scale=2; $space_after_kb / 1024" | bc)
    
    # 计算释放的空间
    local freed_kb=$((space_after_kb - space_before_kb))
    local freed_mb=$(echo "scale=2; $freed_kb / 1024" | bc)
    
    colorEcho $BLUE "清理前可用空间: ${space_before_mb} MB"
    colorEcho $BLUE "清理后可用空间: ${space_after_mb} MB"
    colorEcho $GREEN "成功释放空间: ${freed_mb} MB"
    echo ""
}

# --- 脚本入口 ---
main