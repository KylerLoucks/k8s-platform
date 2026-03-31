#!/bin/bash
apt-get update && apt-get upgrade -y && apt-get install nvme-cli
hostnamectl set-hostname openvpn       

#Install cfn-init equivalent (not needed for Terraform, but keeping structure)
apt-get -y install python3-pip

#Openvpn volume mount for /usr/local/openvpn_as
mkdir /usr/local/openvpn_as
# EBS sdf mount is the device which will be mounted on /usr/local/openvpn_as
if ! $(mount | grep -q /mnt) ; then
    # Detected NVME drives
    # They do not always have a consistent drive number, this will scan for the drives slot in the hypervisor
    # and mount the correct ones, with sda1 always being the base disk and sdb being the extra, larger, disk
    if lshw | grep nvme &>/dev/null; then
        for blkdev in $(nvme list | awk '/^\/dev/ { print $1 }'); do
            mapping=$(nvme id-ctrl --raw-binary "$blkdev" | cut -c3073-3104 | tr -s ' ' | sed 's/ $//g')
            if [[ $mapping == "sda1" ]]; then
                echo "$blkdev is $mapping skipping..."
            elif [[ $mapping == "sdf" ]]; then
                echo "$blkdev is $mapping formatting and mounting..."
                mkfs.xfs $blkdev
                echo "$blkdev    /usr/local/openvpn_as    xfs    defaults    0    1" >> /etc/fstab
                mount $blkdev
            else
                echo "detected unknown drive letter $blkdev: $mapping. Skipping..."
            fi
        done
    else
        echo "Configuring /dev/xvdf..."
        mkfs.xfs /dev/xvdf
        echo "/dev/xvdf    /usr/local/openvpn_as    xfs    defaults    0    1" >> /etc/fstab
        mount /dev/xvdf
    fi
else
  echo "detected drive already mounted to /mnt, skipping mount..."
  lsblk | grep mnt
fi

# OpenVPN
apt update && apt -y install ca-certificates wget net-tools gnupg
wget https://as-repository.openvpn.net/as-repo-public.asc -qO /etc/apt/trusted.gpg.d/as-repository.asc
echo "deb [arch=arm64 signed-by=/etc/apt/trusted.gpg.d/as-repository.asc] http://as-repository.openvpn.net/as/debian jammy main">/etc/apt/sources.list.d/openvpn-as-repo.list
apt update && apt -y install openvpn-as

echo "export PATH=$PATH:/usr/local/openvpn_as/scripts" > /etc/profile.d/openvpn.sh
source /etc/profile.d/openvpn.sh

sacli stop
echo -e "LOG_ROTATE_LENGTH=1000000\n" >> /usr/local/openvpn_as/etc/as.conf
(crontab -l 2>/dev/null; echo "0 4 * * * rm /var/log/openvpnas.log.{15..1000} >/dev/null 2>&1") | crontab -

sacli --key "host.name" --value "${elastic_ip}" ConfigPut
sacli --key "vpn.client.routing.reroute_dns" --value "false" ConfigPut
sacli --key "vpn.client.routing.reroute_gw" --value "false" ConfigPut
sacli --key "vpn.server.routing.private_network.0" --value "${vpc_cidr}" ConfigPut
sacli --key "cs.tls_version_min" --value "1.2" ConfigPut
sacli --key "ssl_api.tls_version_min" --value "1.2" ConfigPut

sacli start
sacli ConfigQuery

# Set admin password
sacli --user openvpn --new_pass ${openvpn_admin_password} SetLocalPassword

# Reboot to complete setup
reboot