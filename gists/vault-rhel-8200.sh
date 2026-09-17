# ============================================================
# COMO ROOT (o con sudo)
# ============================================================

# Crear grupo vault
sudo groupadd vault

# Crear usuario vault
sudo useradd --system --gid vault --home-dir /opt/vault --create-home --shell /sbin/nologin vault

# Distribución de almacenamiento:
# - /apps/vault/data: punto de montaje dedicado de 100 GB por nodo para Raft.
#   Debe ser almacenamiento local (no compartido) y estar montado antes de arrancar Vault.
# - /opt/vault/tls y /opt/vault/vault.hclic: certificados TLS y licencia en el FS de sistema.
# - /etc/vault.d: configuración de Vault en el FS de sistema.
# - Logs operativos: systemd/journald. Audit logs: destino separado, nunca /apps/vault/data.
# Crear directorios necesarios
sudo mkdir -p /apps/vault/data
sudo mkdir -p /opt/vault/tls   
sudo mkdir -p /etc/vault.d

# Los logs operativos se envían a stdout/stderr y systemd los almacena en journald.
# No se crea un fichero local de log para evitar duplicar la gestión y la rotación.

# Establecer permisos para directorio de datos
sudo chown -R vault:vault /apps/vault/data
sudo chmod -R 755 /apps/vault/data
sudo chmod -R 755 /opt/vault/

# Establecer permisos para el directorio de configuración
sudo chown root:root /etc/vault.d
sudo chmod 755 /etc/vault.d

# ============================================================
# DESCARGA E INSTALACIÓN DEL BINARIO - CON ROOT
# ============================================================
# El binario no es secreto: descargarlo como usuario vault obliga a un su -
# que, desde ec2-user, pide un password que no existe, y después un sudo su
# que vault no puede hacer (no está en sudoers). En este gist el usuario
# además tiene /sbin/nologin, así que su - vault falla incluso como root.
# Quedarse en root.
#
# No usar mv /tmp/vault: en RHEL 9 (SELinux enforcing) el fichero conserva
# el contexto user_tmp_t y systemd no puede ejecutarlo.

cd /tmp
VAULT_VERSION="2.1.0"

wget "https://releases.hashicorp.com/vault/${VAULT_VERSION}+ent/vault_${VAULT_VERSION}+ent_linux_amd64.zip"
unzip "vault_${VAULT_VERSION}+ent_linux_amd64.zip"

# Licencia: previamente scp al home (p. ej. ~/vault.hclic). Hacer este paso
# antes de arrancar Vault.

sudo install -o root -g vault -m 640 ~/vault.hclic /opt/vault/vault.hclic
rm ~/vault.hclic

install -o root -g root -m 0755 /tmp/vault /usr/local/bin/vault
restorecon -v /usr/local/bin/vault
ln -sf /usr/local/bin/vault /usr/bin/vault

# ============================================================
# CERTIFICADOS TLS
# ============================================================
# Camino previsto: el cliente (o la PKI corporativa) genera los materiales y
# se suben al servidor. En el nodo solo deben quedar:
#   /opt/vault/tls/vault-ca.pem      CA pública
#   /opt/vault/tls/vault-cert.pem    certificado de este nodo
#   /opt/vault/tls/vault-key.pem     clave privada de este nodo
# El certificado (SAN) debe incluir, como mínimo:
#   - 127.0.0.1          (vault operator / CLI en localhost)
#   - FQDN de este host  (<host-fqdn>)
#   - FQDN del balanceador / VIP (<lb-fqdn>)
# Los clientes se conectan por nombre, no por IP. Incluir IPs en el SAN solo
# tiene sentido en un laboratorio sin DNS.
# La clave privada de la CA no se copia al servidor.
#
# PoC: si el cliente aún no entrega certificados, sirve una CA de laboratorio
# y un certificado firmado por ella, generados en este nodo. Sustituir
# <host-fqdn> y <lb-fqdn> y descomentar. OpenSSL 3 (RHEL 9) copia el SAN del
# CSR con -copy_extensions copy. Los permisos se aplican más abajo, en
# PERMISOS FINALES.

# openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
#   -keyout /opt/vault/tls/vault-ca-key.pem \
#   -out /opt/vault/tls/vault-ca.pem \
#   -subj "/CN=Vault Lab CA"
#
# openssl req -newkey rsa:4096 -sha256 -nodes \
#   -keyout /opt/vault/tls/vault-key.pem \
#   -out /tmp/vault.csr \
#   -subj "/CN=<host-fqdn>" \
#   -addext "subjectAltName=DNS:<host-fqdn>,DNS:<lb-fqdn>,IP:127.0.0.1"
#
# openssl x509 -req -in /tmp/vault.csr \
#   -CA /opt/vault/tls/vault-ca.pem \
#   -CAkey /opt/vault/tls/vault-ca-key.pem \
#   -CAcreateserial -days 365 -sha256 \
#   -copy_extensions copy \
#   -out /opt/vault/tls/vault-cert.pem
#
# rm -f /tmp/vault.csr
# chmod 600 /opt/vault/tls/vault-ca-key.pem /opt/vault/tls/vault-key.pem

# ============================================================
# CONFIGURACIÓN vault.hcl
# ============================================================
# Un solo nodo: no hay retry_join ni VIP/NLB.
#   cluster_addr = IP privada del nodo (tráfico Raft :8201, no se publica a Internet)
#   api_addr     = IP pública (o DNS) por la que los clientes alcanzan la API :8200
# El listener en 0.0.0.0 escucha en todas las interfaces; cluster_addr y api_addr
# solo son las direcciones que Vault anuncia. Sustituir <private-ip> y <public-ip>.
# En un cluster de 3 nodos se añadirían bloques retry_join y api_addr pasaría a ser el VIP.
# El certificado TLS debe incluir en SAN 127.0.0.1, el FQDN de este host y el FQDN
# del balanceador (no las IPs, salvo en un laboratorio sin DNS).

cat << 'EOFHCL' > /etc/vault.d/vault.hcl
ui = true
disable_mlock = true

storage "raft" {
  path    = "/apps/vault/data"
  node_id = "vault-node-1"
}

cluster_addr = "https://<private-ip>:8201"
api_addr     = "https://<public-ip>:8200"

listener "tcp" {
  address            = "0.0.0.0:8200"
  cluster_address    = "0.0.0.0:8201"
  tls_disable        = false
  tls_cert_file      = "/opt/vault/tls/vault-cert.pem"
  tls_key_file       = "/opt/vault/tls/vault-key.pem"
  tls_client_ca_file = "/opt/vault/tls/vault-ca.pem"
}

license_path = "/opt/vault/vault.hclic"
EOFHCL

# Cluster de 3 nodos (comentado). En cada nodo: node_id y cluster_addr propios
# (FQDN de ese host); api_addr es el FQDN del balanceador. El SAN del cert
# incluye 127.0.0.1, <host-fqdn> y <lb-fqdn>.
#
# cat << 'EOFHCL' > /etc/vault.d/vault.hcl
# ui = true
# disable_mlock = true
#
# storage "raft" {
#   path    = "/apps/vault/data"
#   node_id = "vault-node-1"
#
#   retry_join {
#     leader_api_addr       = "https://<node-1-fqdn>:8200"
#     leader_tls_servername = "<node-1-fqdn>"
#     leader_ca_cert_file   = "/opt/vault/tls/vault-ca.pem"
#   }
#   retry_join {
#     leader_api_addr       = "https://<node-2-fqdn>:8200"
#     leader_tls_servername = "<node-2-fqdn>"
#     leader_ca_cert_file   = "/opt/vault/tls/vault-ca.pem"
#   }
#   retry_join {
#     leader_api_addr       = "https://<node-3-fqdn>:8200"
#     leader_tls_servername = "<node-3-fqdn>"
#     leader_ca_cert_file   = "/opt/vault/tls/vault-ca.pem"
#   }
# }
#
# cluster_addr = "https://<host-fqdn>:8201"
# api_addr     = "https://<lb-fqdn>:8200"
#
# listener "tcp" {
#   address            = "0.0.0.0:8200"
#   cluster_address    = "0.0.0.0:8201"
#   tls_disable        = false
#   tls_cert_file      = "/opt/vault/tls/vault-cert.pem"
#   tls_key_file       = "/opt/vault/tls/vault-key.pem"
#   tls_client_ca_file = "/opt/vault/tls/vault-ca.pem"
# }
#
# license_path = "/opt/vault/vault.hclic"
# EOFHCL

