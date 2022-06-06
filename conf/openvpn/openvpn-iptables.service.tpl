[Unit]
Before=network.target
[Install]
WantedBy=multi-user.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/iptables -I INPUT -p tcp --dport 443 -j ACCEPT
ExecStart=/usr/sbin/iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStart=/usr/sbin/ip6tables -I INPUT -p tcp --dport 443 -j ACCEPT
ExecStart=/usr/sbin/ip6tables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStop=/usr/sbin/iptables -D INPUT -p tcp --dport 443 -j ACCEPT
ExecStop=/usr/sbin/iptables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
ExecStop=/usr/sbin/ip6tables -D INPUT -p tcp --dport 443 -j ACCEPT
ExecStop=/usr/sbin/ip6tables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
