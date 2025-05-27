#!/usr/bin/env bash
# short script, i use to iterate locally. Requires a somewhat beefy machines as
# it builds all images and checks whether they boot as expected.
# get a list of all failing builds
# awk '$7 == "1" {print $11} logs/joblog
# get a list of all successful builds
# awk '$7 == "0" {print $11} logs/joblog

mkdir -p logs
nix-instantiate \
    --eval  --json --expr \
    'builtins.filter (n: !(builtins.elem n (import ./ignore.nix))) (builtins.attrNames (import ./. {}).nixos.images)' \
    | jq -cr '.[]' \
    | parallel  \
          --joblog ./logs/joblog \
          "python ./check_boot.py {} 2>&1 | tee logs/{}.txt"
