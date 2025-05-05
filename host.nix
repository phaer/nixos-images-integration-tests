{lib, modulesPath, ...}: {
  imports = [ "${modulesPath}/profiles/minimal.nix" ];
  config = {
    system.stateVersion = "25.05";
    virtualisation.diskSize = 1024 * 2;

    # image setting collides with
    # nixpkgs/nixos/lib/testing/network.nix during testing
    image.modules.amazon.config = {
      ec2.efi = true;
      networking.hostName = lib.mkForce "";
      systemd.services."serial-getty@ttyS0".enable = lib.mkForce true;
    };

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
