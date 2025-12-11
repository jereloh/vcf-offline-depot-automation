#!/bin/bash

# ==============================================================================
# VCF Offline Depot Setup Script ( - Use at your own risk. This code was generated with the help of AI. Always review scripts before running them in a production environment. This software is provided "as is", without warranty of any kind.)
# Author: https://github.com/jereloh
# ==============================================================================

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

clear
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}   VCF Offline Depot Wizard (Photon OS 5)                   ${NC}"
echo -e "${GREEN}============================================================${NC}"

# 1. Gather Inputs
echo -e "\n${CYAN}--- Network ---${NC}"
read -p "Enter Hostname (FQDN) [depot.rainpole.io]: " DEPOT_FQDN; DEPOT_FQDN=${DEPOT_FQDN:-depot.rainpole.io}
read -p "Enter IP Address (CIDR) [172.16.10.14/24]: " DEPOT_IP; DEPOT_IP=${DEPOT_IP:-172.16.10.14/24}
read -p "Enter Gateway [172.16.10.1]: " DEPOT_GATEWAY; DEPOT_GATEWAY=${DEPOT_GATEWAY:-172.16.10.1}
read -p "Enter DNS [172.16.10.4 172.16.10.5]: " DEPOT_DNS; DEPOT_DNS=${DEPOT_DNS:-172.16.10.4 172.16.10.5}

echo -e "\n${CYAN}--- Storage ---${NC}"
lsblk
echo -e "${RED}WARNING: The disk selected below will be FORMATTED.${NC}"
read -p "Enter Disk Device (e.g., /dev/sdb): " DEPOT_DISK
if [ -z "$DEPOT_DISK" ]; then echo "Error: Disk required."; exit 1; fi

echo -e "\n${CYAN}--- SSL Cert Details ---${NC}"
read -p "Country [SE]: " C_C; C_C=${C_C:-SE}
read -p "State [Stockholm]: " C_ST; C_ST=${C_ST:-Stockholm}
read -p "City [Stockholm]: " C_L; C_L=${C_L:-Stockholm}
read -p "Org [Rainpole]: " C_O; C_O=${C_O:-Rainpole}
read -p "Unit [IT]: " C_OU; C_OU=${C_OU:-IT}
read -p "Admin Email [operations@rainpole.io]: " S_ADMIN; S_ADMIN=${S_ADMIN:-operations@rainpole.io}

echo -e "\n${CYAN}--- Auth ---${NC}"
read -p "Enter Username [admin]: " AUTH_USER; AUTH_USER=${AUTH_USER:-admin}

# 2. Configure System
echo -e "\n${GREEN}Applying System Config...${NC}"
cat <<EOF > /etc/systemd/network/10-static-en.network
[Match]
Name=eth0
[Network]
Address=$DEPOT_IP
Gateway=$DEPOT_GATEWAY
DNS=$DEPOT_DNS
EOF
chmod 644 /etc/systemd/network/10-static-en.network
hostnamectl set-hostname $DEPOT_FQDN
systemctl restart systemd-networkd
systemctl restart systemd-resolved

echo -e "${GREEN}Installing Packages...${NC}"
tdnf install httpd tar jq --assumeyes

echo -e "${GREEN}Formatting Storage...${NC}"
mkdir -p /var/www/html
mkfs.ext4 $DEPOT_DISK
if ! grep -q "$DEPOT_DISK" /etc/fstab; then echo "$DEPOT_DISK /var/www/html ext4 defaults 1 1" >> /etc/fstab; fi
mount -a

# 3. SSL Logic
echo -e "\n${CYAN}--- SSL Selection ---${NC}"
echo "1) Self-Signed (Automated)"
echo "2) CA-Signed (Manual Upload)"
read -p "Select [1]: " SSL_OPT; SSL_OPT=${SSL_OPT:-1}

mkdir -p /root/http-certificates
CERT_IP=$(echo $DEPOT_IP | cut -d'/' -f1)
openssl genpkey -out /root/http-certificates/server.key -algorithm RSA -pkeyopt rsa_keygen_bits:2048

cat << EOF > /root/http-certificates/conf.cfg
[req]
distinguished_name = req_distinguished_name
req_extensions = req_ext
prompt = no
[req_distinguished_name]
C = $C_C
ST = $C_ST
L = $C_L
O = $C_O
OU = $C_OU
CN = $DEPOT_FQDN
[req_ext]
subjectAltName = @alt_names
[alt_names]
IP.1 = $CERT_IP
DNS.1 = $DEPOT_FQDN
EOF

if [ "$SSL_OPT" == "1" ]; then
    echo -e "${YELLOW}Self-Signing...${NC}"
    openssl req -new -key /root/http-certificates/server.key \
        -out /root/http-certificates/request.csr -config /root/http-certificates/conf.cfg
    openssl x509 -req -days 365 -in /root/http-certificates/request.csr \
        -signkey /root/http-certificates/server.key -out /root/http-certificates/server.crt
