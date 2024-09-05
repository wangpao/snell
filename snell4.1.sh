#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

IP4=$(curl -sL -4 ip.sb)
IP6=$(curl -sL -6 ip.sb)
CPU=$(uname -m)
snell_conf="/etc/snell/snell-server.conf"
stls_conf="/etc/systemd/system/shadowtls.service"

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

versions=(
v1
v2
v3
v4
v4.1
)

domains=(
gateway.icloud.com
cn.bing.com
mp.weixin.qq.com
自定义
)

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
    tmp=$(grep listen ${snell_conf} | awk -F '=' '{print $2}' | cut -d: -f2)
    if [[ -z ${tmp} ]]; then
        tmp=$(grep listen ${snell_conf} | awk -F '=' '{print $2}' | cut -d: -f4)
    fi
    res=$(ss -nutlp| grep ${tmp} | grep -i snell)
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
    echo "net.ipv4.tcp_fastopen=3" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
}

selectversion() {
    for ((i=1;i<=${#versions[@]};i++ )); do
        hint="${versions[$i-1]}"
        echo -e "${GREEN}${i}${PLAIN}) ${hint}"
    done
    read -p "请选择版本[1-5] (默认: ${versions[4]}):" pick
    [ -z "$pick" ] && pick=5
    expr ${pick} + 1 &>/dev/null
    if [ $? -ne 0 ]; then
        colorEcho $RED "错误, 请选择[1-5]"
        selectversion
    fi
    if [[ "$pick" -lt 1 || "$pick" -gt ${#versions[@]} ]]; then
        colorEcho $RED "错误, 请选择[1-5]"
        selectversion
    fi
    vers=${versions[$pick-1]}
    if [[ "$pick" = "5" ]]; then
        VER="v4.1.0"
    elif [[ "$pick" = "4" ]]; then
        VER="v4.0.1"
    else
        VER="v3.0.1"
    fi
}

Download_snell(){
    rm -rf /etc/snell /tmp/snell
    mkdir -p /etc/snell /tmp/snell
    archAffix
    if [[ "$VER" = "v4.1.0" ]]; then
        DOWNLOAD_LINK="https://dl.nssurge.com/snell/snell-server-${VER}-linux-${ARCH}.zip"
    else
        DOWNLOAD_LINK="https://raw.githubusercontent.com/Slotheve/Snell/main/snell-server-${VER}-linux-${CPU}.zip"
    fi
    colorEcho $YELLOW "下载Snell: ${DOWNLOAD_LINK}"
    curl -L -H "Cache-Control: no-cache" -o /tmp/snell/snell.zip ${DOWNLOAD_LINK}
    unzip /tmp/snell/snell.zip -d /tmp/snell/
    mv /tmp/snell/snell-server /etc/snell/snell
    chmod +x /etc/snell/snell
}

Generate_conf(){
    Set_V6
    Set_port
    Set_psk
    Set_obfs
    Set_tfo
}

Set_V6(){
    read -p $'是否开启V6？[y/n]\n(默认n, 回车): ' answer
    if [[ "${answer}" = "y" ]]; then
        if [[ $VER == "v3.0.1" ]]; then
            LIP="[::]"
            colorEcho $BLUE "启用V6"
        else
            LIP="::0"
            colorEcho $BLUE "启用V6"
        fi
        V6="true"
    elif [[ "${answer}" = "n" || -z "${answer}" ]]; then
        colorEcho $BLUE "禁用V6"
        LIP="0.0.0.0"
        V6="false"
    else
        colorEcho $RED "输入错误, 请输入 y/n"
        Set_V6
    fi
}

Set_port(){
    read -p $'请输入 Snell 端口 [1-65535]\n(默认: 6666，回车): ' PORT
    [[ -z "${PORT}" ]] && PORT="6666"
    echo $((${PORT}+0)) &>/dev/null
    if [[ $? -eq 0 ]]; then
        if [[ ${PORT} -ge 1 ]] && [[ ${PORT} -le 65535 ]]; then
            colorEcho $BLUE "端口: ${PORT}"
        else
            colorEcho $RED "输入错误, 请输入正确的端口。"
            Set_port
        fi
    else
        colorEcho $RED "输入错误, 请输入数字。"
        Set_port
    fi
}

Set_psk(){
    read -p $'请输入 Snell PSK 密钥\n(推荐随机生成，直接回车): ' PSK
    [[ -z "${PSK}" ]] && PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)
    colorEcho $BLUE "PSK: ${PSK}"
}

Set_obfs(){
    read -p $'是否开启obfs？[y/n]\n(默认n, 回车): ' answer
    if [[ "${answer}" = "y" ]]; then
        read -e -p "请输入 obfs 混淆 (tls/http): " OBFS
        if [[ "${OBFS}" = "tls" || "${OBFS}" = "http" ]]; then
            colorEcho $BLUE "obfs: ${OBFS}"
        else
            colorEcho $RED "错误, 请输入 http/tls"
            Set_obfs
        fi
    elif [[ "${answer}" = "n" || -z "${answer}" ]]; then
        if [[ $VER == "v3.0.1" ]]; then
            OBFS="none"
            colorEcho $BLUE "禁用obfs"
        else
            OBFS="off"
            colorEcho $BLUE "禁用obfs"
        fi
    else
        colorEcho $RED "错误, 请输入 y/n"
        Set_obfs
    fi
}

Set_tfo(){
    read -p $'是否开启TFO？[y/n]\n(默认n, 回车): ' answer
    if [[ "${answer}" = "y" ]]; then
        TFO="true"
        colorEcho $BLUE "启用TFO"
    elif [[ "${answer}" = "n" || -z "${answer}" ]]; then
        TFO="false"
        colorEcho $BLUE "禁用TFO"
    else
        colorEcho $RED "错误, 请输入 y/n"
        Set_tfo
    fi
}

Write_config(){
    cat > ${snell_conf}<<-EOF
[snell-server]
listen = ${LIP}:${PORT}
psk = ${PSK}
ipv6 = ${V6}
obfs = ${OBFS}
tfo = ${TFO}
# ${vers}
EOF
}

Install_snell(){
    Install_dependency
    selectversion
    Generate_conf
    Download_snell
    Write_config
    Deploy_snell
    colorEcho $BLUE "安装完成"
    ShowInfo
}

Deploy_snell(){
    cd /etc/systemd/system
    cat > snell.service<<-EOF
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
    echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
    sysctl -p
}

Restart_snell(){
    systemctl restart snell
    colorEcho $BLUE " Snell已启动"
}

Stop_snell(){
    systemctl stop snell
    colorEcho $BLUE " Snell已停止"
}

Uninstall_snell(){
    read -p $' 是否卸载Snell？[y/n]\n (默认n, 回车): ' answer
    if [[ "${answer}" = "y" ]]; then
        systemctl stop snell
        systemctl disable snell >/dev/null 2>&1
        rm -rf /etc/systemd/system/snell.service
        rm -rf /etc/snell
        systemctl daemon-reload
        colorEcho $BLUE " Snell已经卸载完毕"
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
    if [[ -z "${port}" ]]; then
        port=$(grep listen ${snell_conf} | awk -F '=' '{print $2}' | cut -d: -f4)
    fi
    psk=$(grep psk ${snell_conf} | awk -F '= ' '{print $2}')
    ipv6=$(grep ipv6 ${snell_conf} | awk -F '= ' '{print $2}')
    if [[ $ipv6 == "true" ]]; then
        IP=$IP6
    else
        IP=$IP4
    fi
    obfs=$(grep obfs ${snell_conf} | awk -F '= ' '{print $2}')
    tfo=$(grep tfo ${snell_conf} | awk -F '= ' '{print $2}')
    ver=$(grep '#' ${snell_conf} | awk -F '# ' '{print $2}')
    echo ""
    echo -e " ${BLUE}Snell配置文件: ${PLAIN} ${RED}${snell_conf}${PLAIN}"
    echo -e " ${BLUE}Snell配置信息：${PLAIN}"
    echo -e "   ${BLUE}协议: ${PLAIN} ${RED}snell${PLAIN}"
    echo -e "   ${BLUE}地址(IP): ${PLAIN} ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}端口(PORT)：${PLAIN} ${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}密钥(PSK)：${PLAIN} ${RED}${psk}${PLAIN}"
    echo -e "   ${BLUE}IPV6：${PLAIN} ${RED}${ipv6}${PLAIN}"
    echo -e "   ${BLUE}混淆(OBFS)：${PLAIN} ${RED}${obfs}${PLAIN}"
    echo -e "   ${BLUE}TCP记忆(TFO)：${PLAIN} ${RED}${tfo}${PLAIN}"
    echo -e "   ${BLUE}Snell版本：${PLAIN} ${RED}${ver}${PLAIN}"
}

Upgrade_snell() {
    if [[ ! -f /etc/snell/snell ]]; then
        colorEcho $RED "Snell 未安装，无法升级"
        return
    fi

    current_version=$(/etc/snell/snell --version 2>&1 | grep -oP 'snell-server version \K\S+')
    colorEcho $BLUE "当前安装的 Snell 版本：$current_version"

    selectversion
    if [[ "$VER" == "v$current_version" ]]; then
        colorEcho $YELLOW "您已经安装了最新版本，无需升级"
        return
    fi

    colorEcho $BLUE "开始升级到版本 $VER"

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

Change_snell(){
    Generate_conf
    Write_config
    systemctl restart snell
    colorEcho $BLUE " 修改配置成功"
    ShowInfo
}

menu() {
    clear
    echo "################################"
    echo -e "#      ${RED}Snell一键安装脚本${PLAIN}       #"
    echo "################################"
    echo " ----------------------"
    echo -e "  ${GREEN}1.${PLAIN}  安装Snell"
    echo -e "  ${GREEN}2.${PLAIN}  ${RED}卸载Snell${PLAIN}"
    echo " ----------------------"
    echo -e "  ${GREEN}3.${PLAIN}  启动Snell"
    echo -e "  ${GREEN}4.${PLAIN}  重启Snell"
    echo -e "  ${GREEN}5.${PLAIN}  停止Snell"
    echo " ----------------------"
    echo -e "  ${GREEN}6.${PLAIN}  查看Snell配置"
    echo -e "  ${GREEN}7.${PLAIN}  修改Snell配置"
    echo -e "  ${GREEN}8.${PLAIN}  升级Snell"
    echo " ----------------------"
    echo -e "  ${GREEN}0.${PLAIN}  退出"
    echo 
    echo -n " 当前状态："
    statusText
    echo 

    read -p " 请选择操作[0-8]：" answer
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
            colorEcho $BLUE " Snell已启动"
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
            Change_snell
            ;;
        8)
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
