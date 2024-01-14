#!/usr/bin/env bash

# CPU Isolation hook
# By Inspector Parrot
#
# NOTE: This script is intended to be used
#       on non systemd systems, for example:
#       DInit, RunIt, OpenRC, SySVInit.
#       This script utilizes cgroup kernel
#       feature.
#
# GPG Public Key
# NAME: Inspector Parrot
# -----BEGIN PGP PUBLIC KEY BLOCK-----
# mQINBGV2DRwBEAC07afUabelcJIPC30wzU1W4mKDDtib8X6JX8vBf72qI+4WyWLh
# wRGxi+Fm11SbYJ53U0C0qS6VHelOWAYVhA26YAGJN0aLJ19n7GJYkKikpAuVA3QT
# VsNozuJ83iUt0JKRbBhCVz8tMWSMlBeIyqOkTvJGJMSM7QfwbN8akGvLRtkbW93w
# YDfeQ13e7AiRbbjlKY0ry7XIJf68fHpWXxTatPdHoXZ/OYdvqMItwOrq3ABKSiVA
# paJ1gfMlbD4ChJ+m6EyoygE6or4qL+zznlpatIaid+ifwl3HNL73o4zDHKPHu211
# 9vXX1uoPwhgkaGUsWm4YUHqICO/313vZBRs8p80x4Q3yudT2hDjdoDKID65NdK6q
# DxKbf3DdzVpWyB7ftCga9Ay4afUzyR35xxMwWi2sk5YEYSOFiz292JuANtPkyG9J
# v22QGJPeqUPOUTF0t4H80S7IbORJpZWG0HX3LdKG7Q6pnk0gOcAlCs81TY9jebcT
# reaErnqfzI0pBDiT+A1c2czuTKAdvBwB7w+DL3aayG3F/6dAMQ4T/kXT9Nn1fd8q
# Jyya2VX7sZF/8yjqrWC/on5I9wIvJbh+xW7HkvP3OO47PffZg+lEy54ZwDDQWmvG
# dyHvm1qvNdGoZayMERGwK0fLfUYKkQTQMRgzwotz4Ff/TfCG/kak6pTIHwARAQAB
# tBBJbnNwZWN0b3IgUGFycm90iQJRBBMBCAA7FiEEnaWScsMK96286+RxhOFno0y+
# cGAFAmV2DRwCGwMFCwkIBwICIgIGFQoJCAsCBBYCAwECHgcCF4AACgkQhOFno0y+
# cGDCEA/+Ky7hLLA2Hyg9tgSXTOiQHGOiFYigrR9h9v0rTAGmjsintwbd3C/PP0JQ
# RfAyQiO8co0rnqWcbAz+B8t9J2nV6m8QHVguReSIjILr6qm6XjfwvAwYb/LQMzQK
# mFefLYSXSp8Ak0EPWiVXWfrvKbu14qZOhQzBkCNc+l3JIMW5SFlHU98wGe/cROEn
# W/NrJXXvGr0kjrO2PB12x+OBowiTJNKtd/FKvjGKIVOj0NWf//yX0p1dXHILwY9R
# Hg2WbLFWdS5dOBdXlAP6zG3QCf0iYdT2WoRjwJ+uPqw7NiyzQeftQm2DXovGgeYx
# epwbSEvci3L4K7vFK08AIqMDjmvqJKXBMQ5vYFFLP2Vy8PjFwgF4w8Wz7Re/r2o5
# l+taY5zOlBtTZKhZvXqzwjSKvJN1uF1YiYBUNhG2/fTy6D4se4lPhwXJaK+4GG/0
# Q8DeZkz9BldaRc8EeywoJrG1FDZ1xF9WgCjVfPfXDq5Co0HzUOLaoI99Hp7A8M7g
# U6qN/lEGomFSYdZCmU4L9i2z7Uebsf5Bof8I8BgXvPhabQKQqEQA5IMEroQ1lr2l
# BaAi9F7kCdiq4b0CooyzJCjQtDMmrxdNfK/s+7pCSnSeJTwISlfpAo1qts9RWUB+
# LMTAfzr56Q2nQSFE8qMHzl4t4kq+5aeg6gn3VyB3DP1Rs1Hm+Tq5Ag0EZXYNHAEQ
# AOBdeK2nbgWWXDF7tdEiIqRReFUtFlbKXjV5/ojATNrVSx8GluqPtRjNmI4FthFv
# Uy+t8LLFn0S/VAmOr4UyPz+o56ieYBmlsfVNG1hfCSReHsbVpafHGO4AgFxivLjN
# z6PtwtP81lcJJWQtoMzUpA8Qa0KgyBj/yGt0imIQFz3Q+ljbP2asjmxWhCUHMWFX
# ybqSwgmrjqB0m9p5yvQUyNddypGmAeNBr0dcBYhb55BWcsRVn9f5GVa70psof17v
# vffSOnpi0Cj5Tjr3kqnmX5TPC6KdHvCmdPufZqhTwoCst9PzZKzEpgbBVwsUKh1p
# u9W597DDc8/Xs9Eu3u841I8PSkk6cWiZz5KwKOa4RliUV2JaBCqRqC7GsZQqZofd
# CkBf9eTgolCK3esFjWiLvY7xA4AVTRDXKkJMGFAClIs81nRKKl5etRdSu5cToTT2
# unoS4viaC+/jlKNqvzo30utRPe91yssTNuqUW18hRRAjtUgMyDTIfN+PSth02jTb
# Olbyp0FJU8pZRN7Jit5WhFT1Ie37wik/u0CXS/bmyduXLCuuOs+5LTKzmsiJfcyq
# gDe7ymiKjA0PcHJFhLm1xCDTlCm8PA4O15As7wlt5//ms8DR/M9AwzQcX7vf+kjm
# bo8ZKLOIZ5lfpHRK8Y+Jtlm+irE9QWIi1jOzIu28cMLDABEBAAGJAjYEGAEIACAW
# IQSdpZJywwr3rbzr5HGE4WejTL5wYAUCZXYNHAIbDAAKCRCE4WejTL5wYKsKD/0Q
# UbeNU64kS8olYF8i1utoa+jBC1wxh5bZY9okyLprWzgi+UuFBgJPnwcr5YYU3SIY
# Lrhr/blRmviNDBO86CJloZHD4tCDkAr9mgeljqPybb4e7skWIjB9QfJbKUQO+HSj
# LDm34JnnqSpVzsAid19Ur/zdUMARMPW5eXRa+xfe4I0naRJQ3cN2s2u0ZpoKVMIX
# Z9bVXrMAdhHq/XZQwWtKu6kNKTrwDr7DuR2r0526xgb4BBRkO3DQkLCs8cvj6kAt
# Io/i2H1572JboNaMDiz95QofPegFfPxnGfuswLUcoobOoopCMTeeYLBtzNuvfzzi
# utxOPVU+TjedugR3dqPHeUg1+dnxhHIrorg0k94FQ2Ub3EMPL+fQ1knPMTu96rsi
# P7ddUS5dFbx5YoGTbMtPlhJpFJYzqWzYIqx/tkf/s1RVu1B6t8+zAQpWLBb+rNsy
# odedLQZiwBeE2YG6Oc1M1na/s0diIXmpJo4eCo3F4t1k0KSnP5ofYML+22qp2FOp
# lYYPLNN+V+I0YapMSSqIhlY/UkH6rOj+a4hXBwpo5LPUGxlTYJaG4y2SjsSf9msO
# IZyfuWgVf19PGHB4JHQDmbioRj0bIQ/T7ui4uBwqeqqxZcl37YTvusLQff841Hq2
# xUy3YZsMigCf3Gx9sZC7GJ6ZlYv7VyspSAaY0/G06w==
# =2Oko
# -----END PGP PUBLIC KEY BLOCK-----


