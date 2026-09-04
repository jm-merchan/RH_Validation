#!/bin/bash
set -euo pipefail

# Packages required by the Vault gists (RHEL 9 AMIs ship curl, not wget/unzip).
dnf install -y wget unzip xfsprogs firewalld

# Dedicated Raft volume attached as /dev/sdf (Nitro: /dev/nvme1n1).
DATA_DEV=""
for candidate in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
  if [ -b "${candidate}" ]; then
    DATA_DEV="${candidate}"
    break
  fi
done

if [ -n "${DATA_DEV}" ]; then
  if ! blkid "${DATA_DEV}" >/dev/null 2>&1; then
    mkfs.xfs -L vaultdata "${DATA_DEV}"
  fi
  mkdir -p /apps/vault/data
  if ! grep -q 'LABEL=vaultdata' /etc/fstab; then
    echo 'LABEL=vaultdata /apps/vault/data xfs defaults,nofail 0 2' >> /etc/fstab
  fi
  mount -a
fi

# OS firewall as a second layer; SSH must stay open so gist firewall-cmd
# changes cannot lock you out. Security Group remains the primary control.
systemctl enable --now firewalld
firewall-cmd --permanent --add-service=ssh
firewall-cmd --reload