# ============================================================
# SERVICIO SYSTEMD
# ============================================================

cat << 'VAULTSERVICE' > /etc/systemd/system/vault.service
[Unit]
Description=HashiCorp Vault Enterprise
Documentation=https://www.vaultproject.io/docs/
Requires=network-online.target
After=network-online.target
ConditionFileNotEmpty=/etc/vault.d/vault.hcl

[Service]
Type=notify
User=vault
Group=vault
StandardOutput=journal
StandardError=journal
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

# Endurecimiento básico del servicio (compatible con SELinux en enforcing)
NoNewPrivileges=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectHome=read-only
ProtectSystem=full
ReadWritePaths=/apps/vault/data

[Install]
WantedBy=multi-user.target
VAULTSERVICE

# ============================================================
# PERMISOS FINALES
# ============================================================

chown root:root /etc/vault.d
chown root:vault /etc/vault.d/vault.hcl
chmod 640 /etc/vault.d/vault.hcl

# Permisos de certificados y clave TLS
# Para esta PoC se mantienen permisos homogéneos. En producción se recomienda:
# - CA y certificado: root:root, modo 0644.
# - Clave privada: root:vault, modo 0640.
# Así Vault puede leer la clave, pero no sustituirla.
chown -R vault:vault /opt/vault/tls
chmod 750 /opt/vault/tls
find /opt/vault/tls -type f -name '*.pem' -exec chmod 640 {} \;

# Permisos de la licencia Enterprise
chown root:vault /opt/vault/vault.hclic
chmod 640 /opt/vault/vault.hclic

# ============================================================
# FIREWALL - puertos estándar de Vault 8200/8201
# ============================================================

firewall-cmd --permanent --add-port=8200/tcp    # API / listener
firewall-cmd --permanent --add-port=8201/tcp    # Cluster (Raft)
firewall-cmd --reload
firewall-cmd --list-ports

# ============================================================
# ARRANQUE Y VERIFICACIÓN
# ============================================================

vault version

systemctl daemon-reload
systemctl enable vault
systemctl start vault
systemctl status vault

# Consultar los logs operativos gestionados por systemd/journald
journalctl -u vault --no-pager -n 100
# Seguimiento en tiempo real: journalctl -u vault -f

# usar HTTPS ya que TLS está habilitado
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_CACERT=/opt/vault/tls/vault-ca.pem   # necesario para validar TLS

# Inicializar Vault (solo en el primer nodo)
vault operator init -key-shares=1 -key-threshold=1

export UNSEAL_TOKEN=<unseal_token>
export VAULT_TOKEN=<root_token>

# Dessellar Vault
vault operator unseal $UNSEAL_TOKEN

# ============================================================
# AUDITORÍA - CONFIGURACIÓN POSTERIOR
# ============================================================
# Los audit logs no son los logs operativos del servicio.
# Habilitar un audit device después de inicializar y desellar Vault, de acuerdo
# con la política de seguridad, rotación y envío al SIEM de la organización.
# No almacenar audit logs en /apps/vault/data: este filesystem queda reservado para Raft.
# Ejemplo local (solo si se proporciona almacenamiento separado y logrotate):
# vault audit enable file file_path=/var/log/vault_audit.log