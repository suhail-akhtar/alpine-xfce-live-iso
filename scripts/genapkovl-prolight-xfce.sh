#!/bin/sh -e

HOSTNAME="$1"
if [ -z "$HOSTNAME" ]; then
	echo "usage: $0 hostname"
	exit 1
fi

cleanup() {
	rm -rf "$tmp"
}

makefile() {
	OWNER="$1"
	PERMS="$2"
	FILENAME="$3"
	cat > "$FILENAME"
	chown "$OWNER" "$FILENAME"
	chmod "$PERMS" "$FILENAME"
}

rc_add() {
	mkdir -p "$tmp"/etc/runlevels/"$2"
	ln -sf /etc/init.d/"$1" "$tmp"/etc/runlevels/"$2"/"$1"
}

tmp="$(mktemp -d)"
trap cleanup EXIT

mkdir -p "$tmp"/etc
makefile root:root 0644 "$tmp"/etc/hostname <<EOF
$HOSTNAME
EOF

mkdir -p "$tmp"/etc/network
makefile root:root 0644 "$tmp"/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

auto wlan0
iface wlan0 inet dhcp

EOF

mkdir -p "$tmp"/etc/apk
makefile root:root 0644 "$tmp"/etc/apk/world <<EOF
alpine-base
xorg-server
xf86-input-libinput
xinit
alpine-conf
curl
nano 
vim
udev-init-scripts
eudev
mesa-dri-gallium
openbox
xf86-video-vesa
dbus
openssl
curl
wget
lsblk
findmnt
parted
rsync
sfdisk
syslinux
util-linux
xfsprogs
dosfstools 
ntfs-3g
cfdisk
xfce4
xfce4-terminal
xfce4-screensaver
lightdm-gtk-greeter
elogind
polkit-elogind
xterm
gvfs
udisks2
gvfs-smb
gvfs-fuse
fuse-openrc
gvfs-nfs
gvfs-gphoto2
gvfs-afp
consolekit2
polkit
networkmanager
networkmanager-tui
networkmanager-cli
network-manager-applet
networkmanager-wifi
networkmanager-openvpn
wpa_supplicant
wpa_supplicant-openrc
plymouth
firefox
pulseaudio
pulseaudio-alsa
pulseaudio-bluez
alsa-plugins-pulse
alsa-utils 
alsaconf
alsa-utils
alsa-lib
pavucontrol
doas
networkmanager-dnsmasq
breeze-plymouth
wireless-tools
EOF

rc_add devfs sysinit
rc_add dmesg sysinit
rc_add mdev sysinit
rc_add hwdrivers sysinit
rc_add modloop sysinit

rc_add hwclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

## Custom
rc_add lightdm default
rc_add fuse default
rc_add elogind default
rc_add udev sysinit
rc_add udev-trigger sysinit
rc_add udev-settle sysinit
rc_add udev-postmount default
rc_add wpa_supplicant boot
rc_add networkmanager default
rc_add dbus default
rc_add alsa default
rc_add local default


mkdir -p "$tmp"/etc/apk
makefile root:root 0644 "$tmp"/etc/apk/repositories <<EOF
/media/cdrom/apkss
https://dl-cdn.alpinelinux.org/alpine/edge/main
https://dl-cdn.alpinelinux.org/alpine/edge/community
EOF

mkdir -p "$tmp"/etc/doas.d
cp /etc/doas.d/doas.conf "$tmp"/etc/doas.d/
chmod 0644 "$tmp"/etc/doas.d

mkdir -p "$tmp"/etc/NetworkManager
makefile root:root 0644 "$tmp"/etc/NetworkManager/NetworkManager.conf <<EOF

[main] 
dhcp=internal
plugins=ifupdown,keyfile

[ifupdown]
managed=true

[device]
wifi.scan-rand-mac-address=no
#wifi.backend=wpa_supplicant

EOF

# Add the setup-wifi script to rc.local to run on boot
mkdir -p "$tmp"/etc/local.d
makefile root:root 0755 "$tmp"/etc/local.d/setup-wifi.start <<EOF
#!/bin/sh

# Ensure Wi-Fi is not blocked
rfkill unblock wifi

# Restart NetworkManager to apply changes
rc-service networkmanager restart

# Wait for NetworkManager to be fully up
sleep 5

# Trigger a Wi-Fi scan
nmcli device wifi rescan

# List available Wi-Fi networks
nmcli device wifi list

EOF


mkdir -p "$tmp"/etc/lightdm

makefile root:root 0644 "$tmp"/etc/lightdm/lightdm.conf <<EOF
[Seat:*]
autologin-user=liveuser
autologin-session=xfce
autologin-user-timeout=0
EOF


# Adding User Service

mkdir -p "$tmp"/usr/sbin

makefile root:root 0755 "$tmp"/usr/sbin/adduser.sh <<EOF
#!/bin/sh
adduser -D -g "Live User" liveuser

#encrypted_password=$(openssl passwd -6 "1234")
#echo "liveuser:$encrypted_password" | chpasswd -e
#encrypted password is:   password

echo "liveuser:$5$BlpeNVJy5ytCusUs$TxAocxKZ0wD78fUicryMOL7Mo21hisFxEqCewlECSv/" | chpasswd -e

for group in audio video netdev input plugdev users wheel; do
    addgroup liveuser \$group
done

addgroup root audio

EOF

# Create a firstboot service to add the user
mkdir -p "$tmp"/etc/init.d
makefile root:root 0755 "$tmp"/etc/init.d/firstboot <<EOF
#!/sbin/openrc-run

description="First boot setup"

depend() {
    need net
}

start() {
    ebegin "Running first boot setup"
    /usr/sbin/adduser.sh
    eend \$?
    rc-update del firstboot default
}
EOF

