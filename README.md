# vps-setup

PR welcome!

A set of scripts to deploy a minimal-ish [VPS] server with:

- custom SSH
- UFW firewall
- sendmail
- fail2ban (ssh and openvpn setup)
- openvpn (tcp + udp)
- wireguard (udp)
- unbound
- cloudflared
- pi-hole
- a few extras...

What this is not: a full featured script that does everything for you

What this is: a fairly minimal, comprehensive set of scripts you can use to setup a robust privacy oriented VPN server.

Warning: latest changes might not be fully tested. Use at your own risks and please report issues.

## Requirements

First, check `values.sh` and set what you need, but don't set private credentials. Alternatively, create a `.env` file and set whatever you want, including credentials.

Produced files will be stored under the `./out` directory by default.

The script assumes you have a server setup, and running the script under your unprivileged user with sudo access. It will not configure users or ssh/keys for you.

## Install

Run the script with:

```
$ ./setup.sh
```

The follow the instructions during install. Welcome to file Github issues to report bugs.

## Further config

### WSL2 fix

#### The story

If you are using Windows with WSL2, you might have issues with Wiregard (and potentially OpenVPN too).

The problem seems to be in 2 places:

1- Wireguard interface MTU is 1420, therefore the interface MTU needs to be properly set
2- WSL2 sets the host IP address as its DNS server, which gets lost

The MTU fix is fairly simple, but I haven't succeeded to *simply* automate it - couldn't find where the network interface config was - seems absent from the usual places (`/etc/netplan` `/etc/network` `/etc/dhcp`), I didn't dig very much further.

Regarding the DNS issue. For some reasons, Wireguard "killswitch" prevents you from doing queries to the host IP out of the box. This might be expected form a kill-switch, but not using a kill-switch seems to cause issues too.

What's a kill-switch? - Essentially, you'd set a kill-switch by setting the client wg config as follow:

```
...
[Peer]
PublicKey = xxx
PresharedKey = xxx
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = <server_ip>:<server_port>
PersistentKeepalive = 25
```

and without kill-switch:

```
...
[Peer]
PublicKey = xxx
PresharedKey = xxx
AllowedIPs = 0.0.0.0/1, 128.0.0.0/1, ::/1, 8000::/1
Endpoint = <server_ip>:<server_port>
PersistentKeepalive = 25
```

The obvious difference between these two config is the way routes are being setup in Windows. When routing `0.0.0.0/0` to the tunnel, requets to the host IP don't work, but when setting the ips in 2 blocks, it seems to let these request go through.

I assume it is an internal syntax condition, but it might be a workaround in Windows network stack - something to explore for another day.

There are 2 problems with disabling the kill-switch:

1- there seems to be DNS-leak, which defeats the purpose of this setup
2- it still doesn't route the DNS queries to the Wireguard tunnel

#### The solution

An ideal solution would be to properly route the requets coming from the WSL2 VM to the Wireguard tunnel. I am not a Windows network expert and despite some hours of Googling, couldn't find the right way to do it (suggestion are very welcome!).

So I came up with a simple workaround to add to your `~/.bashrc` file (change the nameserver to your wireguard server ip, if different):

```
function wg_on () {
    sudo ip link set mtu 1420 eth0
    [[ ! -f /etc/resolv.conf.bak ]] && sudo cp -f /etc/resolv.conf /etc/resolv.conf.bak
    echo 'nameserver 10.100.0.1' | sudo tee /etc/resolv.conf
}

function wg_off () {
    sudo ip link set mtu 1500 eth0
    [[ -f /etc/resolv.conf.bak ]] && sudo mv -f /etc/resolv.conf.bak /etc/resolv.conf
}
```

Then hit `wg_on` when connected to your Wireguard tunnel and `wg_off` when off.

It would be easy to quickly change this function if you want if to be automatically done. You could also implement some sort of auto detection, but I am quite happy to keep it manual.


## Improvements

- more versatile config
- avoid use of any workarounds and only follow best practices
- remote execution
