#!/usr/bin/env bash
# Don't even dare to remove those two lines
set -euo pipefail
IFS=$'\n\t'

#                            CPU Isolation hook
#                           For r/VFIO community
#                           and all linux gamers
#
#                              !! WARNING !!
# This script was designed to utilize Contro Groups (CGROUPs) Kernel feature.
# Because SystemD manages CGROUPs, it's not supported (for now). And it's only
# been tested on OpenRC (because I can't be bothered to test anything else), but
# inits like DInit, SysVInit, S6 or RunIt should in theory work perfectly fine
# with this script.
#
# While there's SYSTEMD_FAIL_OVERWRITE to bypass systemd check, I advise against
# using it. You really should just use systemctl.
#
# THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

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
HOOK_DIR=$(dirname $HOOK_FILE)
cd $HOOK_DIR
if [[ ! -f './username' ]]; then
    if [[ -d './username' ]]; then
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
# What python interpreter to use, version >= 3.6
PYTHON_BINARY='/usr/bin/python'
# Lock file location, don't change unless nesesery
LOCK_FILE='/tmp/cpu_isolation_hook.lock'
# Set to true if you want to bypass systemd check
SYSTEMD_FAIL_OVERWRITE=false
# CGroup directory
CGROUP_DIR='/sys/fs/cgroup'
# Debugging, don't enable or else libvirt will spam you with "errors"
DEBUG=true
#  ~*~  Config END  ~*~


# Print only if DEBUG == true.
deb () {
    if [[ ! -z ${1:-} ]] && [[ $DEBUG == true ]]; then
        echo $1
    fi
}

# Don't allow script to be re-run if we crash
make_lock_file_dirty () {
    # We have to execute everything in this function, even if something fails.
    set +euo pipefail

    deb "MAKE LOCK FILE DIRTY"

    # Read lock file data (if any)
    LOCK_DATA=$(cat $LOCK_FILE)
    
    deb "LOCK DATA: $LOCK_DATA"

    # Mark lock file as dirty
    if [[ $LOCK_DATA != "" ]]; then
        echo "$(echo $LOCK_DATA | awk -F '.' '{print $1}').-1"
        deb "GOOD LOCK FILE WRITE"
    else
        echo "ERROR_PHRASING_VM_NAME.-1" > $LOCK_FILE
        deb "LOCK FILE INCORRECT VM NAME"
    fi
    chmod 644 $LOCK_FILE
    chown root:root $LOCK_FILE

    # Allow every process to run on every thread
    CPUs=$(find $CGROUP_DIR -maxdepth 2 -type f -name 'cpuset.cpus' -not -path '*/machine/*')
    for i in $CPUs; do
        $LINE_CPUs=$(lscpu | grep 'On-line CPU(s) list:' | grep -oE '[0-9]*-[0-9]*$')
        echo $LINE_CPUs > $i
        deb "echo \"$LINE_CPUs\" > $i"
    done

    # Exit with code 1. While debugging will be useful.
    exit 1
}

# De-isolate CPUs and remove lock file
exit_watcher () {
    # Get rid of the lock file
    rm -f $LOCK_FILE

    # Nothing to do
    if [[ -z ${1:-} ]]; then
        deb "EXIT WATCHER EMPTY \$1"
        exit 0
    fi

    # We don't care if we fail at this stage
    set +euo pipefail

    deb "RECEIVED SIGTERM"
    deb "TRAP DATA: $1"

    # De-isolate everything
    IFS=!
    for i in $1; do
        deb "$i"
        LAST_STATE=$(echo $i | awk -F '~' '{print $2}')
        if [[ $LAST_STATE == "" ]]; then
            deb "NO LAST STATE"
            VALUE=$(lscpu | grep 'On-line CPU(s) list:' | grep -oE '[0-9]*-[0-9]*$')
        else
            VALUE=$(echo $i | awk -F '~' '{print $2}')
            deb "STATE FOUND: $VALUE"
        fi
        SET_DIR=$(echo $i | awk -F '~' '{print $1}')

        echo "$VALUE" > $SET_DIR
        deb "echo \"$VALUE\" > $SET_DIR"
    done
    IFS=$'\n\t'

    # This is required. Or we will continue watching and de-isolating forever.
    exit 0
}

