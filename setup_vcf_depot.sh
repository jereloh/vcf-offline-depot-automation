#!/bin/bash

# ==============================================================================
# VCF Offline Depot Setup Script (Photon OS 5)
#  - Use at your own risk. Always review before using in production.
# Author: https://github.com/jereloh
# ==============================================================================

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

HTTPD_CONF="/etc/httpd/conf/httpd.conf"
SSL_CONF="/etc/httpd/conf/extra/httpd-ssl.conf"
CERT_DIR="/root/http-certificates"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="/root/vcf_depot.state"

# ---------------------------------------------------------------------------
# 0. Load previous state if present
# ---------------------------------------------------------------------------

NET_DONE=0
STORAGE_DONE=0
SSL_DONE=0

DEPOT_FQDN=""
DEPOT_IP=""
DEPOT_GATEWAY=""
DEPOT_DNS=""

C_C=""
C_ST=""
C_L=""
C_O=""
C_OU=""
S_ADMIN=""
AUTH_USER=""

if [ -f "$STATE_FILE" ]; then
  . "$STATE_FILE"
fi

save_state() {
  cat > "$STATE_FILE" <<EOF
NET_DONE=$NET_DONE
STORAGE_DONE=$STORAGE_DONE
SSL_DONE=$SSL_DONE
DEPOT_FQDN="${DEPOT_FQDN}"
DEPOT_IP="${DEPOT_IP}"
DEPOT_GATEWAY="${DEPOT_GATEWAY}"
DEPOT_DNS="${DEPOT_DNS}"
C_C="${C_C}"
C_ST="${C_ST}"
C_L="${C_L}"
C_O="${C_O}"
C_OU="${C_OU}"
S_ADMIN="${S_ADMIN}"
AUTH_USER="${AUTH_USER}"
EOF
  chmod 600 "$STATE_FILE"
}

status_text() {
  [ "$1" -eq 1 ] && echo "DONE" || echo "PENDING"
}

clear
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}   VCF Offline Depot Wizard (for Photon OS 5)               ${NC}"
echo -e "${GREEN}============================================================${NC}"

# ---------------------------------------------------------------------------
# 1. Show current status FIRST
# ---------------------------------------------------------------------------

echo -e "\n${CYAN}--- Current status ---${NC}"
echo "1) Network config     : $(status_text "$NET_DONE")"
echo "2) Storage/httpd      : $(status_text "$STORAGE_DONE")"
echo "3) SSL + Apache       : $(status_text "$SSL_DONE")"

NEXT=""
[ "$NET_DONE" -eq 0 ] && NEXT="1"
[ "$NET_DONE" -eq 1 ] && [ "$STORAGE_DONE" -eq 0 ] && NEXT="2"
[ "$NET_DONE" -eq 1 ] && [ "$STORAGE_DONE" -eq 1 ] && [ "$SSL_DONE" -eq 0 ] && NEXT="3"

if [ -n "$NEXT" ]; then
  echo "Suggested next step: $NEXT"
else
  echo "All steps complete."
fi

echo
read -p "Select step to run (1=Network, 2=Storage, 3=SSL+Apache): " ACTION

# ---------------------------------------------------------------------------
# 2. Functions
# ---------------------------------------------------------------------------

