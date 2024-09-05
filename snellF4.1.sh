#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

IP4=$(curl -sL -4 ip.sb)
CPU=$(uname -m)
snell_conf="/etc/snell/snell-server.conf"
stls_conf="/etc/systemd/system/shadowtls.service"

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

archAffix(){
    if [[ "$CPU" = "x86_64" ]] || [[ "$CPU" = "amd64" ]]; then
        CPU="amd64"
        ARCH="amd64"
    elif [[ "$CPU" = "armv8" ]] || [[ "$CPU" = "aarch64" ]]; then
        CPU="arm64"
        ARCH="aarch64"
    elif [[ "$CPU" = "armv7l" ]]; then
        CPU="arm"
        ARCH="armv7l"
    elif [[ "$CPU" = "i386" ]]; then
        CPU="386"
        ARCH="i386"
    else
        colorEcho $RED " 不支持的CPU架构！"
        exit 1
    fi
}

checkSystem() {
    result=$(id | awk '{print $1}')
    if [[ $result != "uid=0(root)" ]]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    res=$(which yum 2>/dev/null)
    if [[ "$?" != "0" ]]; then
        res=$(which apt 2>/dev/null)
        if [[ "$?" != "0" ]]; then
            colorEcho $RED " 不受支持的Linux系统"
            exit 1
        fi
        OS="apt"
    else
        OS="yum"
    fi
    res=$(which systemctl 2>/dev/null)
    if [[ "$?" != "0" ]]; then
        colorEcho $RED " 系统版本过低，请升级到最新版本"
        exit 1
    fi
}

status() {
    if [[ ! -f /etc/snell/snell ]]; then
        echo 0
        return
    fi
    if [[ ! -f $snell_conf ]]; then
        echo 1
        return
    fi
    port=$(grep listen ${snell_conf} | awk -F '=' '{print $2}' | cut -d: -f2)
    res=$(ss -nutlp| grep ${port} | grep -i snell)
    if [[ -z $res ]]; then
        echo 2
    else
        echo 3
    fi
}

statusText() {
    res=$(status)
    case $res in
        2)
            echo -e ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}
            ;;
        3)
            echo -e ${GREEN}已安装${PLAIN} ${GREEN}正在运行${PLAIN}
            ;;
        *)
            echo -e ${RED}未安装${PLAIN}
            ;;
    esac
}

Install_dependency(){
    if [[ ${OS} == "yum" ]]; then
        colorEcho $YELLOW "安装依赖中..."
        yum install unzip wget -y >/dev/null 2>&1
    else
        colorEcho $YELLOW "安装依赖中..."
        apt install unzip wget -y >/dev/null 2>&1
    fi
}

Download_snell(){
    rm -rf /etc/snell /tmp/snell
    mkdir -p /etc/snell /tmp/snell
    archAffix
    DOWNLOAD_LINK="https://dl.nssurge.com/snell/snell-server-v4.1.0-linux-${ARCH}.zip"
    colorEcho $YELLOW "下载Snell: ${DOWNLOAD_LINK}"
    curl -L -H "Cache-Control: no-cache" -o /tmp/snell/snell.zip ${DOWNLOAD_LINK}
    unzip /tmp/snell/snell.zip -d /tmp/snell/
    mv /tmp/snell/snell-server /etc/snell/snell
    chmod +x /etc/snell/snell
}

