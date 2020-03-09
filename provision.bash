#!/bin/bash -x
PATH=/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin
set -e -u

yum update --exclude="kernel*" --exclude "grub2*" --exclude "selinux-*" -y
yum install -y dnf

# DEVICE=/dev/xvdb
# RELEASE="8.1-1.1911.0.8"
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

dnf --installroot=$ROOTFS --nogpgcheck --setopt=install_weak_deps=False \
   -y install audit authselect basesystem bash biosdevname coreutils \
   cronie curl dnf dnf-plugins-core dnf-plugin-spacewalk dracut-config-generic \
   dracut-config-rescue e2fsprogs filesystem firewalld glibc grub2 grubby hostname \
   initscripts iproute iprutils iputils irqbalance kbd kernel kernel-tools \
   kexec-tools less linux-firmware lshw lsscsi ncurses network-scripts \
   openssh-clients openssh-server passwd plymouth policycoreutils prefixdevname \
   procps-ng  rng-tools rootfiles rpm rsyslog selinux-policy-targeted setup \
   shadow-utils sssd-kcm sudo systemd util-linux vim-minimal xfsprogs \
   chrony cloud-init

cat > $ROOTFS/etc/resolv.conf << HABR
nameserver 169.254.169.253
HABR

cat > $ROOTFS/etc/sysconfig/network << HABR
NETWORKING=yes
NOZEROCONF=yes
HABR

cat > $ROOTFS/etc/sysconfig/network-scripts/ifcfg-eth0  << HABR
DEVICE=eth0
ONBOOT=yes
BOOTPROTO=dhcp
HABR

cat > $ROOTFS/etc/fstab << HABR
LABEL=root / xfs defaults,relatime 1 1
HABR

sed -i  "s/cloud-user/centos/" $ROOTFS/etc/cloud/cloud.cfg
echo "server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4" >> $ROOTFS/etc/chrony.conf
sed -i "/^pool /d" $ROOTFS/etc/chrony.conf
sed -i "s/^AcceptEnv/# \0/" $ROOTFS/etc/ssh/sshd_config

cat > $ROOTFS/etc/default/grub << HABR
GRUB_TIMEOUT=1
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="crashkernel=auto console=ttyS0,115200n8 console=tty0 net.ifnames=0 biosdevname=0"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
HABR

chroot $ROOTFS fips-mode-setup --enable
chroot $ROOTFS grub2-mkconfig -o /boot/grub2/grub.cfg
chroot $ROOTFS grub2-install $DEVICE

chroot $ROOTFS systemctl enable network.service
chroot $ROOTFS systemctl enable sshd.service
chroot $ROOTFS systemctl enable cloud-init.service
chroot $ROOTFS systemctl mask tmp.mount
umount $ROOTFS/{proc,sys,dev,run}

dnf --installroot=$ROOTFS clean all
truncate -c -s 0 $ROOTFS/var/log/*.log
rm -rf $ROOTFS/var/lib/dnf/*
touch $ROOTFS/.autorelabel
sync
umount $ROOTFS

echo "Well Done!"
