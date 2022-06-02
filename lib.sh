new_client () {
    local _CLIENT="$1"
    local _PROTO="$2"
    local _PORT="$3"

    #EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full "${_CLIENT}" nopass
    {
        # Generates the custom client.ovpn
        envsubst < conf/openvpn/client-common.txt
        echo "<ca>"
        cat /etc/openvpn/server/easy-rsa/pki/ca.crt
        echo "</ca>"
        echo "<cert>"
        sed -ne '/BEGIN CERTIFICATE/,$ p' /etc/openvpn/server/easy-rsa/pki/issued/"${_CLIENT}".crt
        echo "</cert>"
        echo "<key>"
        cat /etc/openvpn/server/easy-rsa/pki/private/"${_CIENT}".key
        echo "</key>"
        echo "<tls-crypt>"
        sed -ne '/BEGIN OpenVPN Static key/,$ p' /etc/openvpn/server/tc.key
        echo "</tls-crypt>"
    } > "${OUTDIR}"/"${_CLIENT}_${_PROTO}_${_PORT}".ovpn
}

function gen_ovpn_server_conf () {
    _PROTO="$1"
    shift 1
    if [[ "$2" != "--dns-only" ]]; then
        _REDIRECT='push "redirect-gateway def1 ipv6 bypass-dhcp"'
    else
        _REDIRECT=''
        shift 1
    fi

    export _NET4_ID
    export _NET6_ID
    for _PORT in $@; do
        _NETWORK="server 10.${_NET4_ID}.0.0 255.255.255.0"
        _NETWORK_V6="server-ipv6 fddd:${_NET6_ID}:1194:1194::/64"
        _SERVER="10.${_NET4_ID}.0.1"
        if [[ ${_NET4_ID} -eq 8 ]]; then
            _SNAME="server"
        else
            _SNAME="server_${_PROTO}_${_PORT}"
            #./openvpn-install.sh
        fi
        new_client "client" $_PROTO $_PORT
        envsubst < conf/openvpn/server.conf | sudo tee /etc/openvpn/server/${_SNAME}.conf
        systemctl enable openvpn-server@${_SNAME}
        systemctl restart openvpn-server@${_SNAME}
        _NET4_ID=$((_NET4_ID+1))
        _NET6_ID=$((_NET6_ID+1))
    done
}
