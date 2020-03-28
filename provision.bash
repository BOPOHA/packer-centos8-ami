#!/bin/bash -x
PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin
set -e -u

yum update --exclude="kernel*" --exclude "grub2*" --exclude "selinux-*" -y
yum install -y dnf

# DEVICE=/dev/xvdb
# RELEASE="8.1-1.1911.0.9"
echo "ENV variables from packer template: dev=$DEVICE release=$RELEASE"

ROOTFS=/rootfs
parted -s ${DEVICE} mktable gpt
parted -s ${DEVICE} mkpart primary ext2 1 2
parted -s ${DEVICE} set 1 bios_grub on
parted -s ${DEVICE} mkpart primary xfs 2 100%
sync
partprobe ${DEVICE}
sleep 1
mkfs.xfs -L root ${DEVICE}2
mkdir -p $ROOTFS
mount ${DEVICE}2 $ROOTFS

mkdir $ROOTFS/{proc,sys,dev,run}
mount -t proc /proc $ROOTFS/proc
mount --bind /sys $ROOTFS/sys
mount --bind /dev $ROOTFS/dev
mount --bind /run $ROOTFS/run

PKGSURL=http://mirror.centos.org/centos/8/BaseOS/x86_64/os/Packages
rpm --root=$ROOTFS --initdb
rpm --root=$ROOTFS -ivh \
  $PKGSURL/centos-release-$RELEASE.el8.x86_64.rpm \
  $PKGSURL/centos-gpg-keys-$RELEASE.el8.noarch.rpm \
  $PKGSURL/centos-repos-$RELEASE.el8.x86_64.rpm

# Instal only Core Mandatory packages, without man-db, tuned, yum, dnf-plugin-spacewalk.
# Something like here:
#   dnf groupinstall core -e man-db  -e tuned -e yum
# Look more here: `dnf group info core`
dnf --installroot=$ROOTFS --nogpgcheck --setopt=install_weak_deps=False -y install \
    audit \
    basesystem \
    bash \
    coreutils \
    cronie \
    curl \
    dnf \
    e2fsprogs \
    filesystem \
    firewalld \
    glibc \
    grubby \
    hostname \
    initscripts \
    iproute \
    iprutils \
    iputils \
    irqbalance \
    kbd \
    kexec-tools \
    less \
    ncurses \
    NetworkManager \
    openssh-clients \
    openssh-server \
    parted \
    passwd \
    plymouth \
    policycoreutils \
    procps-ng \
    rng-tools \
    rootfiles \
    rpm \
    rsyslog \
    selinux-policy-targeted \
    setup \
    sg3_utils \
    sg3_utils-libs \
    shadow-utils \
    sssd-common \
    sssd-kcm \
    sudo \
    systemd \
    util-linux \
    vim-minimal \
    xfsprogs

# Install kernel and bootloaders:
dnf --installroot=$ROOTFS --nogpgcheck --setopt=install_weak_deps=False -y install \
    dracut-config-generic \
    epel-release \
    grub2 \
    kernel \
    linux-firmware \
    lvm2

# Install pkgs for my custom needs:
dnf --installroot=$ROOTFS --nogpgcheck --setopt=install_weak_deps=False -y install \
    atop \
    authselect \
    chrony \
    cloud-init \
    cloud-utils-growpart\
    screen \
    vim-enhanced

# it will be configured with dhcpclient on boot
#cat > $ROOTFS/etc/resolv.conf << HABR
#nameserver 169.254.169.253
#
#HABR

cat > $ROOTFS/etc/chrony.conf << HABR
server 169.254.169.123 prefer iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
keyfile /etc/chrony.keys
leapsectz right/UTC

HABR

cat > $ROOTFS/etc/sysconfig/network << HABR
NETWORKING=yes
NOZEROCONF=yes
NETWORKING_IPV6=yes
IPV6_AUTOCONF=yes
PERSISTENT_DHCLIENT=1

HABR

cat > $ROOTFS/etc/sysconfig/network-scripts/ifcfg-eth0  << HABR
DEVICE=eth0
DHCPV6C=yes
IPV6INIT=yes
IPV6_FAILURE_FATAL=no
ONBOOT=yes
BOOTPROTO=dhcp
TYPE=Ethernet
USERCTL=no

HABR

cat > $ROOTFS/etc/cloud/cloud.cfg.d/99-custom-networking.cfg << HABR
network:
  config: disabled

HABR

cat > $ROOTFS/etc/fstab << HABR
LABEL=root / xfs defaults,relatime 1 1

HABR

cat >> $ROOTFS/etc/dnf/dnf.conf << HABR
install_weak_deps=False

HABR

sed -i "s/cloud-user/centos/"   $ROOTFS/etc/cloud/cloud.cfg
sed -i "s/^AcceptEnv/# \0/"     $ROOTFS/etc/ssh/sshd_config
sed -i "s/^X11Forwarding/# \0/" $ROOTFS/etc/ssh/sshd_config

# Disable unneeded GSS-API/Kerberos
sed -i "s/^GSSAPI/# \0/" $ROOTFS/etc/ssh/sshd_config

# ed25519 is not allowed by FIPS policy
sed -i "s/^HostKey \/etc\/ssh\/ssh_host_ed25519_key/# \0/" $ROOTFS/etc/ssh/sshd_config

cat > $ROOTFS/etc/default/grub << HABR
GRUB_TIMEOUT=1
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="crashkernel=auto console=ttyS0,115200n8 console=tty0 net.ifnames=0 biosdevname=0 nvme_core.io_timeout=4294967295 fips=1"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
HABR

chroot $ROOTFS fips-mode-setup --enable
chroot $ROOTFS grub2-mkconfig -o /boot/grub2/grub.cfg
chroot $ROOTFS grub2-install $DEVICE

chroot $ROOTFS systemctl enable sshd.service
chroot $ROOTFS systemctl enable cloud-init.service
chroot $ROOTFS systemctl mask tmp.mount
sync
umount $ROOTFS/{proc,sys,dev,run}

dnf --installroot=$ROOTFS clean all
truncate -c -s 0 $ROOTFS/var/log/*.log
rm -rf $ROOTFS/var/lib/dnf/*
touch $ROOTFS/.autorelabel
sync
umount $ROOTFS

echo "Well Done!"
