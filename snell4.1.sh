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

# 在 menu 函数中添加升级选项
menu() {
    # ... (之前的菜单选项) ...
    echo -e "  ${GREEN}9.${PLAIN}  升级 Snell"
    # ... (之后的菜单选项) ...

    read -p " 请选择操作[0-12]：" answer
    case $answer in
        # ... (之前的 case 语句) ...
        9)
            Upgrade_snell
            ;;
        # ... (之后的 case 语句) ...
    esac
}
