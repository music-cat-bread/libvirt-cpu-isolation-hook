#!/usr/bin/env bash

#               DIS-D CPU Isolation hook
#                 For r/VFIO community
#                 and all linux gamers
#
#                     !! WARNING !!
# This script was designed to run on linux distributions
# NOT running SystemD, and with CGroups support compiled
# in kernel. Following init systems are theoretically*
# supported like: DInit, RunIt, SySVInit, s6 and OpenRC.
#
# While there's SYSTEMD_FAIL_OVERWRITE to bypass systemd
# check, I advise against using it. Under SystemD most of
# CGroups are managed by systemctl utility and this big,
# multi process hook can be reduced to 6 commands. 3 to
# pin CPUs, and another 3 to un-pin.
#
# I AM NOT RESPONSIBLE FOR ANY ACTION RESULTED IN RUNNING
# THIS SCRIPT, NOR YOU ARE ENTITLED TO BITCH ABOUT LOOSING
# RANDOM CODE THAT YOU COPY PASTED FROM STACK OVERFLOW,
# BUT LOST BECAUSE YOUR SYSTEM FROZE. AND YES I AM GOING
# TO SWEAR BECAUSE NOBODY IS EVER READING WARNINGS OR
# ANY KIND OF "NOT RESPONSIBLE" PARAGRAPH LOL
#
# * I don't have time to test this script on all of those
#   init systems. I only use OpenRC, but in theory this
#   script is init independent on the condition that such
#   init system doesn't screw around with CGroups (I am
#   looking at you, systemd)

# TODO: If should be easy to just use some other set of commands in case of systemd.
#       Maybe I will add systemd support in future. Actually that would make this
#       script kinda interesting. No need to worry about init system and the ease of
#       having easy to edit config file in your home directory would make this very
#       good hook.

# TODO: Make this script directly read VM's xml config file. This would then require
#       zero configuration from user's side and only thing that would need to be
#       defined is XML <cputune> tag.

#    ~*~  Config  ~*~
# Location of file containing VM names and CPUs
CONFIG_FILE=/home/$(cat username)/tmp/hook/vm-config
# CGroup directory
CGROUP_DIR='/sys/fs/cgroup'
# Set to true if you want to bypass systemd check
SYSTEMD_FAIL_OVERWRITE=false
# Skip checking if kernel is compiled with CGROUPs support
SKIP_CGROUP_CHECK=false
# Lock file location, don't change unless nesesery
LOCK_FILE='/tmp/cpu_isolation_hook.lock'
# Don't use this, used only for dev
SKIP_ROOT=true
#  ~*~  Config END  ~*~


# Exit on any error
set -e

# Get location DIR + file name
HOOK_FILE="$(which $0)"

# Watch for changes. Main logic for forked process
watcher () {
    echo WATCHER!
    exit 0
}

