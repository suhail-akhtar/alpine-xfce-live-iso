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
plymout-themes
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

mkdir -p "$tmp"/etc/NetworkManager
makefile root:root 0644 "$tmp"/etc/NetworkManager/NetworkManager.conf <<EOF

[main] 
dhcp=internal
plugins=ifupdown,keyfile

[ifupdown]
managed=true

[device]
wifi.scan-rand-mac-address=yes
wifi.backend=wpa_supplicant

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
echo "liveuser:password" | chpasswd -e
for group in audio video netdev input plugdev users wheel; do
    addgroup liveuser \$group
done
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
    before *
    after bootmisc
}

start() {
    ebegin "Starting Plymouth"
    /sbin/plymouthd --mode=boot
    /bin/plymouth show-splash
    eend $?
}

stop() {
    ebegin "Stopping Plymouth"
    /bin/plymouth quit
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
    /bin/plymouth quit
    eend $?
}
EOF

chmod +x "$tmp"/etc/init.d/plymouth "$tmp"/etc/init.d/plymouth-quit

# Configure Plymouth
mkdir -p "$tmp"/etc/plymouth
makefile root:root 0644 "$tmp"/etc/plymouth/plymouthd.conf <<EOF
[Daemon]
Theme=spinner
ShowDelay=0
DeviceTimeout=8
EOF

rc_add plymouth boot
rc_add plymouth-quit shutdown

# Plymouth END

tar -c -C "$tmp" etc usr | gzip -9n > $HOSTNAME.apkovl.tar.gz
