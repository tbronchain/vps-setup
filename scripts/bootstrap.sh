#!/bin/bash
# RUN AS ROOT

# keys and init
apt update
apt -y install ca-certificates curl gnupg lsb-release
mkdir -p /etc/apt/keyrings
if apt-key list | grep A4C6383F; then
    apt-key export A4C6383F | gpg --dearmour -o /etc/apt/keyrings/digitalocean-agent.gpg
    cat > /etc/apt/sources.list.d/digitalocean-agent.list <<EOF
deb [arch=amd64 signed-by=/etc/apt/keyrings/digitalocean-agent.gpg] https://repos.insights.digitalocean.com/apt/do-agent main main
EOF
fi
rm -f /etc/apt/keyrings/docker.gpg
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# updates
apt update
apt -y dist-upgrade

# tools
apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
apt install -y fail2ban ufw tmux git htop net-tools emacs-nox
systemctl enable fail2ban --now
apt install -y sendmail

# EOF