Download_stls() {
    rm -rf /etc/snell/shadowtls
    archAffix
    TAG_URL="https://api.github.com/repos/ihciah/shadow-tls/releases/latest"
    DOWN_VER=$(curl -s "${TAG_URL}" --connect-timeout 10| grep -Eo '"tag_name"(.*?)","' | cut -d\" -f4)
    DOWNLOAD_LINK="https://github.com/ihciah/shadow-tls/releases/download/${DOWN_VER}/shadow-tls-${ARCH}-unknown-linux-musl"
    colorEcho $YELLOW "下载ShadowTLS: ${DOWNLOAD_LINK}"
    curl -L -H "Cache-Control: no-cache" -o /etc/snell/shadowtls ${DOWNLOAD_LINK}
    chmod +x /etc/snell/shadowtls

    if [ ! -s /etc/snell/shadowtls ]; then
        colorEcho $RED "ShadowTLS 下载失败或文件为空"
        return 1
    fi

    file_type=$(file /etc/snell/shadowtls)
    if [[ $file_type != *"ELF 64-bit LSB executable"* && $file_type != *"ELF 32-bit LSB executable"* ]]; then
        colorEcho $RED "下载的文件不是有效的可执行文件"
        return 1
    fi

    if ! /etc/snell/shadowtls --version &> /dev/null; then
        colorEcho $RED "ShadowTLS 可执行文件似乎无法正常运行"
        return 1
    fi

    colorEcho $GREEN "ShadowTLS 下载并验证成功"
    return 0
}

Generate_conf(){
    Set_port
    Set_psk
}

Set_port(){
    read -p $'请输入 Snell 端口 [1-65535]\n(默认: 6666，回车): ' PORT
    [[ -z "${PORT}" ]] && PORT="6666"
    if [[ "${PORT}" =~ ^[0-9]+$ ]] && [[ ${PORT} -ge 1 ]] && [[ ${PORT} -le 65535 ]]; then
        colorEcho $BLUE "端口: ${PORT}"
    else
        colorEcho $RED "输入错误, 请输入1-65535之间的数字。"
        Set_port
    fi
}

Set_psk(){
    read -p $'请输入 Snell PSK 密钥\n(推荐随机生成，直接回车): ' PSK
    [[ -z "${PSK}" ]] && PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    colorEcho $BLUE "PSK: ${PSK}"
}

Write_config(){
    cat > ${snell_conf}<<-EOF
[snell-server]
listen = 0.0.0.0:${PORT}
psk = ${PSK}
ipv6 = false
obfs = off
tfo = true
version = 4
EOF
}

Install_snell(){
    Install_dependency
    Generate_conf
    Download_snell
    Write_config
    Deploy_snell
    if ! Download_stls; then
        colorEcho $RED "ShadowTLS 安装失败，请检查网络连接或稍后重试"
        exit 1
    fi
    Deploy_stls
    colorEcho $BLUE "安装完成"
    ShowInfo
}

Deploy_snell(){
    cat > /etc/systemd/system/snell.service<<-EOF
[Unit]
Description=Snell Server
After=network.target

[Service]
ExecStart=/etc/snell/snell -c /etc/snell/snell-server.conf
Restart=on-failure
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable snell
    systemctl restart snell
}

Deploy_stls() {
    cat > /etc/systemd/system/shadowtls.service<<-EOF
[Unit]
Description=Shadow-TLS Server Service
After=network.target

[Service]
ExecStart=/etc/snell/shadowtls --fastopen --v3 server --listen 0.0.0.0:$(($PORT+1)) --server 127.0.0.1:${PORT} --tls gateway.icloud.com --password ${PSK}
Restart=on-failure
RestartSec=1s

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable shadowtls
    systemctl restart shadowtls
}

Restart_snell(){
    systemctl restart snell
    systemctl restart shadowtls
    colorEcho $BLUE " Snell 和 ShadowTLS 已重启"
}

Stop_snell(){
    systemctl stop snell
    systemctl stop shadowtls
    colorEcho $BLUE " Snell 和 ShadowTLS 已停止"
}

Uninstall_snell(){
    read -p $' 是否卸载Snell和ShadowTLS？[y/n]\n (默认n, 回车): ' answer
    if [[ "${answer}" = "y" ]]; then
        systemctl stop snell shadowtls
        systemctl disable snell shadowtls >/dev/null 2>&1
        rm -rf /etc/systemd/system/snell.service
        rm -rf /etc/systemd/system/shadowtls.service
        rm -rf /etc/snell
        systemctl daemon-reload
        colorEcho $BLUE " Snell和ShadowTLS已经卸载完毕"
    else
        colorEcho $BLUE " 取消卸载"
    fi
}

ShowInfo() {
    if [[ ! -f $snell_conf ]]; then
        colorEcho $RED " Snell未安装"
        exit 1
    fi
    port=$(grep listen ${snell_conf} | awk -F '=' '{print $2}' | cut -d: -f2)
    psk=$(grep psk ${snell_conf} | awk -F '= ' '{print $2}')
    stls_port=$((port+1))

    echo ""
    echo -e " ${BLUE}Snell配置信息：${PLAIN}"
    echo -e "   ${BLUE}地址(IP): ${PLAIN} ${RED}${IP4}${PLAIN}"
    echo -e "   ${BLUE}Snell端口(PORT)：${PLAIN} ${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}ShadowTLS端口(PORT)：${PLAIN} ${RED}${stls_port}${PLAIN}"
    echo -e "   ${BLUE}密钥(PSK)：${PLAIN} ${RED}${psk}${PLAIN}"
    echo -e "   ${BLUE}Snell版本：${PLAIN} ${RED}4${PLAIN}"
    echo -e "   ${BLUE}ShadowTLS版本：${PLAIN} ${RED}3${PLAIN}"
    echo -e "   ${BLUE}ShadowTLS域名：${PLAIN} ${RED}gateway.icloud.com${PLAIN}"
}

Upgrade_snell() {
    if [[ ! -f /etc/snell/snell ]]; then
        colorEcho $RED "Snell 未安装，无法升级"
        return
    fi

    current_version=$(/etc/snell/snell --version 2>&1 | grep -oP 'snell-server version \K\S+')
    colorEcho $BLUE "当前安装的 Snell 版本：$current_version"

    DOWNLOAD_LINK="https://dl.nssurge.com/snell/snell-server-v4.1.0-linux-${ARCH}.zip"
    colorEcho $YELLOW "开始下载 Snell v4.1.0"

    # 备份当前配置
    cp $snell_conf ${snell_conf}.bak

    # 停止当前服务
    systemctl stop snell

    # 下载并安装新版本
    Download_snell

    # 恢复配置
    cp ${snell_conf}.bak $snell_conf

    # 重启服务
    systemctl start snell

    new_version=$(/etc/snell/snell --version 2>&1 | grep -oP 'snell-server version \K\S+')
    colorEcho $GREEN "Snell 已成功升级到版本 $new_version"
}

menu() {
    clear
    echo "################################"
    echo -e "#  ${RED}Snell + ShadowTLS 一键脚本${PLAIN}  #"
    echo "################################"
    echo " ----------------------"
    echo -e "  ${GREEN}1.${PLAIN}  安装"
    echo -e "  ${GREEN}2.${PLAIN}  ${RED}卸载${PLAIN}"
    echo " ----------------------"
    echo -e "  ${GREEN}3.${PLAIN}  启动"
    echo -e "  ${GREEN}4.${PLAIN}  重启"
    echo -e "  ${GREEN}5.${PLAIN}  停止"
    echo " ----------------------"
    echo -e "  ${GREEN}6.${PLAIN}  查看配置"
    echo -e "  ${GREEN}7.${PLAIN}  升级 Snell"
    echo " ----------------------"
    echo -e "  ${GREEN}0.${PLAIN}  退出"
    echo 
    echo -n " 当前状态："
    statusText
    echo 

    read -p " 请选择操作[0-7]：" answer
    case $answer in
        0)
            exit 0
            ;;
        1)
            Install_snell
            ;;
        2)
            Uninstall_snell
            ;;
        3)
            systemctl start snell
            systemctl start shadowtls
            colorEcho $BLUE " Snell 和 ShadowTLS 已启动"
            ;;
        4)
            Restart_snell
            ;;
        5)
            Stop_snell
            ;;
        6)
            ShowInfo
            ;;
        7)
            Upgrade_snell
            ;;
        *)
            colorEcho $RED " 请选择正确的操作！"
            sleep 2s
            menu
            ;;
    esac
}

checkSystem
menu
