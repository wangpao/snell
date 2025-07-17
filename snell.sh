#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

# Snell 最新版本信息 (方便统一管理和更新)
LATEST_SNELL_VER="v5.0.0"
LATEST_DOWNLOAD_LINK="https://dl.nssurge.com/snell/snell-server-${LATEST_SNELL_VER}-linux-amd64.zip"

IP4=`curl -sL -4 ip.sb`
IP6=`curl -sL -6 ip.sb`
CPU=`uname -m`
snell_conf="/etc/snell/snell-server.conf"
stls_conf="/etc/systemd/system/shadowtls.service"

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

checkSystem() {
    if [[ $(lsb_release -rs) < "22.04" ]]; then
        colorEcho $RED "仅支持Ubuntu 22.04及以上版本"
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
    tmp=`grep listen ${snell_conf} | awk -F '=' '{print $2}' | cut -d: -f2`
    if [[ -z ${tmp} ]]; then
        tmp=`grep listen ${snell_conf} | awk -F '=' '{print $2}' | cut -d: -f4`
    fi
    res=`ss -nutlp| grep ${tmp} | grep -i snell`
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
    V6=`grep ipv6 ${snell_conf} | awk -F '= ' '{print $2}'`
    if [[ $V6 = "true" ]]; then
	tmp2=`grep listen ${stls_conf} | cut -d- -f7 | cut -d: -f4`
    else
	tmp2=`grep listen ${stls_conf} | cut -d- -f7 | cut -d: -f2`
    fi
    res2=`ss -nutlp| grep ${tmp2} | grep -i shadowtls`
    if [[ -z $res2 ]]; then
	echo 2
    else
	echo 3
	return
    fi
}

statusText() {
    res=`status`
    res2=`status_stls`
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
        20)
            echo -e ${BLUE}Snell:${PLAIN} ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}
            echo -e "       ${BLUE}ShadowTls:${PLAIN} ${RED}未安装${PLAIN}"
            ;;
        21)
            echo -e ${BLUE}Snell:${PLAIN} ${GREEN}已安装${PLAIN} ${RED}未运行${PLAIN}
            echo -e "       ${BLUE}ShadowTls:${PLAIN} ${RED}未安装${PLAIN}"
            ;;
        30)
            echo -e ${BLUE}Snell:${PLAIN} ${GREEN}已安装${PLAIN} ${GREEN}正在运行${PLAIN}
            echo -e "       ${BLUE}ShadowTls:${PLAIN} ${RED}未安装${PLAIN}"
            ;;
        31)
            echo -e ${BLUE}Snell:${PLAIN} ${GREEN}已安装${PLAIN} ${GREEN}正在运行${PLAIN}
            echo -e "       ${BLUE}ShadowTls:${PLAIN} ${RED}未安装${PLAIN}"
            ;;
        *)
            echo -e ${BLUE}Snell:${PLAIN} ${RED}未安装${PLAIN}
            echo -e "       ${BLUE}ShadowTls:${PLAIN} ${RED}未安装${PLAIN}"
            ;;
    esac
}

Install_dependency(){
    apt update
    apt install unzip wget -y
}

Download_snell(){
    rm -rf /etc/snell /tmp/snell
    mkdir -p /etc/snell /tmp/snell
    colorEcho $YELLOW "下载Snell: ${LATEST_DOWNLOAD_LINK}"
    wget -O /tmp/snell/snell.zip ${LATEST_DOWNLOAD_LINK}
    if [[ $? -ne 0 ]]; then
        colorEcho $RED "下载 Snell 失败, 请检查网络或链接有效性。"
        exit 1
    fi
    unzip /tmp/snell/snell.zip -d /tmp/snell/
    mv /tmp/snell/snell-server /etc/snell/snell
    chmod +x /etc/snell/snell
}

Download_stls() {
    rm -rf /etc/snell/shadowtls
    TAG_URL="https://api.github.com/repos/ihciah/shadow-tls/releases/latest"
    DOWN_VER=`curl -s "${TAG_URL}" --connect-timeout 10| grep -Eo '\"tag_name\"(.*?)\",' | cut -d\" -f4`
    DOWNLOAD_LINK="https://github.com/ihciah/shadow-tls/releases/download/${DOWN_VER}/shadow-tls-x86_64-unknown-linux-musl"
    colorEcho $YELLOW "下载ShadowTLS: ${DOWNLOAD_LINK}"
    curl -L -H "Cache-Control: no-cache" -o /etc/snell/shadowtls ${DOWNLOAD_LINK}
    if [[ $? -ne 0 ]]; then
        colorEcho $RED "下载 ShadowTls 失败, 请检查网络或链接有效性。"
        exit 1
    fi
    chmod +x /etc/snell/shadowtls
}

