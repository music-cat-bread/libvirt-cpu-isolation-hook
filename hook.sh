#!/usr/bin/env bash
# Don't even dare to remove those two lines
set -euo pipefail
IFS=$'\n\t'

# NOTE: Config is on line 57

#                            CPU Isolation hook
#                           For r/VFIO community
#                           and all linux gamers
#
#                              !! WARNING !!
# This script was designed to run on linux distributions NOT running SystemD,
# and with CGroups support compiled in kernel. Following init systems are
# theoretically* supported like: DInit, RunIt, SySVInit, s6 and OpenRC.
#
# While there's SYSTEMD_FAIL_OVERWRITE to bypass systemd check, I advise against
# using it. Under SystemD most of CGroups are managed by systemctl utility and
# this big, multi process hook can be reduced to 6 commands. 3 to pin CPUs, and
# another 3 to un-pin.
#
# I AM NOT RESPONSIBLE FOR ANY ACTION RESULTED FROM RUNNING THIS SCRIPT, NOR YOU
# ARE ENTITLED TO BITCH ABOUT LOOSING RANDOM CODE THAT YOU COPY PASTED FROM
# STACK OVERFLOW, BUT LOST BECAUSE YOUR SYSTEM FROZE. AND YES I AM GOING TO
# SWEAR BECAUSE NOBODY IS EVER READING WARNINGS OR ANY KIND OF "NOT RESPONSIBLE"
# PARAGRAPHS LOL
#
# * I don't have time to test this script on all of those init systems. I only
#   use OpenRC, but in theory this script is init independent on the condition
#   that such init system doesn't screw around with CGroups (I am looking at
#   you, systemd)

# TODO: If should be easy to just use some other set of commands in case of
#       systemd. Maybe I will add systemd support in future. Actually that would
#       make this script kinda interesting. No need to worry about init system
#       and the ease of having easy to edit config file in your home directory
#       would make this very good hook.

# TODO: Make this script directly read VMs' xml config file. This would then
#       require zero configuration from user's side and only thing that would
#       need to be defined is XML <cputune> tag.

# Check username file as it's needed to be checked before config
HOOK_FILE="$(which $0)"
cd $(dirname $HOOK_FILE)
if [[ ! -f './username' ]];
    then if [[ -d './username' ]]; then
        echo "$HOOK_FILE: ERROR: './username' is a directory, not a file."
        exit 0
    else
        echo "$HOOK_FILE: ERROR: './username' doesn't exist."
        exit 0
    fi
fi


#  ~*~  Config  ~*~
# Location of file containing VM names and CPUs
CONFIG_FILE=/home/$(cat username)/.config/vm-config
# CGroup directory
CGROUP_DIR='/sys/fs/cgroup'
# Set to true if you want to bypass systemd check
SYSTEMD_FAIL_OVERWRITE=false
# Skip checking if kernel is compiled with CGROUPs support
SKIP_CGROUP_CHECK=false
# Lock file location, don't change unless nesesery
LOCK_FILE='/tmp/cpu_isolation_hook.lock'
# What python interpreter to use, version >= 3.6
PYTHON_BINARY='/usr/bin/python'
# Don't use this. It skips some code so it can be tested without requiring me
# to re-type my password every few minutes.
SKIP_ROOT=false
#  ~*~  Config END  ~*~


