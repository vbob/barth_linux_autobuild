#!/bin/bash

TOP="$(pwd)"
OUTDIR="$(pwd)/out_v1_modules"

ARCH=arm64
PREFIX=aarch64-linux-gnu-
DEVICE=t8103-j313

Help()
{
   echo "Add description of the script functions here."
   echo
   echo "Syntax: build [-h] " 
   echo "options:"
   echo "-h     Print help"
   echo "-l     Rebuild linux"
   echo "-m     Rebuild m1n1"
   echo "-b     Rebuild busybox"
   echo "-d     Rebuild debian"
   echo "-r     Rebuild rootfs"
   echo "-u     Rebuild uboot"
   echo "-w     Write all /dev/ttyACM0"
   echo
}

BuildLinux() 
{
    cd $TOP/linux

    echo "[LINUX] Cleaning up"
    make -s clean
    rm -rf $OUTDIR/kernel_modules
    mkdir -pv $OUTDIR/kernel_modules/

    echo "[LINUX] Creating config"
    cp -rf $TOP/options/linux.config $TOP/linux/.config
    
    echo "[LINUX] Compiling dtbs..."
    make -j24 -s ARCH=$ARCH CROSS_COMPILE=$PREFIX dtbs

    echo "[LINUX] Copying dtbs..."
    rm -rf $OUTDIR/$DEVICE.dtb
    cp $TOP/linux/arch/arm64/boot/dts/apple/$DEVICE.dtb $OUTDIR

    echo "[LINUX] Compiling Image.gz..."
    make -j24 -s ARCH=$ARCH CROSS_COMPILE=$PREFIX Image.gz

    echo "[LINUX] Copying Image.gz..."
    rm -rf $OUTDIR/Image.gz
    cp $TOP/linux/arch/arm64/boot/Image.gz $OUTDIR

    echo "[LINUX] Compiling bindeb-pkg..."
    make -j24 -s ARCH=$ARCH CROSS_COMPILE=$PREFIX bindeb-pkg

    echo "[LINUX] Compiling modules"
    make -j24 -s ARCH=$ARCH CROSS_COMPILE=$PREFIX modules

    echo "[LINUX] Installing modules"
    make -j24 -s ARCH=$ARCH CROSS_COMPILE=$PREFIX INSTALL_MOD_PATH=$OUTDIR/kernel_modules/ modules_install

    cd $TOP
}

BuildM() 
{       
    echo "Building M1N1..."
    cd $TOP/m1n1
    make clean
    make

    echo "Copying m1n1.macho to $OUTDIR"
    rm -f $OUTDIR/m1n1.macho
    cp build/m1n1.macho $OUTDIR

    cd $TOP
}

BuildBusybox() 
{
    echo "Building Busybox..."
    cd $TOP/busybox
    make clean
    make ARCH=$ARCH CROSS_COMPILE=$PREFIX defconfig

    rm -rf $OUTDIR/rootfs
    mkdir -pv $OUTDIR/rootfs/
    make -j24 ARCH=$ARCH CROSS_COMPILE=$PREFIX CONFIG_STATIC=y CONFIG_PREFIX=$OUTDIR/rootfs install 
    chmod +x $OUTDIR/rootfs/bin/busybox
    rm $OUTDIR/rootfs/linuxrc

    mkdir -pv $OUTDIR/rootfs/dev
    mkdir -pv $OUTDIR/rootfs/proc
    mkdir -pv $OUTDIR/rootfs/sys
    mkdir -pv $OUTDIR/rootfs/tmp

    rm -rf $OUTDIR/rootfs/init 
    rm -rf $OUTDIR/rootfs/lib

    mkdir -pv $OUTDIR/rootfs/
    cp -rf $TOP/kernel_modules/lib $OUTDIR/rootfs/
    cp -rf $TOP/kernel_modules/lib $OUTDIR/rootfs/

    echo "#!/bin/busybox sh
sleep 3
echo 'Built on $(date)'
echo 'Starting busybox...'


/bin/mount -t devtmpfs devtmpfs /dev
/bin/mount -t proc proc /proc
/bin/mount -t sysfs sysfs /sys
/bin/mount -t tmpfs tmpfs /tmp

modprobe apple-mailbox
modprobe pinctrl-apple-gpio
modprobe i2c-apple
modprobe tps6598x
modprobe apple-dart
modprobe dwc3
modprobe dwc3-of-simple
modprobe spi-apple
modprobe spi-hid-apple
modprobe spi-hid-apple-of
modprobe macsmc
modprobe macsmc-rtkit
modprobe rtc-macsmc
modprobe simple-mfd-spmi
modprobe spmi-apple-controller
modprobe nvmem_spmi_mfd
modprobe cfg80211
modprobe mac80211
modprobe brcmfmac

/bin/sh" > $OUTDIR/rootfs/init 

    chmod +x $OUTDIR/rootfs/init

    cd $TOP
}

