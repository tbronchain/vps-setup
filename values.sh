export OUTDIR="./out"

export SSH_PORT="22"
export OPENVPN_TCP_PORTS=("2222")
export OPENVPN_UDP_PORTS=("33333")
export OPENVPN_UDP_DNS_PORTS=("44444")
export OPENVPN_ALL_PORTS=( "${OPENVPN_TCP_PORTS[@]}" "${OPENVPN_UDP_PORTS[@]}" "${OPENVPN_UDP_DNS_PORTS[@]}" )
export WIREGUARD_PORT="55555"
export WIREGUARD_CLIENTS=("xx")
export FLOATING_IP="1.2.3.4"

export METAD=1

export ADMIN_EMAIL=""
export SENDER_EMAIL=""
export SMTP_SERVER=""
export SMTP_PASSWD=""

export PUBLIC_IP=""
export ANCHOR_IP=""
export PUBLIC6_IP=""