# CPU ids to leave for host usage
# Dictionary key is VM name
declare -A HOSTCPUS=(
  [gentoo]="0,6"
)
# HOSTCPUS="0,6"
# By default this script will refuse to run if we
# found systemd on user's system. Setting this to
# true will bypass the check.
SYSTEMD_FAIL_OVERWRITE=false
# CGROUP Directory, don't change unless script fails
CGROUP_DIR='/sys/fs/cgroup'

SCRIPT_DIR="$(which $0)"

# Check if we are root
if [[ "$EUID" != 0 ]]; then
    echo "$SCRIPT_DIR: ERROR: This hook requires root permissions"
    exit 0
fi

# Check if we have cgroup directory
if  [[ ! -d $CGROUP_DIR ]]; then
    echo "$SCRIPT_DIR: ERROR: $CGROUP_DIR doesn't exist"
    exit 0
fi

# Check if system is compiled with support for CGROUPS
OUTPUT=$(zcat /proc/config.gz | grep 'CONFIG_CGROUPS=y')
EXIT_CODE=$?
if [[ $(echo $OUTPUT | wc -l) == 0 ]] || [[ $EXIT_CODE != 0 ]]; then
    echo "$SCRIPT_DIR: ERROR: Kernel compiled without CONFIG_CGROUPS=y"
    exit 0
fi

# Check if host machine is running SystemD
# This is official method to check for SystemD
if  [ -d '/run/systemd/system' ] && [[ $SYSTEMD_FAIL_OVERWRITE == false ]]; then
    echo "$SCRIPT_DIR: ERROR: SystemD detected!"
    exit 0
fi

if [ ! -n "$1" ]; then
    echo "$SCRIPT_DIR: ERROR: No \$1. This script is supposed to be run as QEMU Hook."
    exit 0
fi

isolate () {
    if [ -f $2 ]; then
        echo "$SCRIPT_DIR: ERROR: $2 is present. This hook doesn't support running multiple isolated VMs at once."
        exit 0
    else
        touch $2
    fi


    echo "+cpuset" > "$CGROUP_DIR/cgroup.subtree_control"
    for i in $(find $CGROUP_DIR -type f -name 'cpuset.cpus'); do
        # If we restrict libvirt, it will crash.
        if [[ $i == "$CGROUP_DIR/machine/cpuset.cpus" ]]; then
            continue
        fi
        echo "${HOSTCPUS[$1]}" > "$i"
    done
    exit 0    
}

deisolate () {
    if [ ! -f $2 ]; then
        exit 0
    fi

    ALLCPUS="0-$(lscpu -e | awk '{print  $  1 }' | grep -i -oE '[0-9]+' | sort -n | tail -n 1)"
    for i in $(find $CGROUP_DIR -type f -name 'cpuset.cpus'); do
        echo $ALLCPUS > $i
    done
    echo "-cpuset" > '/sys/fs/cgroup/cgroup.subtree_control'
    rm $2
    exit 0
}

LOCK_FILE='/tmp/cpu_isolation_hook.lock'
if [[ ${HOSTCPUS[$1]} ]]; then
    case $2.$3 in
        "prepare.begin")
            isolate "$1" "$LOCK_FILE"
        ;;
        "restore.begin")
            isolate "$1" "$LOCK_FILE"
        ;;
        "release.end")
            deisolate
        ;;
        *)
            exit 0
        ;;
    esac
else
    exit 0
fi
