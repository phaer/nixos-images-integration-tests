{
  sources ? import ./npins,
  pkgs ? import sources.nixpkgs {},

}:
let
  inherit (pkgs) pkgsLinux;
  inherit (pkgs.lib) mapAttrs' nameValuePair removeSuffix;

  module = ./host.nix;
  nixos = pkgsLinux.nixos {
    imports = [ module ];
    config.nixpkgs.hostPlatform = pkgsLinux.system;
  };

  inherit (nixos.config.system.build) images;

  tests =
    mapAttrs'
      (n: _v: nameValuePair
        (removeSuffix ".nix" n)
        (pkgs.testers.runNixOSTest (import (./tests + "/${n}") {
          inherit module;
          variant = "repart-efi-gpt";
        }))) (
          builtins.readDir ./tests
        );
in
  {
    inherit pkgs pkgsLinux nixos tests images;
  }
