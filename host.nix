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