# Don't allow script to be re-run if we crash
make_lock_file_dirty () {
    # At this point we don't care about being easy to debug, the only thing we
    # have to do is mark lock file as dirty. And crashing without any signs of
    # failure would be VERY annoying
    set +euo pipefail

    # Read lock file data (if any)
    LOCK_DATA=$(cat $LOCK_FILE)
    
    # Mark lock file as dirty
    if [[ $LOCK_DATA != "" ]]; then
        echo "$(echo $LOCK_DATA | awk -F '.' '{print $1}').-1"
    else
        echo "ERROR_PHRASING_VM_NAME.-1" > $LOCK_FILE
    fi
    chmod 644 $LOCK_FILE
    if [[ $SKIP_ROOT == false ]]; then
        chown root:root $LOCK_FILE
    fi

    # Allow every process to run on every thread
    CPUs=$(find $CGROUP_DIR -maxdepth 2 -type f -name 'cpuset.cpus' -not -path '*/machine/*')
    for i in $CPUs; do
        if [[ $SKIP_ROOT == false ]]; then
            echo $(lscpu | grep 'On-line CPU(s) list:' | grep -oE '[0-9]*-[0-9]*$') > $i
        else
            echo "echo \"$(lscpu | grep 'On-line CPU(s) list:' | grep -oE '[0-9]*-[0-9]*$')\" > $i"
        fi
    done

    # Disable CPU set for CGROUPs.
    # In most cases this will fail. Because "device or resource is busy".
    # *shrug*
    if [[ $SKIP_ROOT == false ]]; then
        echo "-cpuset" > "$CGROUP_DIR/cgroup.subtree_control"
    else
        echo "echo \"-cpuset\" > \"$CGROUP_DIR/cgroup.subtree_control\""
    fi

    # If for some reason we are not actually forked. Exit with code 1
    exit 1
}

# De-isolate CPUs and remove lock file
exit_watcher () {
    # We don't care if we fail at this stage
    set +euo pipefail

    # Debug
    if [[ $SKIP_ROOT == true ]]; then
        echo 'RECEIVED SIGTERM'
    fi

    # We got killed really early. Because we didn't redefine trap with new
    # arguments. Don't even bother doing anything.
    if [[ -z ${1:-} ]]; then
        exit 0
    fi

    # De-isolate everything
    IFS=!
    for i in $1; do
        LAST_STATE=$(echo $i | awk -F '~' '{print $2}')
        if [[ $LAST_STATE == "" ]]; then
            VALUE=$(lscpu | grep 'On-line CPU(s) list:' | grep -oE '[0-9]*-[0-9]*$')
        else
            VALUE=$(echo $i | awk -F '~' '{print $2}')
        fi

        if [[ $SKIP_ROOT == false ]]; then
            echo "$LAST_STATE" > $(echo $i | awk -F '~' '{print $1}')
        else
            echo "echo \"$(echo $i | awk -F '~' '{print $2}')\" > $(echo $i | awk -F '~' '{print $1}')"
        fi
    done
    IFS=$'\n\t'

    # Disable CPU set for CGROUPs.
    # In most cases this will fail. Because "device or resource is busy".
    # *shrug* 
    if [[ $SKIP_ROOT == false ]]; then
        echo "-cpuset" > "$CGROUP_DIR/cgroup.subtree_control"
    else
        echo "echo \"-cpuset\" > \"$CGROUP_DIR/cgroup.subtree_control\""
    fi

    # Get rid of the lock file
    rm -f $LOCK_FILE

    # This is required. Or we will continue watching and de-isolating forever.
    exit 0
}

