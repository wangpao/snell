#!/bin/bash

# 检查是否已启用 BBR V3
check_bbr3_enabled() {
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        return 0
    else
        return 1
    fi
}

# 询问用户是否继续
ask_to_continue() {
    read -p "BBR V3 未启用。是否要安装新内核并启用 BBR V3？(y/n) " answer
    case ${answer:0:1} in
        y|Y )
            return 0
        ;;
        * )
            echo "操作已取消。"
            exit 0
        ;;
    esac
}

# 安装依赖项
install_dependencies() {
    apt update
    apt install wget curl -y
}

# 获取最新内核版本的下载链接
get_latest_kernel_urls() {
    curl -s "https://api.github.com/repos/Naochen2799/Latest-Kernel-BBR3/releases/latest" \
    | grep "browser_download_url" \
    | grep -v "linux-libc-dev" \
    | cut -d '"' -f 4
}

# 下载内核
download_kernels() {
    local urls=("$@")
    for url in "${urls[@]}"; do
        wget -P /root/bbr3 "$url"
    done
}

# 安装内核
install_kernels() {
    dpkg -i /root/bbr3/*.deb
}

# 启用 BBR V3
enable_bbr3() {
    echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
}

# 检查 BBR V3 状态
check_bbr3_status() {
    echo "当前的 TCP 流控算法："
    sysctl net.ipv4.tcp_congestion_control
    echo "可用的 TCP 流控算法："
    sysctl net.ipv4.tcp_available_congestion_control
}

# 检查操作是否成功
check_operation() {
    if [ $? -ne 0 ]; then
        echo "错误：$1 失败"
        exit 1
    fi
}

# 主程序
main() {
    if check_bbr3_enabled; then
        echo "BBR V3 已经成功启用。无需进行任何操作。"
        check_bbr3_status
        exit 0
    else
        echo "BBR V3 未启用。"
        ask_to_continue
    fi

    install_dependencies
    check_operation "安装依赖项"

    local kernel_urls
    kernel_urls=($(get_latest_kernel_urls))
    if [ ${#kernel_urls[@]} -gt 0 ]; then
        download_kernels "${kernel_urls[@]}"
        check_operation "下载内核"

        install_kernels
        check_operation "安装内核"

        echo "内核安装完成，正在启用 BBR V3..."
        enable_bbr3
        check_operation "启用 BBR V3"

        if check_bbr3_enabled; then
            echo "BBR V3 已成功启用"
        else
            echo "警告：BBR V3 可能未成功启用，请在重启后再次检查"
        fi

        check_bbr3_status

        echo "安装和配置完成。请重启系统以使用新内核和 BBR V3。"
        echo "重启后，请运行以下命令再次检查 BBR V3 状态："
        echo "sysctl net.ipv4.tcp_congestion_control"
    else
        echo "无法获取内核下载链接，请检查网络连接或稍后重试。"
        exit 1
    fi
}

main