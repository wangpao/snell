#!/bin/bash

# =================================================
#         BBR Status Checker & Enabler
# =================================================
#
# 功能:
# 1. 检查系统是否已开启 BBR。
# 2. 如果未开启，检查内核是否支持 BBR。
# 3. 如果支持，则提示用户一键开启 BBR。
#
# =================================================

# 定义颜色代码，让输出更美观
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN='\033[0m'

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

# 检查是否以 root 用户运行脚本
if [[ $EUID -ne 0 ]]; then
   colorEcho $RED "错误：本脚本必须以 root 权限运行！" 
   exit 1
fi

# 检查 BBR 是否已经启用
check_bbr_status() {
    # sysctl -n 命令只返回值，不返回键名
    local status=$(sysctl -n net.ipv4.tcp_congestion_control)
    if [[ "$status" == "bbr" ]]; then
        return 0 # 0 代表成功，即 BBR 已开启
    else
        return 1 # 1 代表失败，即 BBR 未开启
    fi
}

# 启用 BBR
enable_bbr() {
    colorEcho $YELLOW "正在为您开启 BBR..."

    # 检查 /etc/sysctl.conf 文件中是否已有相关配置，有则删除，避免重复
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf

    # 添加 BBR 配置到 /etc/sysctl.conf
    # fq (Fair Queue) 是 BBR 推荐的队列算法
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf

    # 应用配置使其立即生效
    sysctl -p > /dev/null 2>&1
    
    # 稍作等待，让系统应用更改
    sleep 1

    colorEcho $GREEN "BBR 配置已写入并应用。"
}

# 主逻辑
main() {
    colorEcho $YELLOW "========================================"
    colorEcho $YELLOW "    TCP BBR 状态检测与开启脚本"
    colorEcho $YELLOW "========================================"
    echo

    if check_bbr_status; then
        local bbr_version=$(uname -r)
        colorEcho $GREEN "恭喜！您的系统已开启 BBR。"
        colorEcho $GREEN "当前内核版本: $bbr_version"
        colorEcho $GREEN "当前拥塞控制算法: $(sysctl -n net.ipv4.tcp_congestion_control)"
        exit 0
    fi

    colorEcho $YELLOW "检测到您的系统当前未开启 BBR。"
    
    # 检查内核是否支持 BBR
    if ! sysctl net.ipv4.tcp_available_congestion_control | grep -q "bbr"; then
        colorEcho $RED "错误：您的系统内核不支持 BBR。"
        colorEcho $RED "请先将 Linux 内核升级到 4.9 或更高版本再尝试。"
        exit 1
    fi
    
    colorEcho $YELLOW "好消息是，您的系统内核支持 BBR！"
    echo
    read -p "是否需要现在为您开启 BBR? [Y/n] " answer

    # 如果用户不输入或输入y/Y，则认为同意
    if [[ -z "$answer" || "$answer" =~ ^[Yy]$ ]]; then
        enable_bbr
        
        # 最终确认
        if check_bbr_status; then
            colorEcho $GREEN "太棒了！BBR 已成功开启并正在运行。"
        else
            colorEcho $RED "出现未知错误，BBR 开启失败。"
            colorEcho $RED "请检查 /etc/sysctl.conf 文件或手动执行 sysctl -p 查看错误信息。"
        fi
    else
        colorEcho $YELLOW "操作已取消。"
    fi
}

# 执行主函数
main
