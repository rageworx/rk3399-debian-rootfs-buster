#!/bin/bash -e

# Directory contains the target rootfs
TARGET_ROOTFS_DIR="binary"

if [ "$ARCH" == "armhf" ]; then
	ARCH='armhf'
elif [ "$ARCH" == "arm64" ]; then
	ARCH='arm64'
else
    echo -e "\033[36mAutomatically set ARCH default to arm64...\033[0m"
    ARCH='arm64'
fi

if [ ! $VERSION ]; then
	VERSION="debug"
fi

if [ ! -e linaro-buster-alip-*.tar.gz ]; then
	echo "\033[36m Run mk-base-debian.sh first \033[0m"
fi

finish() {
	sudo umount $TARGET_ROOTFS_DIR/dev
	exit -1
}
trap finish ERR

echo -e "\033[36m Extract image \033[0m"
sudo tar -xpf linaro-buster-alip-*.tar.gz

echo -e "\033[36m Copy overlay to rootfs \033[0m"
sudo mkdir -p $TARGET_ROOTFS_DIR/packages
sudo cp -rf packages/$ARCH/* $TARGET_ROOTFS_DIR/packages

# some configs
sudo cp -rf overlay/* $TARGET_ROOTFS_DIR/

if [ "$ARCH" == "armhf"  ]; then
    sudo cp overlay-firmware/usr/bin/brcm_patchram_plus1_32 $TARGET_ROOTFS_DIR/usr/bin/brcm_patchram_plus1
    sudo cp overlay-firmware/usr/bin/rk_wifi_init_32 $TARGET_ROOTFS_DIR/usr/bin/rk_wifi_init
elif [ "$ARCH" == "arm64"  ]; then
    sudo cp overlay-firmware/usr/bin/brcm_patchram_plus1_64 $TARGET_ROOTFS_DIR/usr/bin/brcm_patchram_plus1
    sudo cp overlay-firmware/usr/bin/rk_wifi_init_64 $TARGET_ROOTFS_DIR/usr/bin/rk_wifi_init
fi

# bt,wifi,audio firmware
sudo mkdir -p $TARGET_ROOTFS_DIR/system/lib/modules/
sudo find ../kernel/drivers/net/wireless/rockchip_wlan/*  -name "*.ko" | \
    xargs -n1 -i sudo cp {} $TARGET_ROOTFS_DIR/system/lib/modules/

sudo cp -rf overlay-firmware/* $TARGET_ROOTFS_DIR/

if [ -d "../modules" ]; then
    sudo cp -r ../modules/lib/modules $TARGET_ROOTFS_DIR/lib
fi

# adb
if [ "$ARCH" == "armhf" ]; then
	sudo cp -rf overlay-debug/usr/local/share/adb/adbd-32 $TARGET_ROOTFS_DIR/usr/local/bin/adbd
elif [ "$ARCH" == "arm64"  ]; then
	sudo cp -rf overlay-debug/usr/local/share/adb/adbd-64 $TARGET_ROOTFS_DIR/usr/local/bin/adbd
fi

# glmark2
sudo rm -rf $TARGET_ROOTFS_DIR/usr/local/share/glmark2
sudo mkdir -p $TARGET_ROOTFS_DIR/usr/local/share/glmark2
if [ "$ARCH" == "armhf" ]; then
	sudo cp -rf overlay-debug/usr/local/share/glmark2/armhf/share/* $TARGET_ROOTFS_DIR/usr/local/share/glmark2
	sudo cp overlay-debug/usr/local/share/glmark2/armhf/bin/glmark2-es2 $TARGET_ROOTFS_DIR/usr/local/bin/glmark2-es2
elif [ "$ARCH" == "arm64"  ]; then
	sudo cp -rf overlay-debug/usr/local/share/glmark2/aarch64/share/* $TARGET_ROOTFS_DIR/usr/local/share/glmark2
	sudo cp overlay-debug/usr/local/share/glmark2/aarch64/bin/glmark2-es2 $TARGET_ROOTFS_DIR/usr/local/bin/glmark2-es2
fi

if [ "$VERSION" == "debug" ] || [ "$VERSION" == "jenkins" ]; then
	# adb, video, camera  test file
	sudo cp -rf overlay-debug/etc $TARGET_ROOTFS_DIR/
	sudo cp -rf overlay-debug/lib $TARGET_ROOTFS_DIR/usr/
	sudo cp -rf overlay-debug/usr $TARGET_ROOTFS_DIR/
fi

if  [ "$VERSION" == "jenkins" ] ; then
	# network
	sudo cp -b /etc/resolv.conf  $TARGET_ROOTFS_DIR/etc/resolv.conf
fi

echo ">>>"
echo -e "\033[36m Change root on [\033[37m$TARGET_ROOTFS_DIR\033[36m]\033[0m"
echo "<<<"

if [ "$ARCH" == "armhf" ]; then
	sudo cp /usr/bin/qemu-arm-static $TARGET_ROOTFS_DIR/usr/bin/
elif [ "$ARCH" == "arm64"  ]; then
	sudo cp /usr/bin/qemu-aarch64-static $TARGET_ROOTFS_DIR/usr/bin/
fi
sudo mount -o bind /dev $TARGET_ROOTFS_DIR/dev

cat << EOF | sudo chroot $TARGET_ROOTFS_DIR

chmod o+x /usr/lib/dbus-1.0/dbus-daemon-launch-helper
apt-get update
apt-get install -y lxpolkit
# -- no longer needed on debian-10 -- apt-get install -y blueman
echo exit 101 > /usr/sbin/policy-rc.d
chmod +x /usr/sbin/policy-rc.d

#-------------- systemd-sysv + vim, not vi --------------
apt-get install -y systemd-sysv vim

#---------------power management --------------
apt-get install -y busybox pm-utils triggerhappy
cp /etc/Powermanager/triggerhappy.service  /lib/systemd/system/triggerhappy.service

#---------------ForwardPort Linaro overlay --------------
apt-get install -y e2fsprogs
wget http://repo.linaro.org/ubuntu/linaro-overlay/pool/main/l/linaro-overlay/linaro-overlay-minimal_1112.10_all.deb
wget http://repo.linaro.org/ubuntu/linaro-overlay/pool/main/9/96boards-tools/96boards-tools-common_0.9_all.deb
dpkg -i *.deb
rm -rf *.deb
apt-get install -f -y

#---------------conflict workaround --------------
apt-get remove -y xserver-xorg-input-evdev
apt-get install -y libxfont-dev libinput-bin libinput10 libwacom-common libwacom2 libunwind8 xserver-xorg-input-libinput libdmx1  libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-render-util0 libxcb-xf86dri0 libxcb-xv0 libpixman-1-dev  libxkbfile-dev libpciaccess-dev mesa-common-dev

#---------XFCE4 Power control------
apt-get install -y xfce4-power-manager xfce4-power-manager-plugins

#---------------Video--------------
echo -e "\033[36m Setup Video.................... \033[0m"
apt-get install -y gstreamer1.0-plugins-base gstreamer1.0-tools gstreamer1.0-alsa gstreamer1.0-plugins-good  gstreamer1.0-plugins-bad alsa-utils

dpkg -i  /packages/$ARCH/video/mpp/*.deb
# dpkg -i  /packages/$ARCH/video/gstreamer/*.deb
apt-get install -f -y

#---------------Qt-Video--------------
dpkg -l | grep lxde
if [ "$?" -eq 0 ]; then
	# if target is base, we won't install qt
	apt-get install  -y libqt5opengl5 libqt5qml5 libqt5quick5 libqt5widgets5 libqt5gui5 libqt5core5a qml-module-qtquick2 libqt5multimedia5 libqt5multimedia5-plugins libqt5multimediaquick-p5
	#dpkg -i  /packages/video/qt/*
	apt-get install -f -y
else
	echo "won't install qt"
fi

#-----------MESA, XFCE4-----------
apt-get remove mesa-common-dev -y
apt-get install nano pciutils

apt-get remove gnome-shell gnome-session* -y
apt-get install xfce4 lightdm -y
apt-get install --reinstall libgdk-pixbuf2.0-0

#--------------libdrm----------------
dpkg -i /packages/$ARCH/libdrm/libdrm-rockchip*_$ARCH.deb
apt-get install -f -y

#---------------TODO: USE DEB-------------- 
#---------------Setup Graphics-------------- 
apt-get install -y weston
#cd /usr/lib/aarch64-linux-gnu
#ln -s libmali-midgard-t86x-r18p0-wayland.so libmali-bifrost-g31-rxp0-wayland-gbm.so
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libEGL.so
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libEGL.so.1
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libEGL.so.1.0.0
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libGLESv2.so
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libGLESv2.so.2
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libGLESv2.so.2.0.0
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libMaliOpenCL.so
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libOpenCL.so
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libgbm.so
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libgbm.so.1
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libgbm.so.1.0.0
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libwayland-egl.so
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libwayland-egl.so.1
#ln -sf libmali-bifrost-g31-rxp0-wayland-gbm.so libwayland-egl.so.1.0.0
#cd /

#---------------Others--------------

#---------SDL2+FFmpeg---------
apt-get install -y libsdl2-2.0-0:$ARCH libcdio-paranoia1:$ARCH libjs-bootstrap:$ARCH libjs-jquery:$ARCH
apt-get install -y ffmpeg:$ARCH

#-------------exFAT and fuse----------
apt-get install -y exfat-fuse:$ARCH exfat-utils:$ARCH

#---------------Custom Script-------------- 
systemctl mask systemd-networkd-wait-online.service
systemctl mask NetworkManager-wait-online.service
systemctl mask wpa_supplicant-nl80211@.service
systemctl mask wpa_supplicant-wired@.service
systemctl mask wpa_supplicant.service
rm /lib/systemd/system/wpa_supplicant@.service

#---------------Clean-------------- 
ldconfig
rm -rf /var/lib/apt/lists/*
apt-get autoremove

EOF

sudo umount $TARGET_ROOTFS_DIR/dev
