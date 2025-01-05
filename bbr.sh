#!/bin/bash

# 检测 Ubuntu 版本
ubuntu_version=$(lsb_release -rs)
if (( $(echo "$ubuntu_version >= 22.04" | bc -l) )); then
  echo "Ubuntu 版本：$ubuntu_version (符合要求)"
else
  echo "Ubuntu 版本：$ubuntu_version (不符合最低要求 22.04)"
  exit 1
fi

# 检测内核版本
kernel_version=$(uname -r)
echo "内核版本：$kernel_version"

# 检查内核是否支持 BBR (>= 4.9)
if (( $(echo "$kernel_version >= 4.9" | bc -l) )); then
  echo "内核版本 >= 4.9，支持 BBR。"
else
  echo "内核版本 < 4.9，可能不支持 BBR。"
  read -r -p "是否继续尝试开启 BBR？ (y/n): " continue_choice
  if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
    echo "操作已取消。"
    exit 0
  fi
fi

# 检查 BBR 是否已开启
bbr_loaded=$(lsmod | grep bbr)
congestion_control=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')

if [[ -n "$bbr_loaded" ]] && [[ "$congestion_control" == "bbr" ]]; then
  echo "BBR 已开启。"
  exit 0
else
  echo "BBR 未开启。"
fi

# 询问用户是否开启 BBR
read -r -p "是否开启 BBR？ (y/n): " choice
if [[ ! "$choice" =~ ^[Yy]$ ]]; then
  echo "操作已取消。"
  exit 0
fi

# 开启 BBR
echo "net.core.default_qdisc = fq" | sudo tee -a /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control = bbr" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 再次检查 BBR 是否开启成功
bbr_loaded=$(lsmod | grep bbr)
congestion_control=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')

if [[ -n "$bbr_loaded" ]] && [[ "$congestion_control" == "bbr" ]]; then
  echo "BBR 已成功开启！"
else
  echo "BBR 开启失败，请检查日志或手动排查。"
fi