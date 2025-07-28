[
  "lxc-metadata" # covered by nixos/tests/lxc
  "lxc" # covered by nixos/tests/lxc
  "kexec" # covered by nixos/tests/kexec.nix
  "proxmox-lxc" # compressed container tarball
  "google-compute"  # FIXME: eval error, google-guest-configs pkg "not valid". 4 years out of date upstream
  "proxmox"  # FIXME failing build, vm crashes during vma creating
  "vagrant-virtualbox" # FIXME: ova, single file output
  "virtualbox" # FIXME: ova
  "sd-card" # FIXME: uses generic-extlinux bootloader. Maybe do direct boot to test the fs at least?
  "linode" # FIXME: linode uses direct boot, see e.g. https://www.linode.com/community/questions/24318/how-exactly-does-linode-boot-a-disk
  "openstack" # FIXME: reaches multi-user-target but no getty on serial
  "openstack-zfs" # FIXME: reaches multi-user-target but no getty on serial
]