# Watch for changes. Main logic for forked process
watcher () {
    # Debug
    if [[ $SKIP_ROOT == true ]]; then
        echo HOOK with PID $$
        echo "\$1: $1"
        echo "\$2: $2"
        echo "\$3: $3"
    fi

    # Catch SIGTERM (kill -15 $PID) and call exit function Note that this call
    # is not finished and will be updates with saved CGROUPs state later as an
    # argument
    trap "exit_watcher" SIGTERM

    # If we crash at this point we want to mark this hook as failed. Because we
    # forked of, we don't posses any control over vm status. And randomly
    # calling virsh to shut it down is not the best idea. So we just set PID in
    # lock file as -1 and on next launch, user will be informed of the error.
    trap 'make_lock_file_dirty' ERR

    # This workaround is absolutely stupid
    # So when we fork and another process tries to kill us, sleep command will
    # block trap and we will have to wait sometimes like 5 seconds. So we sleep
    # in smaller increments. That doesn't overload the CPU by non-stop reading
    # /sys/fs and also makes script responsive to being killed. For fuck sake,
    # why.
    SLEEP_TIME=5
    SLEEP_INTERVAL=0.2
    SLEEP_COUNTER=$(echo "$SLEEP_TIME $SLEEP_INTERVAL" | awk '{print $1 / $2}')

    # Here we will store CGROUPs with their last known states before starting
    # isolating.
    declare -A CGROUPs

    # Enable CPU set for CGROUPs
    if [[ $SKIP_ROOT == false ]]; then
        echo "+cpuset" > "$CGROUP_DIR/cgroup.subtree_control"
    else
        echo "echo \"+cpuset\" > \"$CGROUP_DIR/cgroup.subtree_control\""
    fi

    # Now we watch till we receive kill -15 (aka SIGTERM)
    while true; do
        # Libvirt creates a new cgroup called `machine`. We don't want to limit
        # it because libvirt needs to have full control over itself in order to
        # use correct CPU threads
        CPUs=$(find $CGROUP_DIR -maxdepth 2 -type f -name 'cpuset.cpus' -not -path '*/machine/*')
        for i in $CPUs; do
            # Check if we don't have that cgroup save it's value
            if [[ -z ${CGROUPs[$i]:-} ]]; then
                CGROUPs[$i]=$(cat $i)
            fi

            # If we don't have desired isolation, change it
            if [[ $(cat $i) != $3 ]]; then
                if [[ $SKIP_ROOT == false ]]; then
                    echo $3 > $i
                else
                    # NOTE: Because we actually never write when SKIP_ROOT is
                    # true. Every time we print this. In reality we would only
                    # do it when the value doesn't match up.
                    echo "echo $3 > $i"
                fi
            fi
        done

        # In case we get asked to stop, we call wrapper_exit.
        # But it needs to restore states, so we need to pass last
        # known states to it. Here we redefine function argument.
        NEW_TRAP=""
        for i in "${!CGROUPs[@]}"; do
            NEW_TRAP+="$i~${CGROUPs[$i]}!"
        done
        if [[ $NEW_TRAP != "" ]]; then
            NEW_TRAP=${NEW_TRAP::-1}
        fi
        trap "exit_watcher $NEW_TRAP" SIGTERM

        # Sleep for given amount of time.
        # Look at $SLEEP_COUNTER definition above for explanation of this mess.
        for i in $(seq $SLEEP_COUNTER); do
            sleep $SLEEP_INTERVAL;
        done
    done
}

