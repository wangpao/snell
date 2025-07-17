#!/bin/bash

# 定义颜色代码
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

# 封装彩色输出函数
colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
       colorEcho $RED "错误：此脚本必须以root用户身份运行！"
       exit 1
    fi
}

# 启用BBR的函数 (此函数不变，因为它已经正确设置了两个参数)
enable_bbr() {
    colorEcho $YELLOW "正在修改系统配置文件 /etc/sysctl.conf 以永久生效..."
    
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    
    colorEcho $YELLOW "正在应用新的内核参数..."
    sysctl -p > /dev/null 2>&1
    return $?
}

# 主函数
main() {
    clear
    colorEcho $BLUE "================================================="
    colorEcho $BLUE "    BBR 状态与配置严谨检测及开启脚本"
    colorEcho $BLUE "================================================="
    echo ""

    # 获取两个关键参数的当前值
    congestion_algo=$(sysctl net.ipv4.tcp_congestion_control | awk -F '= ' '{print $2}')
    qdisc=$(sysctl net.core.default_qdisc | awk -F '= ' '{print $2}')
    
    colorEcho $YELLOW "当前系统配置检测结果:"
    echo "-------------------------------------------------"
    echo -n "TCP拥塞控制算法 (tcp_congestion_control): "
    if [[ "$congestion_algo" == "bbr" ]]; then
        colorEcho $GREEN $congestion_algo
    else
        colorEcho $RED $congestion_algo
    fi

    echo -n "默认队列调度算法 (default_qdisc):         "
    if [[ "$qdisc" == "fq" ]]; then
        colorEcho $GREEN $qdisc
    else
        colorEcho $RED $qdisc
    fi
    echo "-------------------------------------------------"
    echo ""

    # 根据两个参数的值进行综合判断
    if [[ "$congestion_algo" == "bbr" && "$qdisc" == "fq" ]]; then
        colorEcho $GREEN "诊断: BBR 已完全开启并处于最佳配置状态。"
        exit 0
    elif [[ "$congestion_algo" == "bbr" && "$qdisc" != "fq" ]]; then
        colorEcho $YELLOW "诊断: BBR 已开启，但配置非最优！"
        colorEcho $YELLOW "队列调度算法应为 'fq' 才能发挥最佳性能。"
    else
        colorEcho $RED "诊断: BBR 未开启。"
    fi
    
    echo ""
    read -p "是否需要为您自动配置并开启BBR? [y/n] (默认: y): " choice
    [[ -z "$choice" ]] && choice="y"
    
    if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
        enable_bbr
        if [[ $? -eq 0 ]]; then
            # 最终验证
            final_algo=$(sysctl net.ipv4.tcp_congestion_control | awk -F '= ' '{print $2}')
            final_qdisc=$(sysctl net.core.default_qdisc | awk -F '= ' '{print $2}')
            if [[ "$final_algo" == "bbr" && "$final_qdisc" == "fq" ]]; then
                colorEcho $GREEN "成功！BBR 已正确开启并配置为最佳状态。"
            else
                colorEcho $RED "操作完成但验证失败，请检查系统日志。"
            fi
        else
            colorEcho $RED "应用内核参数失败！请检查 /etc/sysctl.conf 文件是否有语法错误。"
        fi
    else
        colorEcho $YELLOW "操作已取消。"
    fi
    echo ""
}

# 脚本执行入口
check_root
main
