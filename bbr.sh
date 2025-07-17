#!/bin/bash

# 定义颜色代码，方便输出彩色信息
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

# 封装一个彩色输出的函数
colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

# 检查脚本是否以root用户运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
       colorEcho $RED "错误：此脚本必须以root用户身份运行！"
       colorEcho $YELLOW "请尝试使用 'sudo ./your_script_name.sh' 来运行。"
       exit 1
    fi
}

# 启用BBR的函数
enable_bbr() {
    colorEcho $YELLOW "正在修改系统配置文件 /etc/sysctl.conf ..."
    
    # 删除可能存在的旧配置，避免重复
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    
    # 追加新的BBR配置
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    
    colorEcho $GREEN "配置文件修改完成。"
    
    # 让配置立即生效
    colorEcho $YELLOW "正在应用新的内核参数..."
    sysctl -p > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        colorEcho $GREEN "内核参数已成功应用。"
    else
        colorEcho $RED "应用内核参数失败！请检查 /etc/sysctl.conf 文件是否有语法错误。"
        return 1
    fi
}

# 主函数
main() {
    clear
    colorEcho $BLUE "========================================="
    colorEcho $BLUE "       BBR 状态检测与开启脚本"
    colorEcho $BLUE "========================================="
    echo ""

    # 获取当前的TCP拥塞控制算法
    current_congestion_algo=$(sysctl net.ipv4.tcp_congestion_control | awk -F '= ' '{print $2}')
    
    # 检查BBR是否已经开启
    if [[ "$current_congestion_algo" == "bbr" ]]; then
        colorEcho $GREEN "太棒了！检测到 BBR 已经开启。"
        colorEcho $BLUE "当前拥塞控制算法: $current_congestion_algo"
        echo ""
        exit 0
    fi
    
    colorEcho $YELLOW "检测到 BBR 未开启。"
    colorEcho $BLUE "当前拥塞控制算法为: $current_congestion_algo"
    echo ""
    
    # 询问用户是否开启
    read -p "是否需要为您开启 BBR? [y/n] (默认: y): " choice
    # 如果用户直接回车，则默认为y
    [[ -z "$choice" ]] && choice="y"
    
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        enable_bbr
        
        # 最终验证
        echo ""
        colorEcho $YELLOW "正在进行最终验证..."
        final_status=$(sysctl net.ipv4.tcp_congestion_control | awk -F '= ' '{print $2}')
        if [[ "$final_status" == "bbr" ]]; then
            colorEcho $GREEN "成功！BBR 已开启并正在运行。"
            colorEcho $BLUE "您可以通过重新运行此脚本来确认状态。"
        else
            colorEcho $RED "失败！无法开启 BBR。请检查系统日志或手动配置。"
        fi
    else
        colorEcho $YELLOW "操作已取消。"
    fi
    echo ""
}

# 脚本执行入口
check_root
main