configure_network() {
  echo -e "\n${CYAN}--- Network config ---${NC}"

  read -p "Enter Hostname (FQDN) [${DEPOT_FQDN:-depot.rainpole.io}]: " TMP
  DEPOT_FQDN=${TMP:-${DEPOT_FQDN:-depot.rainpole.io}}

  read -p "Enter IP Address (CIDR) [${DEPOT_IP:-172.16.10.14/24}]: " TMP
  DEPOT_IP=${TMP:-${DEPOT_IP:-172.16.10.14/24}}

  read -p "Enter Gateway [${DEPOT_GATEWAY:-172.16.10.1}]: " TMP
  DEPOT_GATEWAY=${TMP:-${DEPOT_GATEWAY:-172.16.10.1}}

  read -p "Enter DNS [${DEPOT_DNS:-172.16.10.4 172.16.10.5}]: " TMP
  DEPOT_DNS=${TMP:-${DEPOT_DNS:-172.16.10.4 172.16.10.5}}

  save_state

  echo -e "\n${GREEN}Applying System Network Config...${NC}"
  echo -e "${YELLOW}WARNING:${NC} If you are connected via SSH and change the IP, your session WILL drop."
  echo "Current connection: $SSH_CONNECTION"
  read -p "Proceed with network restart? [y/N]: " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Network configuration skipped."
    return
  fi

  cat <<EOF > /etc/systemd/network/10-static-en.network
[Match]
Name=eth0
[Network]
Address=$DEPOT_IP
Gateway=$DEPOT_GATEWAY
DNS=$DEPOT_DNS
EOF

  chmod 644 /etc/systemd/network/10-static-en.network
  hostnamectl set-hostname "$DEPOT_FQDN"
  systemctl restart systemd-networkd
  systemctl restart systemd-resolved

  NET_DONE=1
  save_state

  echo -e "${GREEN}Network configuration complete.${NC}"
}

configure_storage() {
  echo -e "\n${CYAN}--- Storage / httpd ---${NC}"
  lsblk
  echo -e "${RED}WARNING: The disk selected below will be FORMATTED.${NC}"
  read -p "Enter Disk Device (e.g., /dev/sdb): " DEPOT_DISK
  if [ -z "$DEPOT_DISK" ]; then
    echo "Error: Disk required."
    exit 1
  fi

  echo -e "${GREEN}Installing Packages (httpd, tar, jq)...${NC}"
  tdnf install httpd tar jq --assumeyes

  echo -e "${GREEN}Formatting Storage...${NC}"
  mkdir -p /var/www/html
  mkfs.ext4 "$DEPOT_DISK"
  if ! grep -q "$DEPOT_DISK" /etc/fstab; then
    echo "$DEPOT_DISK /var/www/html ext4 defaults 1 1" >> /etc/fstab
  fi
  mount -a

  STORAGE_DONE=1
  save_state

  echo -e "${GREEN}Storage and httpd installation complete.${NC}"
}

