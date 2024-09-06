#!/bin/bash

# Function to generate a random string
generate_random_string() {
    tr -dc A-Za-z0-9 </dev/urandom | head -c 20
}

# Function to generate a random port number
generate_random_port() {
    shuf -i 1024-49151 -n 1
}

# Phase 1: Install Snell

# Update and install necessary packages
sudo apt update && sudo apt install -y wget unzip vim

# Download Snell Server
wget https://dl.nssurge.com/snell/snell-server-v4.1-linux-amd64.zip

# Unzip Snell Server to the specified directory
sudo unzip snell-server-v4.1-linux-amd64.zip -d /usr/local/bin

# Grant execution permissions
chmod +x /usr/local/bin/snell-server

# Prompt the user to enter a PSK for Snell
read -p "Enter the PSK for Snell (press enter to generate a random one): " snell_psk
snell_psk=${snell_psk:-$(generate_random_string)}

# Create configuration directory and file with the user's PSK
sudo mkdir -p /etc/snell
echo "[snell-server]
listen = 0.0.0.0:11029
psk = $snell_psk
ipv6 = false" | sudo tee /etc/snell/snell-server.conf

# Create and configure systemd service file for Snell
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

# Reload systemd, enable and start Snell
sudo systemctl daemon-reload
sudo systemctl enable snell
sudo systemctl start snell

# Phase 2: Install Shadow-Tls

# Download Shadow-Tls
wget https://github.com/ihciah/shadow-tls/releases/download/v0.2.25/shadow-tls-x86_64-unknown-linux-musl -O /usr/local/bin/shadow-tls

# Grant execution permissions
chmod +x /usr/local/bin/shadow-tls

# Prompt the user to enter a port for Shadow-Tls
read -p "Enter the port for Shadow-Tls (press enter to generate a random one): " shadow_tls_port
shadow_tls_port=${shadow_tls_port:-$(generate_random_port)}

# Prompt the user to enter a password for Shadow-Tls
read -p "Enter the password for Shadow-Tls (press enter to generate a random one): " shadow_tls_password
shadow_tls_password=${shadow_tls_password:-$(generate_random_string)}

# Create and configure systemd service file for Shadow-Tls
echo "[Unit]
Description=Shadow-TLS Server Service
Documentation=man:sstls-server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/shadow-tls --fastopen --v3 server --listen ::0:$shadow_tls_port --server 127.0.0.1:11029 --tls gateway.icloud.com --password $shadow_tls_password
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=shadow-tls

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/shadow-tls.service

# Enable and start Shadow-Tls service
sudo systemctl enable shadow-tls.service
sudo systemctl daemon-reload
sudo systemctl start shadow-tls.service

# Output the configurations to the user in color
echo -e "\033[1;32mConfiguration completed:\033[0m"
echo -e "\033[1;34mSnell PSK: \033[0m$snell_psk"
echo -e "\033[1;34mShadow-Tls Port: \033[0m$shadow_tls_port"
echo -e "\033[1;34mShadow-Tls Password: \033[0m$shadow_tls_password"