BuildDebian() {
    echo "Building Debian..."

    sudo rm -rf $OUTDIR/rootfs
    mkdir -p $OUTDIR/debian_cache

    sudo eatmydata qemu-debootstrap --cache-dir=$OUTDIR/debian_cache --arch=arm64 --include\
       initramfs-tools,wpasupplicant,tcpdump,vim,tmux,vlan,ntpdate,parted,curl,wget,grub-efi-arm64,mtr-tiny,dbus,ca-certificates,sudo,openssh-client,mtools,pciutils,usbutils,htop\
       testing\
       $OUTDIR/rootfs\
       http://ftp.br.debian.org/debian/
    
    cd $OUTDIR
    export KERNEL=`ls -1rt linux-image*.deb | grep -v dbg | tail -1`
    cd $OUTDIR/rootfs

    sudo bash -c 'echo $DEVICE > etc/hostname'
    sudo bash -c 'echo > etc/motd'

    sudo cp $TOP/debian_files/sources.list etc/apt/sources.list
    sudo cp $TOP/debian_files/hosts etc/hosts
    sudo cp $TOP/debian_files/resolv.conf etc/resolv.conf
    sudo cp $TOP/debian_files/quickstart.txt root/
    sudo cp $TOP/debian_files/interfaces etc/network/interfaces
    sudo cp $TOP/debian_files/wpa.conf etc/wpa_supplicant/wpa_supplicant.conf
    sudo cp $TOP/debian_files/rc.local etc/rc.local

    sudo bash -c 'chroot . apt update'
    sudo bash -c 'chroot . apt install -y firmware-linux pciutils usbutils'

    sudo -- perl -p -i -e 's/root:x:/root::/' etc/passwd
    sudo -- ln -s lib/systemd/systemd init

    sudo cp ../${KERNEL} .
    sudo chroot . dpkg -i ${KERNEL}
    sudo rm ${KERNEL}

    sudo bash -c 'apt-get clean'

    cd $TOP
}

BuildRootfs() 
{
    echo "Building Rootfs..."

    rm -f $OUTDIR/initrd.gz 

    cd $OUTDIR/rootfs 
    find . | cpio --quiet -ov -H newc | pigz -9 > ../initrd.gz
    cd $TOP
}

BuildUboot() 
{
    echo "Building Uboot..."

}

Write() 
{
    echo "Writing..."
    python $TOP/m1n1/proxyclient/experiments/pcie_enable_devices.py 

    python $TOP/m1n1/proxyclient/tools/linux.py \
           -b 'earlycon console=ttySAC0,1500000 console=tty0 debug init=/init' \
           $OUTDIR/Image.gz \
           $OUTDIR/t8103-j313.dtb \
           $OUTDIR/initrd.gz 
}

BUILD_LINUX=false
BUILD_M1N1=false
BUILD_BUSYBOX=false
BUILD_DEBIAN=false
BUILD_ROOTFS=false
BUILD_UBOOT=false
WRITE_TO_TTY=false

while getopts ":hlmbdwru" option; do
   case $option in
    h)
         Help
         exit;;
    l) 
         BUILD_LINUX=true;;
    m) 
         BUILD_M1N1=true;;
    b) 
         BUILD_BUSYBOX=true;;
    d)
         BUILD_DEBIAN=true;;
    w) 
         WRITE_TO_TTY=true;;
    r) 
         BUILD_ROOTFS=true;;
    u) 
         BUILD_UBOOT=true;;
    \?) 
         echo "Error: Invalid option"
         exit;;
   esac
done

mkdir -pv $OUTDIR

echo "building: "
echo "  linux:   $BUILD_LINUX"
echo "  m1n1:    $BUILD_M1N1"
echo "  busybox: $BUILD_BUSYBOX"
echo "  debian:  $BUILD_DEBIAN"
echo "  rootfs:  $BUILD_ROOTFS"
echo "  uboot:   $BUILD_UBOOT"
echo "write: $WRITE_TO_TTY"
echo "saving on: $OUTDIR"

echo ""
echo "Starting"
echo "---------------------------"
echo ""

if [ "$BUILD_LINUX" = true ] ; then
    BuildLinux
fi

if [ "$BUILD_M1N1" = true ] ; then
    BuildM
fi

if [ "$BUILD_BUSYBOX" = true ] ; then
    BuildBusybox
fi

if [ "$BUILD_DEBIAN" = true ] ; then
    BuildDebian
fi

if [ "$BUILD_ROOTFS" = true ] ; then
    BuildRootfs
fi

if [ "$BUILD_UBOOT" = true ] ; then
    BuildUboot
fi

if [ "$WRITE_TO_TTY" = true ] ; then
    Write
fi