rc_add firstboot default

## END - Adding User

# audio
mkdir -p "$tmp"/etc/security/limits.d
makefile root:root 0644 "$tmp"/etc/security/limits.d/audio.conf <<EOF
@audio - nice -11
EOF


## Configure liveuser  to doas no password
# Create doas configuration directory
mkdir -p "$tmp"/etc/doas.d
makefile root:root 0400 "$tmp"/etc/doas.d/liveuser.conf <<EOF

# Allow liveuser to use doas without password
permit nopass keepenv :liveuser

# Optional: Allow liveuser to use doas as root without password
permit nopass keepenv :liveuser as root

EOF

# branding
cat > "$tmp"/etc/os-release <<EOF
NAME="ProLight OS"
VERSION="1.0"
ID=prolightos
PRETTY_NAME="ProLight OS 1.0"
EOF

cat > "$tmp"/etc/motd <<EOF

Welcome to ProLight OS 1.0
For more information please visit: https://prolightos.io

EOF

cat > "$tmp"/etc/issue <<EOF

ProLight OS 1.0

EOF

# Plymouth Splash screen configuration

mkdir -p "$tmp"/etc/init.d
makefile root:root 0644 "$tmp"/etc/init.d/plymouth << EOF
#!/sbin/openrc-run

depend() {
    need devfs
    before *
    after mountfs
}

start() {
    ebegin "Starting Plymouth"
    #/usr/sbin/plymouthd --mode=boot
    #/usr/bin/plymouth show-splash

    plymouth-set-default-theme breeze
    /usr/sbin/plymouthd --mode=boot --pid-file=/run/plymouth/pid
    /usr/bin/plymouth show-splash

    eend $?
}

stop() {
    ebegin "Stopping Plymouth"
    /usr/bin/plymouth quit
    eend $?
}
EOF

makefile root:root 0644 "$tmp"/etc/init.d/plymouth-quit << EOF
#!/sbin/openrc-run

depend() {
    need plymouth
}

start() {
    ebegin "Quitting Plymouth"
    /usr/bin/plymouth quit
    eend $?
}
EOF

makefile root:root 0755 "$tmp"/etc/init.d/plymouth-shutdown <<EOF
#!/sbin/openrc-run

description="Plymouth shutdown screen"

depend() {
    #after *

    keyword -stop
    before *
}

start() {
    ebegin "Starting Plymouth shutdown screen"
    /usr/sbin/plymouthd --mode=shutdown
    /usr/bin/plymouth show-splash

   # /usr/sbin/plymouthd --mode=shutdown
   # /usr/bin/plymouth show-splash
    eend $?
}
stop() {
    ebegin "Stopping Plymouth"
    plymouth quit
    eend $?
}
EOF

chmod +x "$tmp"/etc/init.d/plymouth "$tmp"/etc/init.d/plymouth-quit "$tmp"/etc/init.d/plymouth-shutdown

# Configure Plymouth
mkdir -p "$tmp"/etc/plymouth
makefile root:root 0644 "$tmp"/etc/plymouth/plymouthd.conf <<EOF
[Daemon]
Theme=breeze
ShowDelay=0
DeviceTimeout=8
QuietPixel=true
EOF

rc_add plymouth sysinit
rc_add plymouth-quit default
rc_add plymouth-shutdown shutdown

# Plymouth END

makefile root:root 0644 "$tmp"/etc/inittab <<EOF
# /etc/inittab

# Start Plymouth immediately
::sysinit:/usr/sbin/plymouthd --mode=boot --pid-file=/run/plymouth/pid
::sysinit:/usr/bin/plymouth show-splash

::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default

# Quit Plymouth after OpenRC completes
::sysinit:/bin/plymouth quit

# Set up a couple of getty's
tty1::respawn:/sbin/getty 38400 tty1
tty2::respawn:/sbin/getty 38400 tty2
tty3::respawn:/sbin/getty 38400 tty3
tty4::respawn:/sbin/getty 38400 tty4
tty5::respawn:/sbin/getty 38400 tty5
tty6::respawn:/sbin/getty 38400 tty6

# Put a getty on the serial port
#ttyS0::respawn:/sbin/getty -L ttyS0 115200 vt100

# Stuff to do for the 3-finger salute
::ctrlaltdel:/sbin/reboot

# Stuff to do before rebooting
::shutdown:/sbin/openrc shutdown
EOF


# Audio
# 1. Create a new script to set the volume

mkdir -p "$tmp"/usr/local/bin
makefile root:root 0755 "$tmp"/usr/local/bin/set-default-volume.sh <<EOF
#!/bin/sh

# Set Master volume to 50%
amixer -q sset Master 50%

# Unmute Master if it's muted
amixer -q sset Master unmute

# Set PCM volume to 50% (if available)
amixer -q sset PCM 50% unmute 2>/dev/null

# Set Speaker volume to 50% (if available)
amixer -q sset Speaker 50% unmute 2>/dev/null

# Set Headphone volume to 50% (if available)
amixer -q sset Headphone 50% unmute 2>/dev/null

exit 0
EOF

# 2. Create an OpenRC service to run this script at boot

mkdir -p "$tmp"/etc/init.d
makefile root:root 0755 "$tmp"/etc/init.d/set-default-volume <<EOF
#!/sbin/openrc-run

description="Set default audio volume"

depend() {
    need alsa
    after alsa
}

start() {
    ebegin "Setting default audio volume"
    /usr/local/bin/set-default-volume.sh
    eend $?
}
EOF

# 3. Add the new service to the default runlevel
rc_add set-default-volume default

# ENDS <---

tar -c -C "$tmp" etc usr | gzip -9n > $HOSTNAME.apkovl.tar.gz