# Watch for changes. Main debic for forked process
watcher () {
    deb "HOOK with PID $$"
    deb "\$1: $1"
    deb "\$2: $2"

    # Catch SIGTERM (kill -15 $PID)
    trap "exit_watcher" SIGTERM
    # If crash mark lock file as dirty
    trap 'make_lock_file_dirty' ERR

    # Sleep in intervals so sleep doesn't block SIGTERM
    SLEEP_TIME=5
    SLEEP_INTERVAL=0.2
    SLEEP_COUNTER=$(echo "$SLEEP_TIME $SLEEP_INTERVAL" | awk '{print $1 / $2}')
    deb "SLEEP: $SLEEP_TIME = $SLEEP_INTERVAL * $SLEEP_COUNTER"

    # CGROUPs with their last know state
    declare -A CGROUPs

    # This will go on forever until we receive SIGTERM
    deb "HOOK LOOP"
    while true; do
        deb "LOOP CYCLE BEGIN"

        # Libvirt creates a new cgroup called `machine`. Wo don't want to mess
        # with it
        CPUs=$(find $CGROUP_DIR -maxdepth 2 -type f -name 'cpuset.cpus' -not -path '*/machine/*')
        UPDATE=false
        for i in $CPUs; do
            SYS_FS_VALUE=$(cat $i)

            # Check if we have CGROUP's value
            if [[ -z ${CGROUPs[$i]:-} ]]; then
                CGROUPs[$i]=$SYS_FS_VALUE
                deb "$i = $SYS_FS_VALUE"
            fi

            # If we don't have desired isolation, change it
            if [[ $SYS_FS_VALUE != $2 ]]; then
                echo $2 > $i
                UPDATE=true
                deb "UPDATE $i $2 -> $SYS_FS_VALUE"
            fi
        done

        # In case we get asked to stop, we call wrapper_exit. But it needs to
        # restore states, so we need to pass last known states to it. Here we
        # redefine trap argument.
        if [[ $UPDATE == true ]]; then
            NEW_TRAP=""
            for i in "${!CGROUPs[@]}"; do
                NEW_TRAP+="$i~${CGROUPs[$i]}!"
            done
            if [[ $NEW_TRAP != "" ]]; then
                NEW_TRAP=${NEW_TRAP::-1}
            fi
            trap "exit_watcher $NEW_TRAP" SIGTERM
            deb "NEW TRAP $NEW_TRAP"
        fi

        # Sleep for given amount of time.
        # Look at $SLEEP_COUNTER definition above for explanation of this mess.
        deb SLEEP
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

    # Check if we are root
    if [[ "$EUID" != 0 ]]; then
        echo "$HOOK_FILE: ERROR: This hook requires root permissions"
        exit 0
    fi

    # Check if config file is actually a file
    if [[ ! -f $CONFIG_FILE ]]; then
        # Check if it's a directory
        if [[ -d $CONFIG_FILE ]]; then
            echo "$HOOK_FILE: ERROR: $CONFIG_FILE is a directory"
            exit 0
        else # Nothing :(
            echo "$HOOK_FILE: ERROR: $CONFIG_FILE doesn't exist."
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
        deb "NO CONFIG FOUND FOR VM: $1"
        exit 0
    fi

    # If we are starting or restoring VM
    if [[ "$2.$3" == "prepare.begin" || "$2.$3" == "restore.begin" ]]; then
        deb "BEGIN: $2.$3"

        # Handle the lock file
        if [[ -f $LOCK_FILE ]]; then
            deb "$LOCK_FILE EXISTS"

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

        # Fork new process. It will change isolation and keep watching for new
        # CGROUPs. Thanks to reddit.com/u/Academic_Yogurt966 for finding that
        # gentoo's portage creates new cgroup.
        deb "CALLING:"
        deb "$PYTHON_BINARY $HOOK_DIR/wrapper.py /bin/bash $HOOK_FILE PLEASE_FOR_FUCKS_SAKE_DO_NOT_NAME_YOUR_VM_LIKE_THIS $1 $HOST_CPU"
        PID=$($PYTHON_BINARY $HOOK_DIR/wrapper.py /bin/bash $HOOK_FILE PLEASE_FOR_FUCKS_SAKE_DO_NOT_NAME_YOUR_VM_LIKE_THIS $1 $HOST_CPU)

        # Write data to lock file
        touch $LOCK_FILE
        chmod 644 $LOCK_FILE
        chown root:root $LOCK_FILE
        echo "$1.$PID" > $LOCK_FILE
        deb "$LOCK_FILE: "$1.$PID""

        # Exit
        exit 0
    elif [[ "$2.$3" == "release.end" ]] && [[ -f $LOCK_FILE ]]; then
        deb "RELEASE END"

        # We are ending but lock file is dirty. Idk how you would get into this
        # position because you can't run two hooks at the same time but idk.
        if [[ $(cat $LOCK_FILE | awk -F '.' '{print $3}') == "SIGKILL" ]]; then
            deb "LOCK FILE ALREADY DIRTY, IGNORING RELEASE END"
            exit 0
        fi

        # Ask our hook to exit
        # It needs to clear all cpuset.cpus files
        HOOK_PID=$(cat $LOCK_FILE | awk -F '.' '{print $2}')
        deb "HOOK PID: $HOOK_PID"
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

# Check if we have enough variables
if [[ -z ${1:-} || -z ${2:-} || -z ${3:-} ]]; then
    echo "$HOOK_FILE: ERROR: Not enough arguments."
    exit 0
else
    if [[ $1 == 'PLEASE_FOR_FUCKS_SAKE_DO_NOT_NAME_YOUR_VM_LIKE_THIS' ]]; then
        deb "WATCHER CALL"
        watcher $2 $3
        deb "WATCHER END NO DERIVE"
        exit 0
    else
        deb "WRAPPER CALL"
        wrapper $1 $2 $3
        deb "WRAPPER END"
        exit 0
    fi
fi
