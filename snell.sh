#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN='\033[0m'

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
    DOWNLOAD_LINK="https://dl.nssurge.com/snell/snell-server-v5.0.0-linux-amd64.zip"
    colorEcho $YELLOW "下载Snell: ${DOWNLOAD_LINK}"
    wget -O /tmp/snell/snell.zip ${DOWNLOAD_LINK}
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
# v4.1.1
EOF
}

Install_snell(){
    Install_dependency
    Generate_conf
    Download_snell
    Write_config
    Deploy_snell
    Install_stls
    colorEcho $BLUE "安装完成"
    ShowInfo
}

Install_stls() {
    Generate_stls
    Download_stls
    Deploy_stls
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
	if [[ -f "$stls_conf" ]]; then
		systemctl stop snell shadowtls
		systemctl disable snell shadowtls >/dev/null 2>&1
		rm -rf /etc/systemd/system/snell.service
		rm -rf /etc/systemd/system/shadowtls.service
		rm -rf /etc/snell
		systemctl daemon-reload
		colorEcho $BLUE " Snell已经卸载完毕"
	else
		systemctl stop snell
		systemctl disable snell >/dev/null 2>&1
		rm -rf /etc/systemd/system/snell.service
		rm -rf /etc/snell
		systemctl daemon-reload
		colorEcho $BLUE " Snell已经卸载完毕"
	fi
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
    echo -e "   ${BLUE}TCP记忆(TFO)：${PLAIN} ${RED}${tfo}${PLAIN}"
    echo -e "   ${BLUE}Snell版本(VER)：${PLAIN} ${RED}${ver}${PLAIN}"
}

outputSTLS() {
    echo -e "   ${BLUE}ShadowTls端口(PORT)：${PLAIN} ${RED}${sport}${PLAIN}"
    echo -e "   ${BLUE}ShadowTls密码(PASS)：${PLAIN} ${RED}${pass}${PLAIN}"
    echo -e "   ${BLUE}ShadowTls域名(DOMAIN)：${PLAIN} ${RED}${domain}${PLAIN}"
    echo -e "   ${BLUE}ShadowTls版本(VER)：${PLAIN} ${RED}v3${PLAIN}"
}

Change_snell(){
    tmp3=`grep '#' ${snell_conf} | awk -F '# ' '{print $2}'`
    Generate_conf
    if [[ -f "$stls_conf" ]]; then
	if [[ ${V6} = "true" ]]; then
		SV6="::0"
		SPORT=`grep listen ${stls_conf} | cut -d- -f7 | cut -d: -f2`
		PASS=`grep password ${stls_conf} | cut -d- -f13 | cut -d " " -f 2`
		DOMAIN=`grep password ${stls_conf} | cut -d- -f11 | cut -d " " -f 2`
	else
		SV6="0.0.0.0"
		SPORT=`grep listen ${stls_conf} | cut -d- -f7 | cut -d: -f4`
		PASS=`grep password ${stls_conf} | cut -d- -f13 | cut -d " " -f 2`
		DOMAIN=`grep password ${stls_conf} | cut -d- -f11 | cut -d " " -f 2`
	fi
	Deploy_stls
    fi
    vers=$tmp3
    Write_config
    systemctl restart snell
    colorEcho $BLUE " 修改配置成功"
    ShowInfo
}

Change_stls() {
    PORT=`grep listen ${snell_conf} | awk -F '=' '{print $2}' | cut -d: -f4`
    if [[ -f "$stls_conf" ]]; then
	V6=`grep ipv6 ${snell_conf} | awk -F '= ' '{print $2}'`
	Generate_stls
	Deploy_stls
	colorEcho $BLUE " 修改配置成功"
	ShowInfo
    else
	colorEcho $RED " 未安装ShadowTls"
    fi
}

Upgrade_snell() {
    colorEcho $BLUE "开始升级Snell..."
    
    # 停止Snell服务
    systemctl stop snell
    colorEcho $YELLOW "Snell服务已停止"

    # 备份旧版本
    mv /etc/snell/snell /etc/snell/snell.old
    colorEcho $YELLOW "旧版本已备份为 snell.old"

    # 下载新版本
    DOWNLOAD_LINK="https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-amd64.zip"
    colorEcho $YELLOW "下载新版Snell: ${DOWNLOAD_LINK}"
    wget -O /tmp/snell.zip ${DOWNLOAD_LINK}
    
    # 解压并安装新版本
    unzip -o /tmp/snell.zip -d /tmp/
    mv /tmp/snell-server /etc/snell/snell
    chmod +x /etc/snell/snell
    
    # 清理临时文件
    rm -f /tmp/snell.zip

    # 重启Snell服务
    systemctl start snell
    colorEcho $GREEN "Snell已升级并重新启动"

    # 验证新版本
    NEW_VERSION=$(/etc/snell/snell --version)
    colorEcho $BLUE "当前Snell版本: ${NEW_VERSION}"
}

checkSystem
menu() {
	clear
	echo "################################"
	echo -e "#      ${RED}Snell一键安装脚本${PLAIN}       #"
	echo "################################"
	echo " ----------------------"
	echo -e "  ${GREEN}1.${PLAIN}  安装Snell和ShadowTLS"
	echo -e "  ${GREEN}2.${PLAIN}  ${RED}卸载Snell和ShadowTLS${PLAIN}"
	echo -e "  ${GREEN}3.${PLAIN}  重启Snell和ShadowTLS"
	echo -e "  ${GREEN}4.${PLAIN}  查看配置"
	echo -e "  ${GREEN}5.${PLAIN}  升级Snell"
	echo -e "  ${GREEN}0.${PLAIN}  退出"
	echo ""
	echo -n " 当前状态："
	statusText
	echo 

	read -p " 请选择操作[0-5]：" answer
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
			Restart_stls
			;;
		4)
			ShowInfo
			;;
		5)
			Upgrade_snell
			;;
		*)
			colorEcho $RED " 请选择正确的操作！"
   			sleep 2s
			menu
			;;
	esac
}
menu
