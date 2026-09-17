# ============================================================
# PoC HTTP: tráfico sin cifrar. Usar sólo en una red aislada de laboratorio.
# ============================================================
# COMO ROOT (o con sudo)
# ============================================================

# Crear grupo vault
sudo groupadd vault

# Crear usuario vault
sudo useradd -g vault -d /opt/vault -s /bin/bash vault

# Distribución de almacenamiento:
# - /apps/vault/data: punto de montaje dedicado de 100 GB por nodo para Raft.
#   Debe ser almacenamiento local (no compartido) y estar montado antes de arrancar Vault.
# - /opt/vault/vault.hclic: licencia Enterprise en el FS de sistema.
# - /etc/vault.d: configuración de Vault en el FS de sistema.
# - Logs operativos: systemd/journald. Audit logs: destino separado, nunca /apps/vault/data.
# Crear directorios necesarios
sudo mkdir -p /apps/vault/data
sudo mkdir -p /etc/vault.d

# Los logs operativos se envían a stdout/stderr y systemd los almacena en journald.
# No se crea un fichero local de log para evitar duplicar la gestión y la rotación.

# Establecer permisos para directorio de datos
sudo chown -R vault:vault /apps/vault/data
sudo chmod -R 750 /apps/vault/data
sudo chmod -R 755 /opt/vault/

# Establecer permisos para el directorio de configuración
sudo chown root:root /etc/vault.d
sudo chmod 755 /etc/vault.d

# ============================================================
# DESCARGA E INSTALACIÓN DEL BINARIO - CON ROOT
# ============================================================
# El binario no es secreto: descargarlo como usuario vault obliga a un su -
# que, desde ec2-user, pide un password que no existe, y después un sudo su
# que vault no puede hacer (no está en sudoers). Quedarse en root.
#
# No usar mv /tmp/vault: en RHEL 9 (SELinux enforcing) el fichero conserva
# el contexto user_tmp_t y systemd no puede ejecutarlo.

cd /tmp
VAULT_VERSION="2.1.0"

wget "https://releases.hashicorp.com/vault/${VAULT_VERSION}+ent/vault_${VAULT_VERSION}+ent_linux_amd64.zip"
unzip "vault_${VAULT_VERSION}+ent_linux_amd64.zip"

# Licencia: previamente scp al home (p. ej. ~/vault.hclic). Hacer este paso
# antes de arrancar Vault.
sudo mkdir -p /opt/vault
sudo install -o root -g vault -m 640 ~/vault.hclic /opt/vault/vault.hclic
rm ~/vault.hclic

install -o root -g root -m 0755 /tmp/vault /usr/local/bin/vault
restorecon -v /usr/local/bin/vault
ln -sf /usr/local/bin/vault /usr/bin/vault
# Verificar que el binario se ha instalado correctamente
which vault
vault -v

#
# ============================================================
# CONFIGURACIÓN vault.hcl
# ============================================================
# Un solo nodo: no hay retry_join ni VIP/NLB.
#   cluster_addr = IP privada del nodo (tráfico Raft :8201, no se publica a Internet)
#   api_addr     = IP pública (o DNS) por la que los clientes alcanzan la API :8200
# El listener en 0.0.0.0 escucha en todas las interfaces; cluster_addr y api_addr
# solo son las direcciones que Vault anuncia. Sustituir <private-ip> y <public-ip>.
# En un cluster de 3 nodos se añadirían bloques retry_join y api_addr pasaría a ser el VIP.

cat << 'EOFHCL' > /etc/vault.d/vault.hcl
ui = true
disable_mlock = true

storage "raft" {
  path    = "/apps/vault/data"
  node_id = "vault-node-1"
}

cluster_addr = "http://<private-ip>:8201"
api_addr     = "http://<public-ip>:8200"

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable     = true
}

license_path = "/opt/vault/vault.hclic"
EOFHCL

# Cluster de 3 nodos (comentado). En cada nodo: node_id y cluster_addr propios;
# api_addr es el VIP/FQDN del balanceador. retry_join apunta a los tres peers.
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
#     leader_api_addr = "http://<node-1-fqdn>:8200"
#   }
#   retry_join {
#     leader_api_addr = "http://<node-2-fqdn>:8200"
#   }
#   retry_join {
#     leader_api_addr = "http://<node-3-fqdn>:8200"
#   }
# }
#
# cluster_addr = "http://<host-fqdn>:8201"
# api_addr     = "http://<lb-fqdn>:8200"
#
# listener "tcp" {
#   address         = "0.0.0.0:8200"
#   cluster_address = "0.0.0.0:8201"
#   tls_disable     = true
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
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
VAULTSERVICE

# ============================================================
# PERMISOS FINALES
# ============================================================

chown root:root /etc/vault.d
chown root:vault /etc/vault.d/vault.hcl
chmod 640 /etc/vault.d/vault.hcl

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

# usar HTTP únicamente para esta PoC en red aislada
export VAULT_ADDR=http://127.0.0.1:8200

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