Generate_conf(){
    Set_port
    Set_psk
    show_psk
}

Generate_stls() {
    Set_sport
    Set_domain
    show_domain
    Set_pass
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

Set_port(){
    read -p $'请输入 Snell 端口 [1-65535]\n(默认: 6666，回车): ' PORT
    [[ -z "${PORT}" ]] && PORT="6666"
    echo $((${PORT}+0)) &>/dev/null
    if [[ $? -eq 0 ]]; then
	if [[ ${PORT} -ge 1 ]] && [[ ${PORT} -le 65535 ]]; then
		colorEcho $BLUE "端口: ${PORT}"
		echo ""
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
}

show_psk() {
    colorEcho $BLUE "PSK: ${PSK}"
    echo ""
}

Set_sport() {
    read -p $'请输入 ShadowTLS 端口 [1-65535]\n(默认: 9999，回车): ' SPORT
    [[ -z "${SPORT}" ]] && SPORT="9999"
    echo $((${SPORT}+0)) &>/dev/null
    if [[ $? -eq 0 ]]; then
	if [[ ${SPORT} -ge 1 ]] && [[ ${SPORT} -le 65535 ]]; then
		colorEcho $BLUE "端口: ${SPORT}"
		echo ""
	else
		colorEcho $RED "输入错误, 请输入正确的端口。"
		Set_sport
	fi
    else
	colorEcho $RED "输入错误, 请输入数字。"
	Set_sport
    fi
}

Set_domain() {
    DOMAIN="gateway.icloud.com"
    colorEcho $BLUE "域名：${DOMAIN}"
    echo ""
}

show_domain() {
	colorEcho $BLUE "域名：${DOMAIN}"
	echo ""
}

Set_pass() {
    read -p $'请设置ShadowTLS的密码\n(默认随机生成, 回车): ' PASS
    [[ -z "$PASS" ]] && PASS=`cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1`
    colorEcho $BLUE " 密码：$PASS"
    echo ""
}

Write_config(){
    cat > ${snell_conf}<<-EOF
[snell-server]
listen = 0.0.0.0:${PORT}
psk = ${PSK}
ipv6 = false
obfs = off
tfo = true
# ${LATEST_SNELL_VER}
EOF
}

Install_snell(){
    Install_dependency
    Generate_conf
    Download_snell
    Write_config
    Deploy_snell
    Install_stls
    colorEcho $GREEN "安装完成"
    ShowInfo
}

Install_stls() {
    Generate_stls
    Download_stls
    Deploy_stls
}

Restart_all(){
    systemctl restart snell
    colorEcho $BLUE "Snell已重启"
    if [[ -f "$stls_conf" ]]; then
        systemctl restart shadowtls
        colorEcho $BLUE "ShadowTls已重启"
    fi
}

Stop_snell(){
    systemctl stop snell
    colorEcho $BLUE " Snell已停止"
}

Uninstall_all(){
    read -p $' 是否卸载Snell和ShadowTls？[y/n]\n (默认n, 回车): ' answer
    if [[ "${answer}" = "y" ]]; then
        systemctl stop snell >/dev/null 2>&1
        systemctl disable snell >/dev/null 2>&1
        rm -f /etc/systemd/system/snell.service

	if [[ -f "$stls_conf" ]]; then
		systemctl stop shadowtls >/dev/null 2>&1
		systemctl disable shadowtls >/dev/null 2>&1
		rm -f /etc/systemd/system/shadowtls.service
	fi
 
	rm -rf /etc/snell
	systemctl daemon-reload
	colorEcho $GREEN "Snell 及 ShadowTls 已经卸载完毕"
    else
	colorEcho $YELLOW "取消卸载"
    fi
}

ShowInfo() {
    if [[ ! -f $snell_conf ]]; then
	colorEcho $RED "Snell未安装"
 	exit 1
    fi
    echo ""
    echo -e " ${BLUE}Snell配置文件: ${PLAIN} ${RED}${snell_conf}${PLAIN}"
    colorEcho $BLUE " Snell配置信息："
    GetConfig
    outputSnell
    if [[ -f $stls_conf ]]; then
	GetConfig_stls
	outputSTLS
	echo ""
	echo -e " ${BLUE}若要使用ShadowTls, 请将${PLAIN}${RED} 端口 ${PLAIN}${BLUE}替换为${PLAIN}${RED} ${sport} ${PLAIN}"
    fi
}

GetConfig() {
    port=`grep listen ${snell_conf} | awk -F '=' '{print $2}' | cut -d: -f2`
    if [[ -z "${port}" ]]; then
	port=`grep listen ${snell_conf} | awk -F '=' '{print $2}' | cut -d: -f4`
    fi
    psk=`grep psk ${snell_conf} | awk -F '= ' '{print $2}'`
    ipv6=`grep ipv6 ${snell_conf} | awk -F '= ' '{print $2}'`
    if [[ $ipv6 == "true" ]]; then
	IP=${IP6}
    else
	IP=${IP4}
    fi
    obfs=`grep obfs ${snell_conf} | awk -F '= ' '{print $2}'`
    tfo=`grep tfo ${snell_conf} | awk -F '= ' '{print $2}'`
    ver=`grep '#' ${snell_conf} | awk -F '# ' '{print $2}'`
}

GetConfig_stls() {
    V6=`grep ipv6 ${snell_conf} | awk -F '= ' '{print $2}'`
    if [[ $V6 = "true" ]]; then
	sport=`grep listen ${stls_conf} | cut -d- -f7 | cut -d: -f4`
    else
	sport=`grep listen ${stls_conf} | cut -d- -f7 | cut -d: -f2`
    fi
    pass=`grep password ${stls_conf} | cut -d- -f13 | cut -d " " -f 2`
    domain=`grep password ${stls_conf} | cut -d- -f11 | cut -d " " -f 2`
}

outputSnell() {
    echo -e "   ${BLUE}协议: ${PLAIN} ${RED}snell${PLAIN}"
    echo -e "   ${BLUE}地址(IP): ${PLAIN} ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}Snell端口(PORT)：${PLAIN} ${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}Snell密钥(PSK)：${PLAIN} ${RED}${psk}${PLAIN}"
    echo -e "   ${BLUE}IPV6：${PLAIN} ${RED}${ipv6}${PLAIN}"
    echo -e "   ${BLUE}混淆(OBFS)：${PLAIN} ${RED}${obfs}${PLAIN}"
    echo -e "   ${BLUE}TCP加速(TFO)：${PLAIN} ${RED}${tfo}${PLAIN}"
    echo -e "   ${BLUE}Snell版本(VER)：${PLAIN} ${RED}${ver}${PLAIN}"
}

outputSTLS() {
    echo -e "   ${BLUE}ShadowTls端口(PORT)：${PLAIN} ${RED}${sport}${PLAIN}"
    echo -e "   ${BLUE}ShadowTls密码(PASS)：${PLAIN} ${RED}${pass}${PLAIN}"
    echo -e "   ${BLUE}ShadowTls域名(DOMAIN)：${PLAIN} ${RED}${domain}${PLAIN}"
    echo -e "   ${BLUE}ShadowTls版本(VER)：${PLAIN} ${RED}v3${PLAIN}"
}

Change_snell(){
    colorEcho $BLUE "开始修改 Snell 配置..."
    Generate_conf # 获取新的 PORT 和 PSK
    
    # 如果ShadowTls已安装，需要更新其启动参数中的Snell端口
    if [[ -f "$stls_conf" ]]; then
        colorEcho $YELLOW "检测到ShadowTls，将同步更新其配置..."
        GetConfig_stls # 获取当前的 sport, pass, domain
        SPORT=${sport} # 赋值给大写变量以供Deploy_stls使用
        PASS=${pass}
        DOMAIN=${domain}
        Deploy_stls # 使用新的PORT和旧的STLS参数重新生成服务文件
    fi

    Write_config # 写入新的Snell配置文件
    systemctl restart snell
    colorEcho $GREEN "修改配置成功！"
    ShowInfo
}

Change_stls() {
    if [[ ! -f "$stls_conf" ]]; then
        colorEcho $RED "未安装ShadowTls，无法修改。"
        return
    fi
    colorEcho $BLUE "开始修改 ShadowTls 配置..."
    GetConfig # 获取当前的 Snell port
    PORT=${port} # 赋值给大写变量以供Deploy_stls使用
    Generate_stls # 获取新的 SPORT, DOMAIN, PASS
    Deploy_stls # 部署新的ShadowTls服务
    colorEcho $GREEN "修改配置成功！"
    ShowInfo
}

Upgrade_snell() {
    if [[ ! -f "$snell_conf" ]]; then
        colorEcho $RED "Snell未安装，无法升级。"
        return
    fi
    
    installed_ver=$(grep '#' ${snell_conf} | awk -F '# ' '{print $2}')
    if [[ -z "$installed_ver" ]]; then
        colorEcho $YELLOW "无法检测到已安装版本，将尝试直接升级。"
    elif [[ "$installed_ver" == "$LATEST_SNELL_VER" ]]; then
        colorEcho $GREEN "恭喜！当前已是最新版本 ($LATEST_SNELL_VER)，无需升级。"
        return
    fi

    colorEcho $YELLOW "发现新版本！"
    colorEcho $BLUE "当前版本: ${installed_ver:-未知}"
    colorEcho $BLUE "最新版本: ${LATEST_SNELL_VER}"
    read -p "是否要升级? [y/n] (默认y, 回车): " answer
    [[ -z "$answer" ]] && answer="y"
    if [[ "$answer" != "y" ]]; then
        colorEcho $YELLOW "已取消升级。"
        return
    fi

    colorEcho $BLUE "开始升级Snell..."
    systemctl stop snell
    
    # 下载新版本
    colorEcho $YELLOW "下载新版Snell: ${LATEST_DOWNLOAD_LINK}"
    wget -O /tmp/snell.zip ${LATEST_DOWNLOAD_LINK}
    if [[ $? -ne 0 ]]; then
        colorEcho $RED "下载新版本失败，升级已中止。"
        systemctl start snell
        return
    fi
    
    unzip -o /tmp/snell.zip -d /tmp/
    mv /tmp/snell-server /etc/snell/snell
    chmod +x /etc/snell/snell
    rm -f /tmp/snell.zip
    
    # 更新配置文件中的版本号
    sed -i "s/^# .*/# ${LATEST_SNELL_VER}/" "${snell_conf}"

    systemctl start snell
    colorEcho $GREEN "Snell已成功升级到 ${LATEST_SNELL_VER} 并重新启动！"
}

changeMenu() {
    clear
    echo "################################"
    echo -e "#      ${YELLOW}修改配置子菜单${PLAIN}          #"
    echo "################################"
    echo ""
    echo -e "  ${GREEN}1.${PLAIN}  修改 Snell 配置 (端口/密钥)"
    echo -e "  ${GREEN}2.${PLAIN}  修改 ShadowTls 配置 (端口/密码)"
    echo -e "  ${GREEN}0.${PLAIN}  返回主菜单"
    echo ""
    read -p " 请选择操作[0-2]：" answer
    case $answer in
        0)
            menu
            ;;
        1)
            Change_snell
            ;;
        2)
            Change_stls
            ;;
        *)
            colorEcho $RED " 请选择正确的操作！"
            sleep 2s
            changeMenu
            ;;
    esac
}

menu() {
	clear
	echo "################################"
	echo -e "#      ${RED}Snell一键安装脚本${PLAIN}       #"
	echo "################################"
	echo " ----------------------"
	echo -e "  ${GREEN}1.${PLAIN}  安装 Snell 和 ShadowTLS"
	echo -e "  ${GREEN}2.${PLAIN}  ${RED}卸载 Snell 和 ShadowTLS${PLAIN}"
	echo -e "  ${GREEN}3.${PLAIN}  重启 Snell 和 ShadowTLS"
	echo -e "  ${GREEN}4.${PLAIN}  查看配置"
    echo -e "  ${GREEN}5.${PLAIN}  修改配置"
	echo -e "  ${GREEN}6.${PLAIN}  升级 Snell"
	echo -e "  ${GREEN}0.${PLAIN}  退出"
	echo ""
	echo -n " 当前状态："
	statusText
	echo 

	read -p " 请选择操作[0-6]：" answer
	case $answer in
		0)
			exit 0
			;;
		1)
			Install_snell
			;;
		2)
			Uninstall_all
			;;
		3)
			Restart_all
			;;
		4)
			ShowInfo
			;;
        5)
            changeMenu
            ;;
		6)
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