configure_ssl_and_apache() {
  echo -e "\n${CYAN}--- SSL Cert + Apache ---${NC}"

  echo -e "\n${CYAN}--- SSL Mode ---${NC}"
  echo "1) Self-Signed (lab/test, generate key+cert here)"
  echo "2) CSR for External CA / VMCA (manual upload of signed CRT)"
  echo "3) Upload existing Certificate & Key (e.g., Let's Encrypt)"
  read -p "Select [1]: " SSL_OPT; SSL_OPT=${SSL_OPT:-1}

  mkdir -p "$CERT_DIR"
  CERT_IP=$(echo "$DEPOT_IP" | cut -d'/' -f1)

  case "$SSL_OPT" in
    1|2)
      echo -e "\n${CYAN}--- Certificate Subject ---${NC}"
      read -p "Country [${C_C:-SE}]: " TMP;       C_C=${TMP:-${C_C:-SE}}
      read -p "State [${C_ST:-Stockholm}]: " TMP; C_ST=${TMP:-${C_ST:-Stockholm}}
      read -p "City [${C_L:-Stockholm}]: " TMP;    C_L=${TMP:-${C_L:-Stockholm}}
      read -p "Org [${C_O:-Rainpole}]: " TMP;      C_O=${TMP:-${C_O:-Rainpole}}
      read -p "Unit [${C_OU:-IT}]: " TMP;          C_OU=${TMP:-${C_OU:-IT}}
      read -p "Admin Email [${S_ADMIN:-operations@rainpole.io}]: " TMP; S_ADMIN=${TMP:-${S_ADMIN:-operations@rainpole.io}}
      read -p "Apache Auth Username [${AUTH_USER:-admin}]: " TMP; AUTH_USER=${TMP:-${AUTH_USER:-admin}}

      save_state

      echo -e "${GREEN}Generating key and CSR config...${NC}"
      openssl genpkey -out "$CERT_DIR/server.key" -algorithm RSA \
        -pkeyopt rsa_keygen_bits:2048

      cat << EOF > "$CERT_DIR/conf.cfg"
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

      echo -e "${YELLOW}Generating CSR...${NC}"
      openssl req -new \
        -key "$CERT_DIR/server.key" \
        -out "$CERT_DIR/request.csr" \
        -config "$CERT_DIR/conf.cfg"

      if [ "$SSL_OPT" == "1" ]; then
        echo -e "${YELLOW}Self-Signing CSR for 365 days...${NC}"
        openssl x509 -req -days 365 \
          -in "$CERT_DIR/request.csr" \
          -signkey "$CERT_DIR/server.key" \
          -out "$CERT_DIR/server.crt"
      else
        echo -e "${RED}ACTION REQUIRED:${NC}"
        echo "  Sign $CERT_DIR/request.csr with your External CA or VMCA."
        echo "  Save the resulting certificate chain as: $CERT_DIR/server.crt"
        while true; do
          read -p "Press Enter when $CERT_DIR/server.crt exists..."
          [ -f "$CERT_DIR/server.crt" ] && break || echo "File not found."
        done
      fi
      ;;
    3)
      echo -e "\n${CYAN}--- Configuration ---${NC}"
      read -p "Admin Email [${S_ADMIN:-operations@rainpole.io}]: " TMP
      S_ADMIN=${TMP:-${S_ADMIN:-operations@rainpole.io}}
      
      # Sanitize email
      S_ADMIN=$(echo "$S_ADMIN" | tr -d ' ')

      echo -e "\n${YELLOW}--- Upload Instructions ---${NC}"
      echo "1. Open a terminal on your laptop."
      printf "2. Upload your files to: ${CYAN}%s/${NC}\n" "$CERT_DIR"
      echo
      echo "I will automatically detect 'privkey.pem' and 'fullchain.pem' and rename them."
      echo "Waiting for files..."

      while true; do
        # Check for Let's Encrypt names OR standard names
        if [[ -f "$CERT_DIR/privkey.pem" && -f "$CERT_DIR/fullchain.pem" ]] || \
           [[ -f "$CERT_DIR/server.key" && -f "$CERT_DIR/server.crt" ]]; then
             
             echo -e "\n${GREEN}Files detected!${NC}"
             ls -lh "$CERT_DIR" | grep -E 'pem|key|crt'
             echo
             read -p "Press Enter to rename and process these files..." confirm
             
             # Now perform the rename
             if [ -f "$CERT_DIR/privkey.pem" ]; then 
                echo "Renaming privkey.pem -> server.key"
                mv "$CERT_DIR/privkey.pem" "$CERT_DIR/server.key"
             fi
             if [ -f "$CERT_DIR/fullchain.pem" ]; then 
                echo "Renaming fullchain.pem -> server.crt"
                mv "$CERT_DIR/fullchain.pem" "$CERT_DIR/server.crt"
             fi
             
             if [ -f "$CERT_DIR/server.key" ] && [ -f "$CERT_DIR/server.crt" ]; then
                  echo -e "${GREEN}Files are ready.${NC}"
                  break
             else
                  echo -e "${RED}Error: Files missing after rename. Please re-upload.${NC}"
             fi
        fi
        sleep 2
      done

      read -p "Apache Auth Username [${AUTH_USER:-admin}]: " TMP; AUTH_USER=${TMP:-${AUTH_USER:-admin}}
      save_state
      ;;
    *)
      echo "Invalid SSL option."
      exit 1
      ;;
  esac

  # ----- Common Apache config -----
  echo -e "${GREEN}Configuring Apache...${NC}"

  # 1. INSTALL CERTIFICATES (Use COPY instead of MOVE for reliability)
  # We use 'cp -f' to force overwrite and ensure correct SELinux context inheritance
  if [ -f "$CERT_DIR/server.key" ] && [ -f "$CERT_DIR/server.crt" ]; then
      cp -f "$CERT_DIR/server.key" /etc/httpd/conf/
      cp -f "$CERT_DIR/server.crt" /etc/httpd/conf/
      echo "Certificates installed to /etc/httpd/conf/."
  else
      echo -e "${RED}ERROR: Certificates not found in $CERT_DIR! Cannot proceed.${NC}"
      exit 1
  fi
  
  chmod 0640 /etc/httpd/conf/server.key /etc/httpd/conf/server.crt
  chown root:apache /etc/httpd/conf/server.key /etc/httpd/conf/server.crt

  # 2. Sanitize Variables
  S_ADMIN=$(echo "$S_ADMIN" | tr -d ' ')
  AUTH_USER=$(echo "$AUTH_USER" | tr -d ' ')

  # 3. Enable Modules
  sed -i 's|#LoadModule ssl_module|LoadModule ssl_module|' "$HTTPD_CONF"
  sed -i 's|#LoadModule socache_shmcb_module|LoadModule socache_shmcb_module|' "$HTTPD_CONF"
  sed -i 's|#Include conf/extra/httpd-ssl.conf|Include conf/extra/httpd-ssl.conf|' "$HTTPD_CONF"

  # 4. Configure DocumentRoot
  sed -i 's|DocumentRoot "/etc/httpd/html"|DocumentRoot "/var/www/html"|' "$SSL_CONF"
  sed -i 's|DocumentRoot "/etc/httpd/html"|DocumentRoot "/var/www/html"|' "$HTTPD_CONF"
  sed -i 's|<Directory "/etc/httpd/html">|<Directory "/var/www/html">|' "$HTTPD_CONF"

  # 5. FORCE UPDATE ServerAdmin/Name
  sed -i "s|^ServerAdmin .*|ServerAdmin $S_ADMIN|" "$SSL_CONF"
  sed -i "s|^ServerName .*|ServerName $DEPOT_FQDN:443|" "$SSL_CONF"

  # 6. Fix permissions
  if ! sed -n '/<Directory "\/var\/www\/html">/,/<\/Directory>/p' "$HTTPD_CONF" | grep -q 'Require all granted'; then
    sed -i '/<Directory "\/var\/www\/html">/,/<\/Directory>/{
