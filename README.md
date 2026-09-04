# RH Validation — Vault Enterprise en RHEL 9 (AWS)

Laboratorio de un solo nodo: una instancia **RHEL 9** en `eu-central-1` y, sobre ella, **Vault Enterprise 2.1.0** instalado a mano. Terraform solo crea la máquina (VPC, EIP, SSH, disco Raft de 100 GiB). Vault no se provisiona con cloud-init: se sigue el gist HTTP o el gist TLS.

| Gist | Uso |
|------|-----|
| [`gists/vault-rhel-8200-http.sh`](gists/vault-rhel-8200-http.sh) | PoC en HTTP (`tls_disable = true`) |
| [`gists/vault-rhel-8200.sh`](gists/vault-rhel-8200.sh) | Misma PoC con TLS (certificados del cliente o self-signed de laboratorio) |

Security group: **22/tcp** y **8200/tcp** solo desde `allowed_ssh_cidr`. **8201** (Raft) no se publica. Usuario SSH: `ec2-user`.

Un solo nodo:

- `cluster_addr` → IP **privada** (`:8201`)
- `api_addr` → IP **pública** (`:8200`)

La licencia `*.hclic` y la clave `ssh/*.pem` no van a git.

## 1. Levantar la instancia

Credenciales AWS en el entorno. Si tu IP pública cambia, actualiza `allowed_ssh_cidr` en `variables.tf`.

```bash
terraform init
terraform apply
```

## 2. SSH

```bash
eval "$(terraform output -raw ssh)"
```

Equivale a `ssh -i <pem> ec2-user@<elastic-ip>`.

## 3. Copiar la licencia

Por defecto el fichero local es `vault-telefonica.hclic` (variable `license_file`). Lo deja en `~/vault.hclic` del host:

```bash
eval "$(terraform output -raw scp_license)"
```

En el host (como `ec2-user` o root), **antes de arrancar Vault**:

```bash
sudo mkdir -p /opt/vault
sudo install -o root -g vault -m 640 ~/vault.hclic /opt/vault/vault.hclic
rm ~/vault.hclic
```

Esos tres comandos están también en los gists. La licencia debe ser compatible con **2.1.0+ent** (una clave con el módulo `agentic-iam` no arranca en 2.0.3).

## 4. Instalar Vault

En la instancia, como root, pega el gist HTTP o el TLS. El `user_data` ya deja `wget`, `unzip`, `firewalld` y `/apps/vault/data` montado.

Tras HTTP, se puede pasar a HTTPS generando CA + cert (SAN: IP privada, IP pública, `127.0.0.1`), cambiando `vault.hcl` a `https://` y `tls_disable = false`, y reiniciando. No hace falta volver a `vault operator init`; sí un `unseal`.

CLI con TLS:

```bash
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_CACERT=/opt/vault/tls/vault-ca.pem
vault status
```

## 5. Outputs útiles

```bash
terraform output public_ip
terraform output private_ip
terraform output ssh
terraform output scp_license
```

## 6. Destruir

```bash
terraform destroy
```
