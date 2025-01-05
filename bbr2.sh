#!/bin/bash

# 检查是否以 root 权限运行
if [ "$EUID" -ne 0 ]; then 
    echo "请使用 root 权限运行此脚本"
    exit 1
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# 检查 BBR 是否已经启用
check_bbr() {
    local bbr_loaded=$(lsmod | grep bbr)
    local current_cc=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
    
    if [[ -n "$bbr_loaded" && "$current_cc" == "bbr" ]]; then
        return 0 # BBR 已启用
    else
        return 1 # BBR 未启用
    fi
}

# 启用 BBR
enable_bbr() {
    # 加载 BBR 模块
    modprobe tcp_bbr
    
    # 设置 BBR 为默认拥塞控制算法
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    
    # 应用设置
    sysctl -p
    
    # 检查是否成功启用
    if check_bbr; then
        echo -e "${GREEN}BBR 已成功启用！${NC}"
        return 0
    else
        echo -e "${RED}BBR 启用失败！${NC}"
        return 1
    fi
}

# 主程序
main() {
    echo "正在检查 BBR 状态..."
    
    if check_bbr; then
        echo -e "${GREEN}BBR 已经启用，无需再次启用。${NC}"
        echo "当前拥塞控制算法: $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')"
        exit 0
    fi
    
    echo -e "${RED}BBR 未启用${NC}"
    read -p "是否要启用 BBR？(y/n) " choice
    
    case "$choice" in
        y|Y)
            echo "正在启用 BBR..."
            enable_bbr
            ;;
        n|N)
            echo "操作已取消"
            exit 0
            ;;
        *)
            echo "无效的选择"
            exit 1
            ;;
    esac
}

# 运行主程序
main
