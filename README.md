bash <(curl -fsSL https://raw.githubusercontent.com/wangpao/snell/main/snell.sh)

bash <(curl -fsSL https://raw.githubusercontent.com/wangpao/snell/main/bbr.sh)

bash <(curl -fsSL https://raw.githubusercontent.com/wangpao/snell/main/clean_vps.sh)

echo "if \$programname == 'shadow-tls' then stop" | sudo tee /etc/rsyslog.d/10-discard-shadow-tls.conf && sudo systemctl restart rsyslog.service && echo "✅ 操作成功！shadow-tls 的日志已被过滤。"
