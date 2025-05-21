{
  sources ? import ./npins,
  pkgs ? import sources.nixpkgs {},

}:
let
  inherit (pkgs) pkgsLinux;
  inherit (pkgs.lib) listToAttrs map attrNames nameValuePair;

  module = ./host.nix;
  nixos = pkgsLinux.nixos {
    imports = [ module ];
    config.nixpkgs.hostPlatform = pkgsLinux.system;
  };

  inherit (nixos.config.system.build) images;

  ovmf = pkgs.OVMF.fd;
  python = pkgs.python3.withPackages (ps: [ps.pexpect]);
  qemu = pkgs.qemu;
  check-boot = pkgs.writers.writePython3
    "check_boot"
    { libraries = [ pkgs.python3Packages.pexpect ]; }
    (builtins.readFile ./check_boot.py)
    ;

  tests =
    listToAttrs (
      map (variant: nameValuePair
        "boot-${variant}"
        (pkgs.testers.runNixOSTest (import ./tests/boot.nix {
          inherit module variant;
        }))

      ) (attrNames nixos.images));
  shell = pkgs.mkShell {
    packages = [
      qemu
      python
    ];
  };
in
  {
    inherit pkgs pkgsLinux nixos tests images shell ovmf qemu python check-boot;
  }
