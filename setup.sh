#!/bin/bash

source lib.sh
source values.sh
source .env

set -ex

mkdir -p "${OUTDIR}"

sudo bash -ex scripts/bootstrap.sh

gPUBLIC_IP=$(curl -s 169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address)
ANCHOR_IP=$(curl -s 169.254.169.254/metadata/v1/interfaces/public/0/anchor_ipv4/address)

# configure ssh
envsubst < conf/ssh/sshd_config | sudo tee /etc/ssh/sshd_config
sudo systemctl restart sshd

# configure ufw firewall
sudo ufw default deny incoming
sudo ufw default allow outgoing
# allow in traffic from floatting IP only
sudo ufw allow from any to ${ANCHOR_IP} port ${SSH_PORT}
for _PORT in "${OPENVPN_ALL_PORTS[@]}"; do
    sudo ufw allow from any to ${ANCHOR_IP} port ${_PORT}
done
sudo ufw allow from any to ${ANCHOR_IP} port ${WIREGUARD_PORT}
sudo ufw enable


# config sendmail
sudo mkdir /etc/mail/authinfo
sudo chmod -R 700 /etc/mail/authinfo
sudo cat > /etc/mail/authinfo/smtp-auth <<EOF
AuthInfo: "U:root" "I:${SENDER_EMAIL}" "P:${SMTP_PASSWD}"
EOF
sudo makemap hash /etc/mail/authinfo/smtp-auth < /etc/mail/authinfo/smtp-auth
envsubst < conf/mail/sendmail.mc | sudo tee /etc/mail/sendmail.mc
pushd /etc/mail
sudo make
popd
sudo systemctl restart sendmail


# config fail2ban
envsubst < conf/fail2ban/jail.local | sudo tee /etc/fail2ban/jail.local
cp -f conf/fail2ban/filter.d/* /etc/fail2ban/filter.d/
cp -f conf/fail2ban/jail.d/* /etc/fail2ban/jail.d/
printf -v _OPENVPN_PORTS '%s,' "${OPENVPN_ALL_PORTS[@]}"
_OPENVPN_PORTS="${_OPENVPN_PORTS%,}"
envsubst < conf/fail2ban/jail.d/openvpn | sudo tee /etc/fail2ban/jail.d/openvpn
sudo systemctl restart fail2ban


# config openvpn
wget https://github.com/Nyr/openvpn-install/raw/master/openvpn-install.sh
chmod 755 openvpn-install.sh
echo 'Name your client `client` in order to get the script to work...'
sleep 2
./openvpn-install.sh
sudo touch /var/log/openvpn.log
_NET4_ID=8
_NET6_ID=1194
gen_ovpn_server_conf tcp ${OPENVPN_TCP_PORTS[@]}
gen_ovpn_server_conf udp ${OPENVPN_UDP_PORTS[@]}
gen_ovpn_server_conf udp --dns-only ${OPENVPN_UDP_DNS_PORTS[@]}


# config wireguard
sudo apt-get install -y wireguard wireguard-tools qrencode
sudo mkdir -p /etc/wireguard
sudo wg genkey | sudo tee /etc/wireguard/server.key | sudo wg pubkey | sudo tee /etc/wireguard/server.pub
(cat | sudo tee /etc/wireguard/wg0.conf) <<EOF
[Interface]
Address = 10.100.0.1/24, fd08:4711::1/64
ListenPort = ${WIREGUARD_PORT}
EOF
echo "PrivateKey = $(sudo cat /etc/wireguard/server.key)" | sudo tee /etc/wireguard/wg0.conf
sudo systemctl enable wg-quick@wg0.service
sudo systemctl daemon-reload
sudo systemctl start wg-quick@wg0
sudo wg
gen_wg_net_client ${WIREGUARD_CLIENTS[@]}


# install unbound


# install cloudflared


# install pi-hole
curl -sSL https://install.pi-hole.net | bash


# EOF
