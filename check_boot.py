import os
import sys
import re
import logging
import argparse
import subprocess
import json
import shutil
import gzip
import time
from tempfile import NamedTemporaryFile
from pathlib import Path

import pexpect
import zstandard


logger = logging.getLogger("run_qemu")
logging.basicConfig(level=logging.DEBUG)


arg_parser = argparse.ArgumentParser()
arg_parser.add_argument("image_name")
arg_parser.add_argument(
    "--interactive",
    help="start an interactive vm for debugging",
    action="store_true")


# Use nom-build if available, else nix-build
NIX_BUILD = shutil.which("nom-build") or shutil.which("nix-build")
if not NIX_BUILD:
    raise Exception("Found neither nom-build nor nix-build")
logger.debug(f"Using {NIX_BUILD}")


def _nix_build(attr):
    return _run(
        NIX_BUILD, "-A", attr,
        capture_output=False,
        stdout=subprocess.PIPE,
        # stdout should still go to the current stdout
    )


def _run(*args, **settings):
    logger.debug(f"executing: {" ".join(args)}")
    kwargs = dict(
        check=True,
        encoding="utf-8",
        capture_output=True)
    kwargs.update(settings)
    try:
        return subprocess.run(
            args, **kwargs
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
          bootEFI = systemd-boot.enable || (grub.enable && grub.efiSupport);
          storePath = image.outPath;
        in {{
          inherit filePath bootEFI storePath;
        }}
        """)
    return json.loads(stdout)


def prepare_efi_boot():
    logger.info("preparing efi boot")
    ovmf_firmware = Path(_nix_build("ovmf")) / "FV/OVMF_CODE.fd"
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


prompt = r"\x1b\[1;31m\[\x1b\]0;root@nixos: ~\x07root@nixos:~\]#\x1b\[0m.*" # noqa


def expect_shell(qemu, command):
    qemu.sendline(command)
    qemu.expect(prompt+command)
    qemu.expect(prompt)
    return qemu.before


def expect_systemctl_status(qemu):
    full_status = expect_shell(qemu, "systemctl status|cat")
    state_re = re.compile(r'\W+State:(.+)')
    state = None
    for line in full_status.split("\r\r\n"):
        if m := state_re.match(line):
            state = m.group(1).strip()
            logger.debug(f"found state: {state}")
            break
    return state


def expect_booted(qemu_command):
    "spawn the qemu vm with pexpect, check systemctl status, shutdown"
    logger.debug(" ".join(qemu_command))
    qemu = pexpect.spawnu(" ".join(qemu_command))
    logfile = open('log.txt', "w")
    qemu.logfile = logfile

    # qemu.expect_exact("Welcome to NixOS")
    # logger.debug("reached welcome")

    qemu.sendline()
    qemu.expect(prompt)
    logger.debug("found prompt, running systemctl status")

    # Search the output of `systemctl status` for the "State" field
    retries = 0
    while retries < 10:
        retries += 1
        state = expect_systemctl_status(qemu)
        if state != "starting":
            break
        time.sleep(1 * retries)

    if state == "running":
        logger.info("vm booted successfully")
    else:
        units = logger.info(expect_shell(qemu, "systemctl|cat"))
        logger.info(f"vm did not boot successfully, state: {state}")
        logger.info(f"units: {units}")
        sys.exit(1)

    # Stop qemu by sending Ctrl-A + x
    logger.debug("stopping vm")
    qemu.sendcontrol("A")
    qemu.send("x")


def decompress_or_copy(source, target):
    if source.suffix == ".zstd":
        logger.info(f"Extracting {source} to {target}")  # noqa
        with open(source, 'rb') as compressed:
            dctx = zstandard.ZstdDecompressor()
            with open(target, 'wb') as out:
                dctx.copy_stream(compressed, out)
    elif source.suffix == ".gz":
        logger.info(f"Extracting {source} to {target}")  # noqa
        with gzip.open(source, 'rb') as compressed:
            with open(target, 'wb') as out:
                shutil.copyfileobj(compressed, out)
    else:
        logger.info(f"Copying {source} to {target} to make it writable.")  # noqa
        shutil.copyfile(source, target)


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
        logger.info(f"image {args.image_name} not found at {readable_image}, building...") # noqa
        stdout = _nix_build(f"images.{args.image_name}")
        logger.info(f"built {stdout}")

    suffix = f"{args.image_name}-{file_path.name if len(file_path.suffixes) < 2 else file_path.stem}" # noqa
    with NamedTemporaryFile(suffix=suffix) as writable_image:
        decompress_or_copy(readable_image, writable_image.name)

        efi_boot = prepare_efi_boot() if info.get("bootEFI") else []
        iso_boot = file_path.suffix == ".iso"

        qemu_net_opts = os.getenv("QEMU_NET_OPTS", "")
        qemu_command = [
            "qemu-system-x86_64",
            "-machine", "type=q35,accel=kvm",
            "-cpu", "host",
            "-m", "2048",
            "-device", "virtio-rng-pci",
            "-net", "nic,netdev=user.0,model=virtio", "-netdev", f"user,id=user.0,{qemu_net_opts}", # noqa
            "-device", "virtio-keyboard",
            "-usb",
            "-device", "usb-tablet,bus=usb-bus.0",
            "-nographic",
            *efi_boot
        ]
        if not iso_boot:
            qemu_command.extend(["-drive", f"file={writable_image.name}"])
        else:
            qemu_command.extend(["-cdrom", writable_image.name])

        if not args.interactive:
            expect_booted(qemu_command)
        else:
            subprocess.run(qemu_command)


if __name__ == '__main__':
    main()
