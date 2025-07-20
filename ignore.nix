[
  "google-compute"  # FIXME: eval error, google-guest-configs pkg "not valid". 4 years out of date upstream
  "lxc-metadata" # compressed container tarball
  "proxmox-lxc" # compressed container tarball
  "lxc" # compressed container tarball
  "iso" # FIXME: iso, "no bootable device"
  "iso-installer" # FIXME: iso,  hangs at "virtual console setup"
  "kexec" # compressed kexec tarball
  "proxmox"  # FIXME failing build, vm crashes during vma creating
  "vagrant-virtualbox" # FIXME: ova, single file output
  "virtualbox" # FIXME: ova
  "sd-card" # FIXME: uses generic-extlinux bootloader. Maybe do direct boot to test the fs at least?
  "linode" # FIXME: linode uses direct boot, see e.g. https://www.linode.com/community/questions/24318/how-exactly-does-linode-boot-a-disk
  "openstack" # FIXME: reaches multi-user-target but no getty on serial
  "openstack-zfs" # FIXME: reaches multi-user-target but no getty on serial
]
