{
  sources ? import ./npins,
  pkgs ? import sources.nixpkgs {},

}:
let
  inherit (pkgs) pkgsLinux;

  module = ./host.nix;
  nixos = pkgsLinux.nixos {
    imports = [ module ];
    config.nixpkgs.hostPlatform = pkgsLinux.system;
  };
  inherit (nixos.config.system.build) images;

  ovmf = pkgs.OVMF.fd;
  pythonDeps = ps: [ps.pexpect ps.zstandard];
  python = pkgs.python3.withPackages pythonDeps;
  qemu = pkgs.qemu;
  check-boot = pkgs.writers.writePython3
    "check_boot"
    {
      libraries = pythonDeps pkgs.python3.pkgs;
      makeWrapperArgs = [ "--prefix" "PATH" ":" (pkgs.lib.makeBinPath [ qemu ]) ];
    }
    (builtins.readFile ./check_boot.py)
    ;

  shell = pkgs.mkShell {
    packages = [
      qemu
      python
      pkgs.parallel
    ];
  };
in
  {
    inherit nixos images shell ovmf qemu python check-boot;
  }