# Wrapper. Some checks and config read before we fork.
wrapper () {
    # Check if we have cgroup directory
    if  [[ ! -d $CGROUP_DIR ]]; then
        echo "$HOOK_FILE: ERROR: $CGROUP_DIR doesn't exist"
        exit 0
    fi

    # Check if system is compiled with support for CGROUPs
    if [[ $SKIP_CGROUP_CHECK == false ]]; then
        set +euo pipefail
        OUTPUT=$(zcat /proc/config.gz | grep 'CONFIG_CGROUPS=y')
        EXIT_CODE=$?
        set -euo pipefail
        if [[ $(echo $OUTPUT | wc -l) == 0 ]] || [[ $EXIT_CODE != 0 ]]; then
            echo "$HOOK_FILE: ERROR: Kernel compiled without CGROUPs support"
            exit 0
        fi
    fi

    # Check if host machine is running SystemD
    # This is official method to check for SystemD
    if  [[ -d '/run/systemd/system' && $SYSTEMD_FAIL_OVERWRITE == false ]]; then
        echo "$HOOK_FILE: ERROR: SystemD detected!"
        exit 0
    fi

    # Check if we are root
    if [[ "$EUID" != 0 && ! $SKIP_ROOT ]]; then
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
            if [[ $SKIP_ROOT == false ]]; then
                chown root:libvirt $CONFIG_FILE
            fi
            chmod 660 $CONFIG_FILE
            echo "# Below is example config
# NOTE: This file is owned by libvirt
#       group. So if you are in libvirt
#       group you don't have to use sudo/
#       doas in order to edit this file.
example_vm_name.0,6,1-2" > $CONFIG_FILE
            echo "$HOOK_FILE: ERROR: $CONFIG_FILE didn't exist. It's been created. Please now edit it."
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

    # If we are starting or restoring VM
    if [[ "$2.$3" == "prepare.begin" || "$2.$3" == "restore.begin" ]]; then
        # Handle the lock file
        if [[ -f $LOCK_FILE ]]; then
            set +euo pipefail
            INFO=$(cat $LOCK_FILE)
            if [[ $(echo $INFO | awk -F '.' '{print $2}') == -1 ]]; then
                echo "$HOOK_FILE: ERROR: Forked HOOK has crashed while running VM \"$(echo $INFO | awk -F '.' '{print $1}')\". Please delete $LOCK_FILE and reboot your system."
                chmod 777 $LOCK_FILE
            elif [[ $(echo $INFO | awk -F '.' '{print $3}') == "SIGKILL" ]]; then
                echo "$HOOK_FILE: ERROR: Hook with PID $(echo $INFO | awk -F '.' '{print $2}') didn't exit in 5 seconds. It's been killed with SIGKILL. Please remove $LOCK_FILE and reboot your system."
            else
                echo "$HOOK_FILE: ERROR: VM \"$(echo $INFO | awk -F '.' '{print $1}')\" running with hook PID $(echo $INFO | awk -F '.' '{print $2}'). This script doesn't support running multiple isolated VMs at once."
            fi
            exit 0
        fi

        # Prepare lock file
        touch $LOCK_FILE
        chmod 644 $LOCK_FILE
        if [[ $SKIP_ROOT == false ]]; then
            chown root:root $LOCK_FILE
        fi

        # Fork new process. It will change isolation and keep watching for new
        # CGROUPs. Thanks to reddit.com/u/Academic_Yogurt966 for finding that
        # gentoo's portage creates new cgroup.
        PID=$($PYTHON_BINARY wrapper.py bash $HOOK_FILE PLEASE_FOR_FUCKS_SAKE_DO_NOT_NAME_YOUR_VM_LIKE_THIS $1 $LOCK_FILE $HOST_CPU)

        # Write data to lock file
        echo "$1.$PID" > $LOCK_FILE

        # Exit
        exit 0
    elif [[ "$2.$3" == "release.end" ]] && [[ -f $LOCK_FILE ]]; then
        if [[ $(cat $LOCK_FILE | awk -F '.' '{print $3}') == "SIGKILL" ]]; then
            exit 0
        fi

        # Ask our hook to exit
        # It needs to clear all cpuset.cpus files
        HOOK_PID=$(cat $LOCK_FILE | awk -F '.' '{print $2}')
        set +euo pipefail
        kill -15 $HOOK_PID
        timeout 5 tail --pid=$HOOK_PID -f /dev/null
        HOOK_TIMED_OUT=$?
        if [[ $HOOK_TIMED_OUT != 0 ]]; then
            kill -9 $HOOK_PID
            echo "$HOOK_FILE: ERROR: Hook with PID $HOOK_PID didn't exit in 5 seconds. It's been killed with SIGKILL. Please remove $LOCK_FILE and reboot your system."
            # Get script stuck in a loop. So no VMs get launched
            echo "$(cat $LOCK_FILE).SIGKILL" > $LOCK_FILE
            exit 0
        fi

        set -euo pipefail
    fi
}

# Check if we have first argument
# Naive trap to stop anyone from running this script directly
if [ ! -n "$1" ]; then
    echo "$HOOK_FILE: ERROR: No arguments. This script is supposed to be run as QEMU Hook."
    exit 0
elif [[ $1 == 'PLEASE_FOR_FUCKS_SAKE_DO_NOT_NAME_YOUR_VM_LIKE_THIS' ]]; then
    watcher $2 $3 $4
    exit 0
else
    wrapper $1 $2 $3
    exit 0
fi
