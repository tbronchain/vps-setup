OUTDIR="./out"
SSH_PORT="22"
OPENVPN_TCP_PORTS=("2222")
OPENVPN_UDP_PORTS=("33333")
OPENVPN_UDP_DNS_PORTS=("44444")
OPENVPN_ALL_PORTS=( "${OPENVPN_TCP_PORTS[@]}" "${OPENVPN_UDP_PORTS[@]}" "${OPENVPN_UDP_DNS_PORTS[@]}" )
WIREGUARD_PORTS=("55555")


ADMIN_EMAIL=""
SENDER_EMAIL=""
SMTP_SERVER=""
SMTP_PASSWD=""
