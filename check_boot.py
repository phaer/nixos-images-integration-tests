import os
import sys
import re
import logging
import argparse
import subprocess
import json
import shutil
import time
from tempfile import NamedTemporaryFile
from pathlib import Path

import pexpect


logger = logging.getLogger("run_qemu")
logging.basicConfig(level=logging.DEBUG)


arg_parser = argparse.ArgumentParser()
arg_parser.add_argument("image_name")


# Use nom-build if available, else nix-build
NIX_BUILD = shutil.which("nom-build") or shutil.which("nix-build")
if not NIX_BUILD:
    raise Exception("Found neither nom-build nor nix-build")
logger.debug(f"Using {NIX_BUILD}")


def _run(*args):
    logger.debug(f"executing: {" ".join(args)}")
    try:
        return subprocess.run(
            args,
            check=True,
            encoding="utf-8",
            capture_output=True
        ).stdout.strip()
    except subprocess.CalledProcessError as e:
        logger.fatal(f"command failed: {e.stderr}")
        sys.exit(1)


def get_image_info(image_name):
    stdout = _run(
        "nix-instantiate",
        "--eval", "--json", "--expr", "--strict",
        f"""
        let
          image = (import ./. {{}}).nixos.images.{image_name};
          inherit (image.passthru) filePath config;
          inherit (config.boot.loader) systemd-boot grub;
          useEFI = systemd-boot.enable || (grub.enable && grub.efiSupport);
          storePath = image.outPath;
        in {{
          inherit filePath useEFI storePath;
        }}
        """)
    return json.loads(stdout)


def prepare_efi_boot():
    logger.info("preparing efi boot")
    ovmf_firmware = Path(_run(NIX_BUILD, "-A", "ovmf")) / "FV/OVMF_CODE.fd"
    efi_vars = Path(os.getenv("NIX_EFI_VARS", "nixos-efi-vars.fd"))
    if not efi_vars.exists():
        logger.debug(f"creating {efi_vars}")
        with open(efi_vars, "wb") as f:
            f.truncate(4096)
    return [
        "-drive",
        f"if=pflash,format=raw,unit=0,readonly=on,file={ovmf_firmware}",
        "-drive",
        f"if=pflash,format=raw,file={efi_vars}"
    ]


def main():
    args = arg_parser.parse_args()
    logger.info(args)

    info = get_image_info(args.image_name)
    print("info", info)
    file_path = Path(info["filePath"])
    store_path = Path(info["storePath"])
    readable_image = store_path / file_path

    # Build image if it isn't cached yet
    if readable_image.exists():
        logger.info(f"found {args.image_name} at {readable_image}.")
    else:
        logger.info(f"image {args.image_name} not found at {readable_image}, building...")
        stdout = _run(
            NIX_BUILD,
            "-A", f"images.{args.image_name}")
        logger.info(f"built {stdout}")

    suffix = f"{args.image_name}-{file_path}"
    with NamedTemporaryFile(suffix=suffix) as writable_image:
        logger.info(f"Copying {readable_image} to {writable_image.name} to make it writable.")  # noqa
        shutil.copyfile(readable_image, writable_image.name)

        efi_boot = prepare_efi_boot() if info.get("useEFI") else []

        qemu_net_opts = os.getenv("QEMU_NET_OPTS", "")
        args = [
            "qemu-system-x86_64",
            "-machine", "type=q35,accel=kvm",
            "-cpu", "host",
            "-m", "2048",
            "-device", "virtio-rng-pci",
            "-device", "vhost-vsock-pci,guest-cid=3",
            "-net", "nic,netdev=user.0,model=virtio", "-netdev", f"user,id=user.0,{qemu_net_opts}", # noqa
            "-device", "virtio-keyboard",
            "-usb",
            "-device", "usb-tablet,bus=usb-bus.0",
            "-nographic",
            *efi_boot,
            "-drive", f"file={writable_image.name}"
        ]
        logger.debug(" ".join(args))
        qemu = pexpect.spawnu(" ".join(args))
        logfile = open('log.txt', "w")
        qemu.logfile = logfile

        prompt = r"\x1b\[1;31m\[\x1b\]0;root@nixos: ~\x07root@nixos:~\]#\x1b\[0m.*" # noqa

        qemu.expect_exact("Welcome to NixOS")
        logger.debug("reached welcome")
        time.sleep(3)

        qemu.sendline()
        qemu.expect(prompt)
        logger.debug("found prompt, running systemctl status")

        # Search the output of `systemctl status` for the "State" field
        qemu.sendline("systemctl status|cat")
        qemu.expect(prompt+"systemctl status|cat")
        qemu.expect(prompt)
        state_re = re.compile(r'\W+State:(.+)')
        state = None
        for line in qemu.before.split("\r\r\n"):
            if m := state_re.match(line):
                state = m.group(1).strip()
                logger.debug(f"found state: {state}")
                break

        # Stop qemu by sending Ctrl-A + x
        logger.debug("stopping vm")
        qemu.sendcontrol("A")
        qemu.send("x")

        if state == "running":
            logger.info("vm booted successfully")
        else:
            logger.info(f"vm did not boot successfully, state: {state}")
            sys.exit(1)


if __name__ == '__main__':
    main()
