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

archAffix(){
    if [[ "$CPU" = "x86_64" ]] || [[ "$CPU" = "amd64" ]]; then
        CPU="amd64"
        ARCH="x86_64"
    elif [[ "$CPU" = "armv8" ]] || [[ "$CPU" = "aarch64" ]]; then
        CPU="arm64"
        ARCH="aarch64"
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
        return
    fi
}

status_stls() {
    if [[ ! -f /etc/snell/shadowtls ]]; then
        echo 0
        return
    fi
    if [[ ! -f $stls_conf ]]; then
        echo 1
        return
    fi
    tmp2=$(grep listen ${stls_conf} | cut -d- -f7 | cut -d: -f2)
    res2=$(ss -nutlp| grep ${tmp2} | grep -i shadowtls)
    if [[ -z $res2 ]]; then
        echo 2
    else
        echo 3
        return
    fi
}

statusText() {
    res=$(status)
    res2=$(status_stls)
    case ${res}${res2} in
        22)
            echo -e ${BLUE}Snell:${PLAIN} ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}
            echo -e "       ${BLUE}ShadowTls:${PLAIN} ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}"
            ;;
        23)
            echo -e ${BLUE}Snell:${PLAIN} ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}
            echo -e "       ${BLUE}ShadowTls:${PLAIN} ${GREEN}已安装${PLAIN} ${GREEN}正在运行${PLAIN}"
            ;;
        32)
            echo -e ${BLUE}Snell:${PLAIN} ${GREEN}已安装${PLAIN} ${GREEN}正在运行${PLAIN}
            echo -e "       ${BLUE}ShadowTls:${PLAIN} ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}"
            ;;
        33)
            echo -e ${BLUE}Snell:${PLAIN} ${GREEN}已安装${PLAIN} ${GREEN}正在运行${PLAIN}
            echo -e "       ${BLUE}ShadowTls:${PLAIN} ${GREEN}已安装${PLAIN} ${GREEN}正在运行${PLAIN}"
            ;;
        *)
            echo -e ${BLUE}Snell:${PLAIN} ${RED}未安装${PLAIN}
            echo -e "       ${BLUE}ShadowTls:${PLAIN} ${RED}未安装${PLAIN}"
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

Generate_conf(){
    PORT="6666"
    PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 16)
    colorEcho $BLUE "端口: ${PORT}"
    colorEcho $BLUE "PSK: ${PSK}"
}

Generate_stls() {
    SPORT="9999"
    DOMAIN="gateway.icloud.com"
    PASS=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    colorEcho $BLUE "ShadowTLS端口: ${SPORT}"
    colorEcho $BLUE "ShadowTLS域名: ${DOMAIN}"
    colorEcho $BLUE "ShadowTLS密码: ${PASS}"
}

