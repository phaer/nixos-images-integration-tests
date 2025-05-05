{module, variant, efiBoot ? true, extraTestScript ? ""}:
{ lib, ... }:
{
  name = "test-image-boot";

  meta.maintainers = with lib.maintainers; [ phaer ];

  nodes.machine = {
    imports = [module];

    config.virtualisation = {
      directBoot.enable = false;
      mountHostNixStore = false;
      useEFIBoot = efiBoot;
    };
  };
  testScript =
    { nodes, ... }:
    let
      image = nodes.machine.system.build.images.${variant};
    in
    ''
      import os
      import subprocess
      import tempfile

      tmp_disk_image = tempfile.NamedTemporaryFile()

      subprocess.run([
        "${nodes.machine.virtualisation.qemu.package}/bin/qemu-img",
        "create",
        "-f",
        "qcow2",
        "-b",
        "${image}/${image.passthru.filePath}",
        "-F",
        "raw",
        tmp_disk_image.name,
      ])

      # Set NIX_DISK_IMAGE so that the qemu script finds the right disk image.
      os.environ['NIX_DISK_IMAGE'] = tmp_disk_image.name

      os_release = machine.succeed("cat /etc/os-release")
      #assert 'IMAGE_ID="nixos"' in os_release
      #assert 'IMAGE_VERSION="25.05test"' in os_release

      ${lib.optionalString efiBoot ''
      bootctl_status = machine.succeed("bootctl status")
      assert "Boot Loader Specification Type #2 (.efi)" in bootctl_status

      ${extraTestScript}
      ''}
    '';
}