# Wrapper. Some checks and config read before we fork.
wrapper () {
    # Check if we have cgroup directory
    if  [[ ! -d $CGROUP_DIR ]]; then
        echo "$HOOK_FILE: ERROR: $CGROUP_DIR doesn't exist"
        exit 0
    fi

    # Check if system is compiled with support for CGROUPs
    if [[ ! $SKIP_CGROUP_CHECK ]]; then
        OUTPUT=$(zcat /proc/config.gz | grep 'CONFIG_CGROUPS=y')
        EXIT_CODE=$?
        if [[ $(echo $OUTPUT | wc -l) == 0 ]] || [[ $EXIT_CODE != 0 ]]; then
            echo "$HOOK_FILE: ERROR: Kernel compiled without CGROUPs support"
            exit 0
        fi
    fi

    # Check if host machine is running SystemD
    # This is official method to check for SystemD
    if  [[ -d '/run/systemd/system' ]] && [[ $SYSTEMD_FAIL_OVERWRITE == false ]]; then
        echo "$HOOK_FILE: ERROR: SystemD detected!"
        exit 0
    fi

    # Check if we are root
    if [[ "$EUID" != 0 ]] && [[ ! $SKIP_ROOT ]]; then
        echo "$HOOK_FILE: ERROR: This hook requires root permissions"
        exit 0
    fi

    # Check if config file is actually a file
    if [[ ! -f $CONFIG_FILE ]]; then
        # Check if it's a directory
        if [[ -d $CONFIG_FILE ]]; then
            echo "$HOOK_FILE: ERROR: $CONFIG_FILE is a directory"
            exit 0
        else # Create if it doesn't exist
            touch $CONFIG_FILE
            chown root:libvirt $CONFIG_FILE
            chmod 660 $CONFIG_FILE
            echo "# Below is example config
    # NOTE: This file is owned by libvirt
    #       group. So if you are in libvirt
    #       group you don't have to use sudo/
    #       doas in order to edit this file.
    example_vm_name.0,6,1-2" > $CONFIG_FILE
            echo "$HOOK_FILE: ERROR: $CGROUP_DIR didn't exist. It's been created. Please now edit it."
            exit 0
        fi
    fi

    # Loop over each line in config file
    HOST_CPU=NOTHING_FOUND
    for i in $(cat $CONFIG_FILE); do
        # Some regex black magic to find our VM in config
        if [[ $(echo $i | grep -Eo "^$1\..*") != "" ]]; then
            HOST_CPU=$(echo $i | grep -Eo "\..*$")
            HOST_CPU=${HOST_CPU:1}
            break
        fi
    done

    # No config for this vm found, ignoring call to hook
    if [[ $HOST_CPU == 'NOTHING_FOUND' ]]; then
        exit 0
    fi

    if [[ "$2.$3" == "prepare.begin" || "$2.$3" == "restore.begin" ]]; then
        if [[ -f $LOCK_FILE ]]; then
            INFO=$(cat $LOCK_FILE)
            echo "$HOOK_FILE: ERROR: VM \"$(echo $INFO | awk -F '.' '{print $1}')\" running with hook PID $(echo $INFO | awk -F '.' '{print $2}'). This script doesn't support running multiple isolated VMs at once."
            exit 0
        fi

        # Fork new process. It will change isolation and keep changing it constantly
        bash $HOOK_FILE I_REALLY_HOPE_NOBODY_IS_GOING_TO_NAME_THEIR_VM_IN_THE_SAME_WAY_AS_THIS $1 $LOCK_FILE $HOST_CPU & disown
    elif [[ "$2.$3" == "release.end" ]] && [[ -f $LOCK_FILE ]]; then
        pkill -9 $(cat $LOCK_FILE | awk -F '.' '{print $2}')
        echo 'CALL DEISOLATE HERE'
        # deIsolate
    fi
}

# Check if we have first argument
# Naive trap to stop anyone from running this script directly
if [ ! -n "$1" ]; then
    echo "$HOOK_FILE: ERROR: No arguments. This script is supposed to be run as QEMU Hook."
    exit 0
elif [[ $1 == 'I_REALLY_HOPE_NOBODY_IS_GOING_TO_NAME_THEIR_VM_IN_THE_SAME_WAY_AS_THIS' ]]; then
    echo FORK!
    watcher $2 $3 $4
    exit 0
else
    wrapper $1 $2 $3
    exit 0
fi

# isolate () {
#     if [ -f $2 ]; then
#         echo "$HOOK_FILE: ERROR: $2 is present. This hook doesn't support running multiple isolated VMs at once."
#         exit 0
#     else
#         touch $2
#     fi

#     echo "+cpuset" > "$CGROUP_DIR/cgroup.subtree_control"
#     for i in $(find $CGROUP_DIR -type f -name 'cpuset.cpus'); do
#         # If we restrict libvirt, it will crash.
#         if [[ $i == "$CGROUP_DIR/machine/cpuset.cpus" ]]; then
#             continue
#         fi
#         echo "${HOSTCPUS[$1]}" > "$i"
#     done
#     exit 0    
# }

# deIsolate () {
#     if [ ! -f $2 ]; then
#         exit 0
#     fi

#     ALLCPUS="0-$(lscpu -e | awk '{print  $  1 }' | grep -i -oE '[0-9]+' | sort -n | tail -n 1)"
#     for i in $(find $CGROUP_DIR -type f -name 'cpuset.cpus'); do
#         echo $ALLCPUS > $i
#     done
#     echo "-cpuset" > '/sys/fs/cgroup/cgroup.subtree_control'
#     rm $2
#     exit 0
# }

# if [[ ${HOSTCPUS[$1]} ]]; then
#     case $2.$3 in
#         "prepare.begin")
#             isolate "$1" "$LOCK_FILE"
#         ;;
#         "restore.begin")
#             isolate "$1" "$LOCK_FILE"
#         ;;
#         "release.end")
#             deIsolate
#         ;;
#         *)
#             exit 0
#         ;;
#     esac
# else
#     exit 0
# fi
