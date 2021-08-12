#!/bin/bash
set -xeu

#to check if running as root access
if [ ! `id -u` -eq 0 ]; then
    echo "You must be root to run this script!"
    exit 1
fi

#create the subdirectory
prepare(){
    cd /
    dirname='rootfs'
    if [ ! -d ${dirname} ];then 
        mkdir -p ${dirname}
    else
        echo "rootfs exists already"
    fi
}

make_rootfs(){
    cd /
    HTTP_MIRRORS="http://mirrors.ustc.edu.cn/ubuntu-ports"
    sudo apt -y install debootstrap qemu
    debootstrap --arch=arm64 focal rootfs ${HTTP_MIRRORS}        
    apt-get -y install qemu qemu-user-static binfmt-support debootstrap
    cp /usr/bin/qemu-aarch64-static /rootfs/usr/bin
    echo "copy done!"
    mount --types proc /proc rootfs/proc
    #to check if mount successfully
    echo "$? mount successful!"
    mount --rbind /sys rootfs/sys
    echo "$? mount successful!"
    mount --make-rslave rootfs/sys  
    echo "$? mount successful"  
    mount --rbind /dev rootfs/dev
    echo "$? mount successful!"
    mount --make-rslave rootfs/dev
    echo "$? mount successful!"
    
}

#set up mirror sources
apt_update(){
    chroot rootfs/ /usr/bin/bash -c 'apt -y install apt-transport-https'
    #chroot rootfs/ /usr/bin/bash cp /etc/apt/sources.list /etc/apt/sources.list.bak
    chroot rootfs/ /usr/bin/bash -c "echo deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ focal main restricted universe multiverse > /etc/apt/sources.list"
    chroot rootfs/ /usr/bin/bash -c 'echo deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ focal-updates main restricted universe multiverse >> /etc/apt/sources.list'
    chroot rootfs/ /usr/bin/bash -c 'echo deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ focal-backports main restricted universe multiverse >> /etc/apt/sources.list'
    chroot rootfs/ /usr/bin/bash -c 'echo deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/ focal-security main restricted universe multiverse >> /etc/apt/sources.list'
    chroot rootfs/ /usr/bin/bash -c  'apt update -y'
    if [ $? -eq 0 ]; then
        echo "Mirror setted."
    else
        echo "Failed to set Mirror."
    fi
}

config_raspi(){
    echo "Begin to set up LOCALE"
    chroot rootfs/ /usr/bin/bash -c 'apt-get -y install language-pack-zh-hans language-pack-zh-hans-base'
    chroot rootfs/ /usr/bin/bash -c "export LANG=C"
    chroot rootfs/ /usr/bin/bash -c "export LC_ALL=C"
    if [ $? -eq 0 ]; then
        echo "Locale setted."
    else
        echo "FAILED TO SET LOCALE."
    fi
    
    chroot rootfs/ /usr/bin/bash -c "mkdir -p /boot/firmware"
    chroot rootfs/ /usr/bin/bash -c 'apt install linux-raspi -y'
    chroot rootfs/ /usr/bin/bash -c 'apt install linux-firmware-raspi2 -y'
    if [ $? -eq 0 ]; then
        echo "raspi downloaded."
    else
        echo "raspi failed."
    fi

    #uboot setting-up
    cp /boot/firmware/uboot*.bin /boot/firmware/*.txt /boot/firmware/bootcode*.bin /rootfs/boot/firmware
    echo "$? cope done!"
}
   

services_install(){
    chroot rootfs/ /usr/bin/bash -c 'apt-get install openssh-server -y'
    chroot rootfs/ /usr/bin/bash -c 'apt-get install software-properties-common -y'
    if [ $? -eq 0 ]; then
        echo "$? Services have been downloaded!"
    else
        echo "DOWNLOADING FAILURE!"
    fi
}

account_creation(){
    chroot rootfs/ /usr/bin/bash -c 'useradd kylin --create-home --password "$(openssl passwd -1 "kylin")" --shell /bin/bash --user-group'
    chroot rootfs/ /usr/bin/bash -c 'usermod -a -G sudo,adm kylin'
    if [ $? -eq 0 ]; then
        echo "Account create successfully!"
    else
        echo "FAILED TO CREATE ACCOUNT."
    fi

    chroot rootfs/ /usr/bin/bash -c 'echo "ubuntukylin" > /etc/hostname'
    echo "$? ubuntukylin"
    
    chroot rootfs/ /usr/bin/bash -c "rm /tmp/* -rf"
    echo "$? rm"
    chroot rootfs/ /usr/bin/bash -c "rm /var/lib/apt/lists/*dists*"
    echo "$? rm"
    chroot rootfs/ /usr/bin/bash -c "apt clean -y"
    echo "$? rm"
    #cd /
    #rm rootfs/root/.bash_history
}



un_mount(){
    cd /
    umount rootfs/proc
    umount -R rootfs/sys
    umount -R rootfs/dev
    echo "$? umount"
}

generate_filesystem(){
    cd /
    NUM=700
    var=$(du -sx rootfs/ --block-size=1M)
    temp=`echo ${var} | tr -cd "[0-9]"`
    SIZE=`expr $temp + $NUM`
    TARGET_IMAGE='exported.img'

    dd if=/dev/zero of=${TARGET_IMAGE} bs=1M count=0 seek=${SIZE} > /dev/null 2>&1
 
    fdisk ${TARGET_IMAGE} > /dev/null 2>&1 << EOF 
n
p
1

+256M
a
t
c
n
p
2


w
EOF

    chroot rootfs/ /usr/bin/bash -c 'apt-get update -y'
    chroot rootfs/ /usr/bin/bash -c 'apt-get install kpartx -y'
    EXPORT_PSEUDO_DEVICE="$(sudo kpartx -av "${TARGET_IMAGE}" | sed -E 's/.(loop[0-9])p.*/\1/g' | head -1)"
    EXPORT_DEVICE=`echo "${EXPORT_PSEUDO_DEVICE}" | tr -cd "[0-9]" `
    EXPORT_DEVICE_BOOT="/dev/mapper/loop${EXPORT_DEVICE}p1"
    EXPORT_DEVICE_ROOT="/dev/mapper/loop${EXPORT_DEVICE}p2"

    #filesystem created and mounted
    sudo mkfs.fat -F32 "$EXPORT_DEVICE_BOOT" -n "system-boot"
    sudo mkfs.ext4 "$EXPORT_DEVICE_ROOT" -L "writable" 
    mkdir 'export'
    mount "$EXPORT_DEVICE_ROOT" 'export'
    mkdir export/boot/firmware -p
    mount "$EXPORT_DEVICE_BOOT" "export/boot/firmware"

    echo "sync rootfs to image..."
    rsync -av -y "rootfs/" "export/"
    umount "export/boot/firmware"
    umount "export/"
    sudo kpartx -dv "${TARGET_IMAGE}"
    echo "success export image to ${TARGET_IMAGE}"
}


prepare
make_rootfs
apt_update
config_raspi
services_install
account_creation
#clean_apt
un_mount
generate_filesystem
