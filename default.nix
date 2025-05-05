{
  sources ? import ./npins,
  pkgs ? import sources.nixpkgs {},

}:
let
  inherit (pkgs) pkgsLinux;
  inherit (pkgs.lib) listToAttrs map nameValuePair;

  module = ./host.nix;
  nixos = pkgsLinux.nixos {
    imports = [ module ];
    config.nixpkgs.hostPlatform = pkgsLinux.system;
  };

  inherit (nixos.config.system.build) images;

  tests =
    listToAttrs (
      map (variant: nameValuePair
        "boot-${variant}"
        (pkgs.testers.runNixOSTest (import ./tests/boot.nix {
          inherit module variant;
        }))

      ) [
        "repart-efi-gpt"
        "qemu-efi"
      ]);
in
  {
    inherit pkgs pkgsLinux nixos tests images;
  }
