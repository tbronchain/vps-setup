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
        sudo wg genkey | sudo tee "/etc/wireguard/${_client}.key" | sudo wg pubkey | sudo tee "/etc/wireguard/${_client}.pub"
        sudo wg genpsk | sudo tee "/etc/wireguard/${_client}.psk"
        {
            echo "[Peer]"
            echo "PublicKey = $(sudo cat /etc/wireguard/${_client}.pub)"
            echo "PresharedKey = $(sudo cat /etc/wireguard/${_client}.psk)"
            echo "AllowedIPs = 10.100.0.${_CLIENT_ID}/32, fd08:4711::${_CLIENT_ID}/128"
            echo ""
        } | sudo tee /etc/wireguard/wg0.conf
        {
            echo "[Interface]"
            echo "Address = 10.100.0.${_CLIENT_ID}/32, fd08:4711::${_CLIENT_ID}/128"
            echo "DNS = 10.100.0.1"
            echo "PrivateKey = $(sudo cat /etc/wireguard/${_client}.key)"
            echo ""
            cat <<EOF
[Peer]
AllowedIPs = 10.100.0.1/32, fd08:4711::1/128
Endpoint = ${FLOATING_IP}:${WIREGUARD_PORT}
PersistentKeepalive = 25
EOF
            echo "PublicKey = $(sudo cat /etc/wireguard/server.pub)"
            echo "PresharedKey = $(sudo cat /etc/wireguard/${_client}.psk)"
        } > "${OUTDIR}"/"wg_${_client}".conf
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
        gen_ovpn_new_client "client" $_PROTO $_PORT
        envsubst < conf/openvpn/server.conf | sudo tee /etc/openvpn/server/${_SNAME}.conf
        sudo systemctl enable openvpn-server@${_SNAME}
        sudo systemctl restart openvpn-server@${_SNAME}
        _NET4_ID=$((_NET4_ID+1))
        _NET6_ID=$((_NET6_ID+1))
    done
}
