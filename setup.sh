#!/bin/bash

source lib.sh
source values.sh
source .env

set -ex

mkdir -p "${OUTDIR}/tmp"

sudo bash -ex scripts/bootstrap.sh

if [[ $METAD -eq 1 ]]; then
    export PUBLIC_IP=$(curl -s 169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
    export ANCHOR_IP=$(curl -s 169.254.169.254/metadata/v1/interfaces/public/0/anchor_ipv4/address)
    export PUBLIC6_IP=$(curl -s 169.254.169.254/metadata/v1/interfaces/public/0/ipv6/address)
fi


# configure ssh
echo $SSH_PORT
envsubst < conf/ssh/sshd_config > ${OUTDIR}/tmp/sshd_config
sudo cp ${OUTDIR}/tmp/sshd_config /etc/ssh/sshd_config
sudo systemctl restart sshd


# configure ufw firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing
# allow in traffic from floatting IP only
sudo ufw allow from any to ${PUBLIC_IP} port ${SSH_PORT}
for _PORT in "${OPENVPN_ALL_PORTS[@]}"; do
    sudo ufw allow from any to ${PUBLIC_IP} port ${_PORT}
done
sudo ufw allow from any to ${PUBLIC_IP} port ${WIREGUARD_PORT}
sudo cp -f conf/ufw/etc/* /etc/ufw/
sudo cp -f conf/ufw/default/ufw /etc/default/ufw
sudo ufw enable
sudo iptables -A INPUT -p udp --dport 80 -j REJECT --reject-with icmp-port-unreachable
sudo iptables -A INPUT -p tcp --dport 443 -j REJECT --reject-with tcp-reset
sudo iptables -A INPUT -p udp --dport 443 -j REJECT --reject-with icmp-port-unreachable
sudo ip6tables -A INPUT -p udp --dport 80 -j REJECT --reject-with icmp6-port-unreachable
sudo ip6tables -A INPUT -p tcp --dport 443 -j REJECT --reject-with tcp-reset
sudo ip6tables -A INPUT -p udp --dport 443 -j REJECT --reject-with icmp6-port-unreachable


# config sendmail
sudo mkdir -p /etc/mail/authinfo
sudo chmod 700 /etc/mail/authinfo
sudo chmod 600 /etc/mail/authinfo/smtp-auth
(cat | sudo tee /etc/mail/authinfo/smtp-auth) <<EOF
AuthInfo: "U:root" "I:${SENDER_EMAIL}" "P:${SMTP_PASSWD}"
EOF
sudo cat /etc/mail/authinfo/smtp-auth | sudo makemap hash /etc/mail/authinfo/smtp-auth
envsubst < conf/mail/sendmail.mc | sudo tee /etc/mail/sendmail.mc
pushd /etc/mail
sudo make
popd
sudo systemctl restart sendmail


# config fail2ban
envsubst < conf/fail2ban/jail.local | sudo tee /etc/fail2ban/jail.local
sudo cp -f conf/fail2ban/filter.d/* /etc/fail2ban/filter.d/
sudo cp -f conf/fail2ban/jail.d/* /etc/fail2ban/jail.d/
printf -v _OPENVPN_PORTS '%s,' "${OPENVPN_ALL_PORTS[@]}"
_OPENVPN_PORTS="${_OPENVPN_PORTS%,}"
envsubst < conf/fail2ban/jail.d/openvpn | sudo tee /etc/fail2ban/jail.d/openvpn
sudo systemctl restart fail2ban

cp -f conf/openvpn/openvpn-iptables.service.tpl conf/openvpn/openvpn-iptables.service

# config openvpn
wget https://github.com/Nyr/openvpn-install/raw/master/openvpn-install.sh
chmod 755 openvpn-install.sh
echo 'Name your client `client` in order to get the script to work...'
sleep 2
sudo ./openvpn-install.sh
sudo touch /var/log/openvpn.log
_NET4_ID=8
_NET6_ID=1194
gen_ovpn_server_conf tcp ${OPENVPN_TCP_PORTS[@]}
gen_ovpn_server_conf udp ${OPENVPN_UDP_PORTS[@]}
gen_ovpn_server_conf udp --dns-only ${OPENVPN_UDP_DNS_PORTS[@]}
rm -f ./openvpn-install.sh
sudo cp -f conf/openvpn/openvpn-iptables.service /etc/systemd/system/openvpn-iptables.service
sudo systemctl daemon-reload
sudo systemctl restart openvpn-iptables


# config wireguard
sudo apt-get install -y wireguard wireguard-tools qrencode
sudo mkdir -p /etc/wireguard
if [[ ! sudo test -f /etc/wireguard/server.key ]] || [[ ! sudo test -f /etc/wireguard/server.pub ]]; then
    sudo wg genkey | sudo tee /etc/wireguard/server.key | sudo wg pubkey | sudo tee /etc/wireguard/server.pub
fi
(cat | sudo tee /etc/wireguard/wg0.conf) <<EOF
[Interface]
Address = 10.100.0.1/24, fd08:4711::1/64
ListenPort = ${WIREGUARD_PORT}
PrivateKey = $(sudo cat /etc/wireguard/server.key)
EOF
ufw_vpn_rules "10.100.0.0/24"
sudo systemctl enable wg-quick@wg0.service
sudo systemctl daemon-reload
sudo systemctl start wg-quick@wg0
sudo wg
gen_wg_net_client ${WIREGUARD_CLIENTS[@]}
cat >> conf/openvpn/openvpn-iptables.service <<EOF
ExecStart=/usr/sbin/iptables -t nat -A POSTROUTING -s 10.100.0.0/24 ! -d 10.100.0.0/24 -j SNAT --to ${ANCHOR_IP}
ExecStart=/usr/sbin/iptables -I FORWARD -s 10.100.0.0/24 -j ACCEPT
ExecStop=/usr/sbin/iptables -t nat -D POSTROUTING -s 10.100.0.0/24 ! -d 10.100.0.0/24 -j SNAT --to ${ANCHOR_IP}
ExecStop=/usr/sbin/iptables -D FORWARD -s 10.100.0.0/24 -j ACCEPT
ExecStart=/usr/sbin/ip6tables -t nat -A POSTROUTING -s fd08:4711::1/64 ! -d fd08:4711::1/64 -j SNAT --to ${PUBLIC6_IP}
ExecStart=/usr/sbin/ip6tables -I FORWARD -s fd08:4711::1/64 -j ACCEPT
ExecStop=/usr/sbin/ip6tables -t nat -D POSTROUTING -s fd08:4711::1/64 ! -d fd08:4711::1/64 -j SNAT --to ${PUBLIC6_IP}
ExecStop=/usr/sbin/ip6tables -D FORWARD -s fd08:4711::1/64 -j ACCEPT
EOF
sudo cp -f conf/openvpn/openvpn-iptables.service /etc/systemd/system/openvpn-iptables.service
sudo systemctl daemon-reload
sudo systemctl restart openvpn-iptables


# install unbound
sudo apt install -y unbound
sudo mkdir -p /etc/unbound/unbound.conf.d
envsubst < conf/unbound/pi-hole.conf | sudo tee /etc/unbound/unbound.conf.d/pi-hole.conf
sudo mkdir -p /etc/dnsmasq.d
echo 'edns-packet-max=1232' | sudo tee /etc/dnsmasq.d/99-edns.conf
sudo systemctl enable unbound
sudo systemctl restart unbound
dig pi-hole.net @127.0.0.1 -p 5335
dig sigfail.verteiltesysteme.net @127.0.0.1 -p 5335
dig sigok.verteiltesysteme.net @127.0.0.1 -p 5335


# install cloudflared
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo apt install -y ./cloudflared-linux-amd64.deb
rm -f ./cloudflared-linux-amd64.deb
cloudflared -v
if ! grep cloudflared /etc/passwd; then
    sudo useradd -s /usr/sbin/nologin -r -M cloudflared
fi
(cat | sudo tee /etc/default/cloudflared) <<EOF
# Commandline args for cloudflared, using Cloudflare DNS
CLOUDFLARED_OPTS="--port 5053 --upstream https://1.1.1.1/dns-query --upstream https://1.0.0.1/dns-query"
EOF
sudo chown cloudflared:cloudflared /etc/default/cloudflared
sudo chown cloudflared:cloudflared /usr/local/bin/cloudflared
envsubst < conf/cloudflared/cloudflared.service | sudo tee /etc/systemd/system/cloudflared.service
sudo systemctl enable cloudflared
sudo systemctl start cloudflared
sudo systemctl status cloudflared
dig @127.0.0.1 -p 5053 google.com


# install pi-hole
if ! pihole -v; then
    #curl -sSL https://install.pi-hole.net | bash
    curl -L https://install.pi-hole.net > pihole.sh
    chmod +x pihole.sh
    export PIHOLE_SKIP_OS_CHECK=true
    sudo -E bash /dev/stdin --unattended < pihole.sh
    rm -f pihole.sh
else
    sudo pihole -up
    export PIHOLE_SKIP_OS_CHECK=true
    sudo -E pihole -r
fi
sudo cp -f conf/pihole/dnsmasq.d/* /etc/dnsmasq.d/
sudo cp -f conf/pihole/etc/* /etc/pihole/
sudo python3 vendors/whitelist/scripts/whitelist.py


# save rules
sudo iptables-save | sudo tee /etc/pihole/rules.v4
sudo ip6tables-save | sudo tee /etc/pihole/rules.v6


echo "Install done, please reboot server to ensure everything is working."

# EOF
