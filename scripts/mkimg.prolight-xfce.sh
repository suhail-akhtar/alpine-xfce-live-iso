build_prolightxfce_setup() {
	setup-xorg-base xterm
	setup-devd udev
	setup-desktop xfce
	echo "tmp: $tmp"
}


profile_prolightxfce() {
	profile_extended
	profile_abbrev="plxfce"
	title="ProLight XFCE"
	desc="ProLight OS - XFCE"
	arch="x86_64"
	kernel_cmdline="splash plymouth.ignore-serial-consoles"
	boot_addons="amd-ucode intel-ucode"
        initrd_ucode="/boot/amd-ucode.img /boot/intel-ucode.img"
	apks="$apks alpine-conf xorg-server xf86-input-libinput xinit alpine-conf curl nano vim udev-init-scripts eudev mesa-dri-gallium"
	apks="$apks xf86-video-vesa dbus openssl curl wget lsblk findmnt
		parted rsync sfdisk syslinux util-linux xfsprogs
                dosfstools ntfs-3g cfdisk xterm
		linux-firmware-intel linux-firmware-amd
		xfce4 xfce4-terminal xfce4-screensaver lightdm-gtk-greeter
		elogind polkit-elogind xterm wireless-tools
		gvfs udisks2 gvfs-smb gvfs-fuse fuse-openrc gvfs-nfs gvfs-gphoto2 gvfs-afp
		networkmanager networkmanager-tui networkmanager-cli network-manager-applet networkmanager-wifi networkmanager-openvpn
		wpa_supplicant wpa_supplicant-openrc plymouth breeze-plymouth networkmanager-dnsmasq
		firefox pulseaudio pulseaudio-alsa pulseaudio-bluez alsa-plugins-pulse pavucontrol alsa-lib alsa-utils alsaconf
		"

	local _k _a
	for _k in $kernel_flavors; do
		apks="$apks linux-$_k"
		for _a in $kernel_addons; do
			apks="$apks $_a-$_k"
		done
	done

	apkovl="genapkovl-prolight-xfce.sh"
	
	build_section prolightxfce_setup
}
