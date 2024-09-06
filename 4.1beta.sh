#!/bin/bash

# Function to check if Snell is installed
check_snell() {
    if command -v snell-server &> /dev/null; then
        echo "Snell is installed. Version: $(snell-server -v)"
    else
        echo "Snell is not installed."
    fi
}

# Function to check if ShadowTLS is installed
check_shadowtls() {
    if command -v shadow-tls &> /dev/null; then
        echo "ShadowTLS is installed. Version: $(shadow-tls -v)"
    else
        echo "ShadowTLS is not installed."
    fi
}

# Function to install Snell and ShadowTLS
install_both() {
    echo "Installing Snell and ShadowTLS..."
    # Snell Installation
    sudo apt update && sudo apt install -y wget unzip vim
    wget https://dl.nssurge.com/snell/snell-server-v4.1-linux-amd64.zip
    sudo unzip snell-server-v4.1-linux-amd64.zip -d /usr/local/bin
    chmod +x /usr/local/bin/snell-server
    read -p "Enter the PSK for Snell (press enter to generate a random one): " snell_psk
    snell_psk=${snell_psk:-$(generate_random_string)}
    sudo mkdir -p /etc/snell
    echo "[snell-server]
listen = 0.0.0.0:11029
psk = $snell_psk
ipv6 = false" | sudo tee /etc/snell/snell-server.conf
    echo "[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
LimitNOFILE=32768
ExecStart=/usr/local/bin/snell-server -c /etc/snell/snell-server.conf
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target" | sudo tee /lib/systemd/system/snell.service
    sudo systemctl daemon-reload
    sudo systemctl enable snell
    sudo systemctl start snell

    # ShadowTLS Installation
    wget https://github.com/ihciah/shadow-tls/releases/download/v0.2.25/shadow-tls-x86_64-unknown-linux-musl -O /usr/local/bin/shadow-tls
    chmod +x /usr/local/bin/shadow-tls
    read -p "Enter the port for Shadow-Tls (press enter to generate a random one): " shadow_tls_port
    shadow_tls_port=${shadow_tls_port:-$(generate_random_port)}
    read -p "Enter the password for Shadow-Tls (press enter to generate a random one): " shadow_tls_password
    shadow_tls_password=${shadow_tls_password:-$(generate_random_string)}
    echo "[Unit]
Description=Shadow-TLS Server Service
After=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/shadow-tls --fastopen --v3 server --listen ::0:$shadow_tls_port --server 127.0.0.1:11029 --tls gateway.icloud.com --password $shadow_tls_password
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=shadow-tls

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/shadow-tls.service
    sudo systemctl enable shadow-tls.service
    sudo systemctl daemon-reload
    sudo systemctl start shadow-tls.service

    echo -e "\033[1;32mInstallation completed.\033[0m"
}

# Function to upgrade Snell
upgrade_snell() {
    echo "Upgrading Snell..."
    sudo systemctl stop snell
    wget https://dl.nssurge.com/snell/snell-server-v4.1-linux-amd64.zip
    sudo unzip -o snell-server-v4.1-linux-amd64.zip -d /usr/local/bin
    chmod +x /usr/local/bin/snell-server
    sudo systemctl start snell
    echo "Snell has been upgraded to version 4.1."
}

# Function to uninstall Snell and ShadowTLS
uninstall_both() {
    echo "Uninstalling Snell and ShadowTLS..."
    sudo systemctl stop snell shadow-tls
    sudo systemctl disable snell shadow-tls
    sudo rm /usr/local/bin/snell-server /usr/local/bin/shadow-tls
    sudo rm -rf /etc/snell /etc/systemd/system/shadow-tls.service /lib/systemd/system/snell.service
    sudo systemctl daemon-reload
    echo "Snell and ShadowTLS have been uninstalled."
}

# Main script logic
echo "Checking for existing installations..."
check_snell
check_shadowtls

echo "Choose an option:"
echo "1. Install Snell and ShadowTLS"
echo "2. Upgrade Snell to version 4.1"
echo "3. Uninstall Snell and ShadowTLS"
read -p "Enter the number corresponding to your choice: " choice

case $choice in
    1)
        install_both
        ;;
    2)
        upgrade_snell
        ;;
    3)
        uninstall_both
        ;;
    *)
        echo "Invalid choice."
        ;;
esac