else
    echo -e "${YELLOW}Generating CSR...${NC}"
    openssl req -new -key /root/http-certificates/server.key \
        -out /root/http-certificates/request.csr -config /root/http-certificates/conf.cfg
    echo -e "\n${RED}ACTION REQUIRED:${NC} Sign /root/http-certificates/request.csr with your CA."
    echo "Upload the result to /root/http-certificates/server.crt"
    while true; do
        read -p "Press Enter when server.crt is uploaded..."
        [ -f "/root/http-certificates/server.crt" ] && break || echo "File not found."
    done
fi

# Move files (FIXING THE TEXT BUG by not deleting them first)
mv /root/http-certificates/server.key /etc/httpd/conf/
mv /root/http-certificates/server.crt /etc/httpd/conf/
chmod 0400 /etc/httpd/conf/server.key /etc/httpd/conf/server.crt
chown root:root /etc/httpd/conf/server.key /etc/httpd/conf/server.crt

# 4. Apache Config
echo -e "${GREEN}Configuring Apache...${NC}"
HTTPD_CONF="/etc/httpd/conf/httpd.conf"
SSL_CONF="/etc/httpd/conf/extra/httpd-ssl.conf"

# Enable SSL Modules
sed -i 's|#LoadModule ssl_module|LoadModule ssl_module|' $HTTPD_CONF
sed -i 's|#LoadModule socache_shmcb_module|LoadModule socache_shmcb_module|' $HTTPD_CONF
sed -i 's|#Include conf/extra/httpd-ssl.conf|Include conf/extra/httpd-ssl.conf|' $HTTPD_CONF

# Configure SSL Conf
sed -i 's|DocumentRoot "/etc/httpd/html"|DocumentRoot "/var/www/html"|' $SSL_CONF
sed -i "s|ServerAdmin you@example.com|ServerAdmin $S_ADMIN|" $SSL_CONF
sed -i "s|ServerName www.example.com:443|ServerName $DEPOT_FQDN:443|" $SSL_CONF

# FIX: Update Main httpd.conf to point to new DocumentRoot
# (The text implies this is done, but the default is /etc/httpd/html)
sed -i 's|DocumentRoot "/etc/httpd/html"|DocumentRoot "/var/www/html"|' $HTTPD_CONF
sed -i 's|<Directory "/etc/httpd/html">|<Directory "/var/www/html">|' $HTTPD_CONF

# Grant Permissions
sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/ s/Require all denied/Require all granted/' $HTTPD_CONF

# Inject VCF Blocks
cat << 'EOF' > /tmp/vcf_blocks.conf
<Directory /var/www/html/PROD/COMP>
    AuthType Basic
    AuthName "Basic Authentication"
    AuthUserFile /etc/httpd/conf/.htpasswd
    require valid-user
</Directory>
<Directory /var/www/html/PROD/metadata>
    AuthType Basic
    AuthName "Basic Authentication"
    AuthUserFile /etc/httpd/conf/.htpasswd
    require valid-user
</Directory>
<Directory "/var/www/html/PROD/COMP/Compatibility/VxrailCompatibilityData.json">
    <If "%{HTTP:Cookie} == 'ngssosession=ngsso-token' ">
    Require all granted
    </If>
</Directory>
<Directory /var/www/html/PROD/vsan/hcl>
    Require all granted
</Directory>
    Alias /products/v1/bundles/lastupdatedtime /var/www/html/PROD/vsan/hcl/lastupdatedtime.json
    Alias /products/v1/bundles/all /var/www/html/PROD/vsan/hcl/all.json
<Directory /var/www/html/umds-patch-store>
    Require all granted
</Directory>
EOF
sed -i '/<\/VirtualHost>/e cat /tmp/vcf_blocks.conf' $SSL_CONF
rm -f /tmp/vcf_blocks.conf

# Auth
echo -e "${YELLOW}Set Password for $AUTH_USER:${NC}"
htpasswd -c /etc/httpd/conf/.htpasswd $AUTH_USER
chown apache /etc/httpd/conf/.htpasswd
chmod 0400 /etc/httpd/conf/.htpasswd

# Firewall (Fixing Text Typos)
SAVE="/etc/systemd/scripts/ip4save"
if ! grep -q "dport 443" $SAVE; then sed -i '/COMMIT/i -A INPUT -p tcp -m tcp --dport 443 -j ACCEPT' $SAVE; fi
if ! grep -q "dport 22" $SAVE; then sed -i '/COMMIT/i -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT' $SAVE; fi
systemctl restart iptables

# Start
httpd -t
systemctl enable httpd

# Cleanup & Final Permissions
rm -rf /root/http-certificates
rm -f /var/www/html/index.html
chown apache -R /var/www/html/
find /var/www/html -type d -exec chmod 0500 {} \;
find /var/www/html -type f -exec chmod 0400 {} \;

# 5. Update & Reboot
echo -e "\n${GREEN}Updating System...${NC}"
tdnf update --assumeyes
echo -e "${YELLOW}Rebooting in 5 seconds to apply updates...${NC}"
for i in {5..1}; do echo -ne "$i... \r"; sleep 1; done
reboot
