#!/bin/bash

sudo apt update
sudo apt dist-upgrade -y
sudo pihole -up
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
sudo apt install -y ./cloudflared-linux-amd64.deb
rm -f ./cloudflared-linux-amd64.deb
cloudflared -v

# EOF
