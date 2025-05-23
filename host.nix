{lib, modulesPath, ...}: {
  imports = [ "${modulesPath}/profiles/minimal.nix" ];
  config = {
    system.stateVersion = "25.05";
    virtualisation.diskSize = 1024 * 4;
    boot.kernelParams = [ "console=ttyS0,115200n8" ];

    services.getty.autologinUser = lib.mkForce "root";

    # FIXME: cloud-init can't reach the metadata api and therefore keeps
    # systemd in "starting" state. To include it, it we need to run our
    # own cloud-init server for the VM.
    services.cloud-init.enable = lib.mkForce false;


    # Disable metadata services that require networking for now
    image.modules.amazon = {
      systemd.services.amazon-ssm-agent.enable = lib.mkForce false;
      systemd.services.fetch-ec2-metadata.enable = lib.mkForce false;
    };
    image.modules.azure.systemd.services.consume-hypervisor-entropy.enable = lib.mkForce false;
    image.modules.oci.systemd.services.fetch-ssh-keys.enable = lib.mkForce false;
    image.modules.openstack = {
      systemd.services.openstack-init.enable = lib.mkForce false;
      systemd.services.amazon-init.enable = lib.mkForce false;
    };
    image.modules.openstack-zfs = {
      systemd.services.openstack-init.enable = lib.mkForce false;
      systemd.services.amazon-init.enable = lib.mkForce false;
    };



    # FIXME: wrong image names upstream
    # https://github.com/NixOS/nixpkgs/pull/409571
    #image.modules.amazon.image.extension = lib.mkForce "vhd";
    #image.modules.raw.image.extension = lib.mkForce "img";
    #image.modules.raw-efi.image.extension = lib.mkForce "img";
    #image.modules.sd-card = {config,...}: { image.filePath = lib.mkForce "sd-image/${config.image.fileName}"; };

    image.modules.repart-efi-gpt =
      {...}: {
            imports = [
              ./images/efi-gpt.nix
            ];
            config = {
              boot.loader.systemd-boot.enable = true;
            };
          };
  };
}