Download_snell(){
    rm -rf /etc/snell /tmp/snell
    mkdir -p /etc/snell /tmp/snell
    archAffix
    DOWNLOAD_LINK="https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-${CPU}.zip"
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
    DOWN_VER=$(curl -s "${TAG_URL}" --connect-timeout 10| grep -Eo '\"tag_name\"(.*?)\",' | cut -d\" -f4)
    DOWNLOAD_LINK="https://github.com/ihciah/shadow-tls/releases/download/${DOWN_VER}/shadow-tls-${ARCH}-unknown-linux-musl"
    colorEcho $YELLOW "下载ShadowTLS: ${DOWNLOAD_LINK}"
    curl -L -H "Cache-Control: no-cache" -o /etc/snell/shadowtls ${DOWNLOAD_LINK}
    chmod +x /etc/snell/shadowtls
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

Deploy_stls() {
    cd /etc/systemd/system
    cat > shadowtls.service<<-EOF
[Unit]
Description=Shadow-TLS Server Service
Documentation=man:sstls-server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/etc/snell/shadowtls --fastopen --v3 server --listen 0.0.0.0:$SPORT --server 127.0.0.1:$PORT --tls $DOMAIN --password $PASS
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=shadow-tls
Environment=MONOIO_FORCE_LEGACY_DRIVER=1

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable shadowtls
    systemctl restart shadowtls
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
    Generate_stls
    Download_snell
    Write_config
    Deploy_snell
    Download_stls
    Deploy_stls
    colorEcho $BLUE "安装完成"
    ShowInfo
}

Restart_snell(){
    systemctl restart snell
    colorEcho $BLUE " Snell已启动"
}

Restart_stls(){
    systemctl restart shadowtls
    colorEcho $BLUE " ShadowTls已重启"
}

Stop_snell(){
    systemctl stop snell
    colorEcho $BLUE " Snell已停止"
}

Uninstall_snell(){
    read -p $' 是否卸载Snell？[y/n]\n (默认n, 回车): ' answer
    if [[ "${answer}" = "y" ]]; then
        systemctl stop snell shadowtls
        systemctl disable snell shadowtls >/dev/null 2>&1
        rm -rf /etc/systemd/system/snell.service
        rm -rf /etc/systemd/system/shadowtls.service
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
    echo ""
    echo -e " ${BLUE}Snell配置文件: ${PLAIN} ${RED}${snell_conf}${PLAIN}"
    colorEcho $BLUE " Snell配置信息："
    GetConfig
    outputSnell
    GetConfig_stls
    outputSTLS
    echo ""
    echo -e " ${BLUE}若要使用ShadowTls, 请将${PLAIN}${RED} 端口 ${PLAIN}${BLUE}替换为${PLAIN}${RED} ${SPORT} ${PLAIN}"
}

GetConfig() {
    port=$(grep listen ${snell_conf} | awk -F '=' '{print $2}' | cut -d: -f2)
    psk=$(grep psk ${snell_conf} | awk -F '= ' '{print $2}')
    ver=$(grep version ${snell_conf} | awk -F '= ' '{print $2}')
}

GetConfig_stls() {
    sport=$(grep listen ${stls_conf} | cut -d: -f2 | cut -d' ' -f1)
    pass=$(grep password ${stls_conf} | awk -F '--password ' '{print $2}')
    domain=$(grep tls ${stls_conf} | awk -F '--tls ' '{print $2}' | cut -d' ' -f1)
}

outputSnell() {
    echo -e "   ${BLUE}协议: ${PLAIN} ${RED}snell${PLAIN}"
    echo -e "   ${BLUE}地址(IP): ${PLAIN} ${RED}${IP4}${PLAIN}"
    echo -e "   ${BLUE}Snell端口(PORT)：${PLAIN} ${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}Snell密钥(PSK)：${PLAIN} ${RED}${psk}${PLAIN}"
    echo -e "   ${BLUE}IPV6：${PLAIN} ${RED}false${PLAIN}"
    echo -e "   ${BLUE}混淆(OBFS)：${PLAIN} ${RED}off${PLAIN}"
    echo -e "   ${BLUE}TCP记忆(TFO)：${PLAIN} ${RED}true${PLAIN}"
    echo -e "   ${BLUE}Snell版本(VER)：${PLAIN} ${RED}v${ver}${PLAIN}"
}

outputSTLS() {
    echo -e "   ${BLUE}ShadowTls端口(PORT)：${PLAIN} ${RED}${sport}${PLAIN}"
    echo -e "   ${BLUE}ShadowTls密码(PASS)：${PLAIN} ${RED}${pass}${PLAIN}"
    echo -e "   ${BLUE}ShadowTls域名(DOMAIN)：${PLAIN} ${RED}${domain}${PLAIN}"
    echo -e "   ${BLUE}ShadowTls版本(VER)：${PLAIN} ${RED}v3${PLAIN}"
}

Change_snell(){
    Generate_conf
    Write_config
    systemctl restart snell
    colorEcho $BLUE " 修改配置成功"
    ShowInfo
}

Change_stls() {
    Generate_stls
    Deploy_stls
    colorEcho $BLUE " 修改配置成功"
    ShowInfo
}

Check_Update() {
    current_ver=$(grep version ${snell_conf} 2>/dev/null | awk -F '= ' '{print $2}')
    if [[ -z "$current_ver" ]]; then
        colorEcho $YELLOW " 未检测到已安装的Snell版本，将执行全新安装。"
        Install_snell
        return
    fi
    
    if [[ "$current_ver" != "4" ]];
        if [[ "$current_ver" != "4" ]]; then
        colorEcho $YELLOW " 检测到旧版本Snell(v${current_ver}),是否升级到v4.1? [y/n]"
        read -p " (默认: y):" answer
        if [[ "${answer}" != "n" ]]; then
            Download_snell
            Write_config
            Restart_snell
            colorEcho $BLUE " Snell已升级到v4.1"
        else
            colorEcho $BLUE " 取消升级"
        fi
    else
        colorEcho $BLUE " 当前已是最新版本(v4.1),无需升级"
    fi


checkSystem
menu() {
    clear
    echo "################################"
    echo -e "#      ${RED}Snell一键安装脚本${PLAIN}       #"
    echo "################################"
    echo " ----------------------"
    echo -e "  ${GREEN}1.${PLAIN}  安装Snell"
    echo -e "  ${GREEN}2.${PLAIN}  ${RED}卸载Snell${PLAIN}"
    echo " ----------------------"
    echo -e "  ${GREEN}3.${PLAIN}  重启Snell"
    echo -e "  ${GREEN}4.${PLAIN}  重启ShadowTls"
    echo -e "  ${GREEN}5.${PLAIN}  停止Snell"
    echo " ----------------------"
    echo -e "  ${GREEN}6.${PLAIN}  查看Snell配置"
    echo -e "  ${GREEN}7.${PLAIN}  修改Snell配置"
    echo -e "  ${GREEN}8.${PLAIN}  修改ShadowTLS配置"
    echo -e "  ${GREEN}9.${PLAIN}  检查并升级Snell"
    echo " ----------------------"
    echo -e "  ${GREEN}0.${PLAIN}  退出"
    echo ""
    echo -n " 当前状态："
    statusText
    echo 

    read -p " 请选择操作[0-9]：" answer
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
            Restart_snell
            ;;
        4)
            Restart_stls
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
            Change_stls
            ;;
        9)
            Check_Update
            ;;
        *)
            colorEcho $RED " 请选择正确的操作！"
            sleep 2s
            menu
            ;;
    esac
}
menu