s/Require all denied/Require all granted/;
}' "$HTTPD_CONF"
    if ! sed -n '/<Directory "\/var\/www\/html">/,/<\/Directory>/p' "$HTTPD_CONF" | grep -q 'Require all granted'; then
      sed -i '/<Directory "\/var\/www\/html">/a\    Require all granted' "$HTTPD_CONF"
    fi
  fi

  # 7. RESET VCF BLOCKS
  sed -i '/<Directory \/var\/www\/html\/PROD\/COMP>/,${/<\/VirtualHost>/!d}' "$SSL_CONF"

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
  sed -i '/<\/VirtualHost>/e cat /tmp/vcf_blocks.conf' "$SSL_CONF"
  rm -f /tmp/vcf_blocks.conf

  echo -e "${YELLOW}Set Password for $AUTH_USER:${NC}"
  htpasswd -c /etc/httpd/conf/.htpasswd "$AUTH_USER"
  chown apache /etc/httpd/conf/.htpasswd
  chmod 0400 /etc/httpd/conf/.htpasswd

  SAVE="/etc/systemd/scripts/ip4save"
  if ! grep -q "dport 443" "$SAVE"; then
    sed -i '/COMMIT/i -A INPUT -p tcp -m tcp --dport 443 -j ACCEPT' "$SAVE"
  fi
  if ! grep -q "dport 22" "$SAVE"; then
    sed -i '/COMMIT/i -A INPUT -p tcp -m tcp --dport 22 -j ACCEPT' "$SAVE"
  fi
  systemctl restart iptables

  httpd -t
  systemctl enable httpd
  systemctl restart httpd

  rm -f /var/www/html/index.html

  echo -e "${GREEN}Applying VCF permissions to DocumentRoot...${NC}"
  chown -R apache:apache /var/www/html/
  find /var/www/html -type d -exec chmod 0500 {} \;
  find /var/www/html -type f -exec chmod 0400 {} \;

  SSL_DONE=1
  save_state

  echo -e "${GREEN}SSL and Apache configuration complete.${NC}"
}

# ---------------------------------------------------------------------------
# 3. Dispatch based on selection
# ---------------------------------------------------------------------------

case "$ACTION" in
  1) configure_network ;;
  2) configure_storage ;;
  3) configure_ssl_and_apache ;;
  *) echo "Invalid selection." ;;
esac
