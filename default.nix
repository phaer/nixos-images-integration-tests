let
  sources = import ./npins;
  pkgs = import sources.nixpkgs { };

  nixos = pkgs.nixos (
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      config = {
        nixpkgs.hostPlatform = "x86_64-linux";
        system.stateVersion = "25.05";

        image.modules.repart-efi-gpt = (
          {
            lib,
            config,
            modulesPath,
            ...
          }:
          {
            imports = [
              ./images/efi-gpt.nix
              "${modulesPath}/image/file-options.nix"
            ];
            config = {
              boot.loader.systemd-boot.enable = true;
              image = {
                baseName = config.image.repart.imageFileBasename;
                extension = lib.removePrefix "${config.image.repart.imageFileBasename}." config.image.repart.imageFile;
              };
            };
          }
        );
      };
    }
  );
in
{
  inherit nixos;
}
