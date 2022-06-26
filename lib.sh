function gen_ovpn_new_client () {
    export _CLIENT="$1"
    export _PROTO="$2"
    export _PORT="$3"

    #EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full "${_CLIENT}" nopass
    {
        # Generates the custom client.ovpn
        envsubst < conf/openvpn/client-common.txt
        echo "<ca>"
        sudo cat /etc/openvpn/server/easy-rsa/pki/ca.crt
        echo "</ca>"
        echo "<cert>"
        sudo sed -ne '/BEGIN CERTIFICATE/,$ p' /etc/openvpn/server/easy-rsa/pki/issued/"${_CLIENT}".crt
        echo "</cert>"
        echo "<key>"
        sudo cat /etc/openvpn/server/easy-rsa/pki/private/"${_CLIENT}".key
        echo "</key>"
        echo "<tls-crypt>"
        sudo sed -ne '/BEGIN OpenVPN Static key/,$ p' /etc/openvpn/server/tc.key
        echo "</tls-crypt>"
    } > "${OUTDIR}"/"${_CLIENT}_${_PROTO}_${_PORT}".ovpn
}

function gen_wg_net_client () {
    _CLIENT_ID=2
    for _client in $@; do
        if [[ -f "${OUTDIR}"/"wg_${_client}".conf ]]; then
            echo "config ${OUTDIR}/wg_${_client}.conf found"
        else
            echo "config ${OUTDIR}/wg_${_client}.conf not found, generating..."
            sudo wg genkey | sudo tee "/etc/wireguard/${_client}.key" | sudo wg pubkey | sudo tee "/etc/wireguard/${_client}.pub"
            sudo wg genpsk | sudo tee "/etc/wireguard/${_client}.psk"
            {
                echo "[Peer]"
                echo "PublicKey = $(sudo cat /etc/wireguard/${_client}.pub)"
                echo "PresharedKey = $(sudo cat /etc/wireguard/${_client}.psk)"
                echo "AllowedIPs = 10.100.0.${_CLIENT_ID}/32, fd08:4711::${_CLIENT_ID}/128"
                #echo "AllowedIPs = 0.0.0.0/0, fd08:4711::${_CLIENT_ID}/128"
                echo ""
            } | sudo tee -a /etc/wireguard/wg0.conf
            {
                echo "[Interface]"
                echo "Address = 10.100.0.${_CLIENT_ID}/32, fd08:4711::${_CLIENT_ID}/128"
                echo "DNS = 10.100.0.1"
                echo "PrivateKey = $(sudo cat /etc/wireguard/${_client}.key)"
                echo ""
                #AllowedIPs = 10.100.0.1/32, fd08:4711::1/128
                cat <<EOF
[Peer]
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${PUBLIC_IP}:${WIREGUARD_PORT}
PersistentKeepalive = 25
EOF
                echo "PublicKey = $(sudo cat /etc/wireguard/server.pub)"
                echo "PresharedKey = $(sudo cat /etc/wireguard/${_client}.psk)"
            } > "${OUTDIR}"/"wg_${_client}".conf
            {
                echo "[Interface]"
                echo "Address = 10.100.0.${_CLIENT_ID}/32, fd08:4711::${_CLIENT_ID}/128"
                echo "DNS = 10.100.0.1"
                echo "PrivateKey = $(sudo cat /etc/wireguard/${_client}.key)"
                echo ""
                #AllowedIPs = 10.100.0.1/32, fd08:4711::1/128
                cat <<EOF
[Peer]
AllowedIPs = 10.100.0.0/16, fd08:4711::1/64
Endpoint = ${PUBLIC_IP}:${WIREGUARD_PORT}
PersistentKeepalive = 25
EOF
                echo "PublicKey = $(sudo cat /etc/wireguard/server.pub)"
                echo "PresharedKey = $(sudo cat /etc/wireguard/${_client}.psk)"
            } > "${OUTDIR}"/"wg_${_client}_dnsonly".conf
        fi
        _CLIENT_ID=$((_CLIENT_ID+1))
    done
    sudo systemctl restart wg-quick@wg0
}

function gen_ovpn_server_conf () {
    export _PROTO="$1"
    shift
    if [[ "$1" != "--dns-only" ]]; then
        export _REDIRECT='push "redirect-gateway def1 ipv6 bypass-dhcp"'
    else
        export _REDIRECT=''
        shift
    fi

    export _NET4_ID
    export _NET6_ID
    for _PORT in $@; do
        export _PORT
        export _NETWORK="server 10.${_NET4_ID}.0.0 255.255.255.0"
        export _NETWORK_V6="server-ipv6 fddd:${_NET6_ID}:1194:1194::/64"
        export _SERVER="10.${_NET4_ID}.0.1"
        if [[ ${_NET4_ID} -eq 8 ]]; then
            _SNAME="server"
        else
            _SNAME="server_${_PROTO}_${_PORT}"
            #./openvpn-install.sh
        fi
        cat >> conf/openvpn/openvpn-iptables.service <<EOF
ExecStart=/usr/sbin/iptables -t nat -A POSTROUTING -s 10.${_NET4_ID}.0.0/24 ! -d 10.${_NET4_ID}.0.0/24 -j SNAT --to ${ANCHOR_IP}
ExecStart=/usr/sbin/iptables -I FORWARD -s 10.${_NET4_ID}.0.0/24 -j ACCEPT
ExecStop=/usr/sbin/iptables -t nat -D POSTROUTING -s 10.${_NET4_ID}.0.0/24 ! -d 10.${_NET4_ID}.0.0/24 -j SNAT --to ${ANCHOR_IP}
ExecStop=/usr/sbin/iptables -D FORWARD -s 10.${_NET4_ID}.0.0/24 -j ACCEPT
ExecStart=/usr/sbin/ip6tables -t nat -A POSTROUTING -s fddd:${_NET6_ID}:1194:1194::/64 ! -d fddd:${_NET6_ID}:1194:1194::/64 -j SNAT --to ${PUBLIC6_IP}
ExecStart=/usr/sbin/ip6tables -I FORWARD -s fddd:${_NET6_ID}:1194:1194::/64 -j ACCEPT
ExecStop=/usr/sbin/ip6tables -t nat -D POSTROUTING -s fddd:${_NET6_ID}:1194:1194::/64 ! -d fddd:${_NET6_ID}:1194:1194::/64 -j SNAT --to ${PUBLIC6_IP}
ExecStop=/usr/sbin/ip6tables -D FORWARD -s fddd:${_NET6_ID}:1194:1194::/64 -j ACCEPT
EOF
        gen_ovpn_new_client "client" $_PROTO $_PORT
        envsubst < conf/openvpn/server.conf | sudo tee /etc/openvpn/server/${_SNAME}.conf
        ufw_vpn_rules "10.${_NET4_ID}.0.0/24"
        sudo systemctl enable openvpn-server@${_SNAME}
        sudo systemctl restart openvpn-server@${_SNAME}
        _NET4_ID=$((_NET4_ID+1))
        _NET6_ID=$((_NET6_ID+1))
    done
}

function ufw_vpn_rules () {
    local _NETWORK="$1"

    sudo ufw allow in from ${_NETWORK} to any port 53 proto udp
    sudo ufw allow in from ${_NETWORK} to any port 80,6666,8080,2342 proto tcp
}
