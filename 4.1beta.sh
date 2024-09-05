#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

snell_conf="/etc/snell/snell-server.conf"

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

check_sys() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -q -E -i "debian"; then
        release="debian"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -q -E -i "debian"; then
        release="debian"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        release="centos"
    fi
}

install_snell() {
    if [[ -f /etc/snell/snell-server.conf ]]; then
        colorEcho $YELLOW " Snell 已经安装，请勿重复安装"
        return
    fi

    colorEcho $BLUE " 安装 Snell..."
    local ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64)
            ARCH="amd64"
            ;;
        armv8|aarch64)
            ARCH="aarch64"
            ;;
        *)
            colorEcho $RED " 不支持的架构: ${ARCH}. 请使用 x86_64/amd64 或 armv8/aarch64."
            exit 1
            ;;
    esac

    SNELL_VER="v4.1"
    DOWNLOAD_LINK="https://github.com/surge-networks/snell/releases/download/${SNELL_VER}/snell-server-${SNELL_VER}-linux-${ARCH}.zip"
    wget -O snell.zip $DOWNLOAD_LINK
    unzip -o snell.zip
    rm -f snell.zip
    chmod +x snell-server
    mv snell-server /usr/local/bin/

    mkdir -p /etc/snell
    cat > $snell_conf<<-EOF
[snell-server]
listen = 0.0.0.0:13254
ipv6 = false
obfs = off
tfo = true
psk = $(openssl rand -base64 32)
EOF

    if [[ $release = "centos" ]]; then
        cat > /etc/systemd/system/snell.service <<-EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
LimitNOFILE=65535
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    else
        cat > /lib/systemd/system/snell.service <<-EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
LimitNOFILE=65535
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    fi

    systemctl daemon-reload
    systemctl enable snell
    systemctl start snell

    colorEcho $GREEN " Snell ${SNELL_VER} 安装完成."
    colorEcho $YELLOW " Snell 配置文件: ${snell_conf}"
    colorEcho $YELLOW " 请记录以下信息:"
    cat $snell_conf
}

check_update() {
    if [[ ! -f /etc/snell/snell-server.conf ]]; then
        colorEcho $RED " Snell 未安装，无法检查更新"
        return
    fi

    local current_version=$(/usr/local/bin/snell-server --version 2>&1 | grep -oP 'snell-server version \K\S+')
    colorEcho $BLUE " 当前安装的 Snell 版本：$current_version"

    if [[ "$current_version" != "v4.1" ]]; then
        colorEcho $YELLOW " 发现新版本 v4.1，是否升级？(y/n)"
        read -r update_confirm
        if [[ "$update_confirm" == "y" || "$update_confirm" == "Y" ]]; then
            upgrade_snell
        else
            colorEcho $YELLOW " 取消升级"
        fi
    else
        colorEcho $GREEN " 当前已是最新版本 v4.1，无需升级"
    fi
}

upgrade_snell() {
    colorEcho $BLUE " 开始升级到版本 v4.1"

    # 备份当前配置
    cp $snell_conf ${snell_conf}.bak

    # 停止当前服务
    systemctl stop snell

    # 下载并安装新版本
    install_snell

    # 恢复配置
    cp ${snell_conf}.bak $snell_conf

    # 重启服务
    systemctl start snell

    colorEcho $GREEN " Snell 已成功升级到版本 v4.1"
}

uninstall_snell() {
    colorEcho $BLUE " 卸载 Snell..."
    systemctl stop snell
    systemctl disable snell
    rm -rf /etc/snell
    rm -f /usr/local/bin/snell-server
    rm -f /etc/systemd/system/snell.service
    rm -f /lib/systemd/system/snell.service
    systemctl daemon-reload
    colorEcho $GREEN " Snell 已成功卸载"
}

show_menu() {
    echo -e "
  ${GREEN}1.${PLAIN} 安装 Snell
  ${GREEN}2.${PLAIN} 卸载 Snell
  ${GREEN}3.${PLAIN} 查看配置
  ${GREEN}4.${PLAIN} 检查更新
  ${GREEN}0.${PLAIN} 退出脚本
 "
    read -p " 请选择操作[0-4]：" option
    case "${option}" in
        1)
            install_snell
            ;;
        2)
            uninstall_snell
            ;;
        3)
            cat ${snell_conf}
            ;;
        4)
            check_update
            ;;
        0)
            exit 0
            ;;
        *)
            colorEcho $RED " 请输入正确的数字 [0-4]"
            ;;
    esac
}

check_sys
[[ ${EUID} != 0 ]] && echo -e "${RED}错误：${PLAIN} 必须使用 root 用户运行此脚本！\n" && exit 1

show_menu
