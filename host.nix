{modulesPath, ...}: {
  imports = [ "${modulesPath}/profiles/minimal.nix" ];
  config = {
    system.stateVersion = "25.05";
    virtualisation.diskSize = 1024 * 4;
    boot.kernelParams = [ "console=ttyS0,115200n8" ];
    services.getty.autologinUser = "root";

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
