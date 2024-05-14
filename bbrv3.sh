#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "脚本需要root运行." 1>&2
    exit 1
fi

# Function to display info messages in green
info() {
    echo -e "\e[92m$1\e[0m"
}

# Function to display error messages in red
fail() {
    echo -e "\e[91m$1\e[0m" 1>&2
}

# Function to get system information
sysinfo_() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        os=$NAME
        ver=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        os=$(lsb_release -si)
        ver=$(lsb_release -sr)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        os=$DISTRIB_ID
        ver=$DISTRIB_RELEASE
    elif [ -f /etc/debian_version ]; then
        os=Debian
        ver=$(cat /etc/debian_version)
    elif [ -f /etc/redhat-release ]; then
        os=Redhat
    else
        os=$(uname -s)
        ver=$(uname -r)
    fi

    # Get virtualization technology
    if [ "$(systemd-detect-virt)" != "none" ]; then
        virt_tech=$(systemd-detect-virt)
    fi

    # Get memory size
    mem_size=$(free -m | grep Mem | awk '{print $2}')

    # Get network interface
    nic=$(ip addr | grep 'state UP' | awk '{print $2}' | sed 's/.$//' | cut -d'@' -f1 | head -1)
}

# Function to update the system
update_() {
    if [[ $os =~ "Ubuntu" ]] || [[ $os =~ "Debian" ]]; then
        apt-get update -y && apt-get upgrade -y
    elif [[ $os =~ "CentOS" ]] || [[ $os =~ "Redhat" ]]; then
        yum update -y
    fi
}

# Function to install BBRv3
install_bbrv3_() {
    if [ "$(uname -m)" == "x86_64" ]; then
        wget https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/BBR/BBRv3/x86_64/linux-headers-6.4.0+-amd64.deb -O /root/linux-headers-6.4.0+-amd64.deb
        if [ ! -f /root/linux-headers-6.4.0+-amd64.deb ]; then
            fail "BBRv3 download failed"
            return 1
        fi
        wget https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/BBR/BBRv3/x86_64/linux-image-6.4.0+-amd64.deb -O /root/linux-image-6.4.0+-amd64.deb
        if [ ! -f /root/linux-image-6.4.0+-amd64.deb ]; then
            fail "BBRv3 download failed"
            rm /root/linux-headers-6.4.0+-amd64.deb
            return 1
        fi
        wget https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/BBR/BBRv3/x86_64/linux-libc-dev-6.4.0-amd64.deb -O /root/linux-libc-dev-6.4.0-amd64.deb
        if [ ! -f /root/linux-libc-dev-6.4.0-amd64.deb ]; then
            fail "BBRv3 download failed"
            rm /root/linux-headers-6.4.0+-amd64.deb /root/linux-image-6.4.0+-amd64.deb
            return 1
        fi
        apt install -y /root/linux-headers-6.4.0+-amd64.deb /root/linux-image-6.4.0+-amd64.deb /root/linux-libc-dev-6.4.0-amd64.deb
        # Clean up
        rm /root/linux-headers-6.4.0+-amd64.deb /root/linux-image-6.4.0+-amd64.deb /root/linux-libc-dev-6.4.0-amd64.deb
    elif [ "$(uname -m)" == "aarch64" ]; then
        wget https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/BBR/BBRv3/ARM64/linux-headers-6.4.0+-arm64.deb -O /root/linux-headers-6.4.0+-arm64.deb
        if [ ! -f /root/linux-headers-6.4.0+-arm64.deb ]; then
            fail "BBRv3 download failed"
            return 1
        fi
        wget https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/BBR/BBRv3/ARM64/linux-image-6.4.0+-arm64.deb -O /root/linux-image-6.4.0+-arm64.deb
        if [ ! -f /root/linux-image-6.4.0+-arm64.deb ]; then
            fail "BBRv3 download failed"
            rm /root/linux-headers-6.4.0+-arm64.deb
            return 1
        fi
        wget https://raw.githubusercontent.com/jerry048/Seedbox-Components/main/BBR/BBRv3/ARM64/linux-libc-dev-6.4.0-arm64.deb -O /root/linux-libc-dev-6.4.0-arm64.deb
        if [ ! -f /root/linux-libc-dev-6.4.0-arm64.deb ]; then
            fail "BBRv3 download failed"
            rm /root/linux-headers-6.4.0+-arm64.deb /root/linux-image-6.4.0+-arm64.deb
            return 1
        fi
        apt install -y /root/linux-headers-6.4.0+-arm64.deb /root/linux-image-6.4.0+-arm64.deb /root/linux-libc-dev-6.4.0-arm64.deb
        # Clean up
        rm /root/linux-headers-6.4.0+-arm64.deb /root/linux-image-6.4.0+-arm64.deb /root/linux-libc-dev-6.4.0-arm64.deb
    else
        fail "$(uname -m) is not supported"
    fi
    return 0
}

# Main script execution
sysinfo_
update_
info "安装BBRv3"
if [[ "$virt_tech" =~ "LXC" ]] || [[ "$virt_tech" =~ "lxc" ]]; then
    fail "不支持LXC"
    exit 1
fi
if [[ $os =~ "Ubuntu" ]] || [[ $os =~ "Debian" ]]; then
    install_bbrv3_
    if [ $? -eq 0 ]; then
        info "重启系统以启用BBRv3"
    else
        fail "BBRv3安装失败"
    fi
else
    fail "不支持此系统"
fi