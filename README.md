# Libvirt CPU Isolation Hook
Isolate CPUs when launching Libvirt Virtual Machines.  
For now this script is designed to run on non-SystemD systems and utilizes Control Groups (CGROUPs) kernel feature.  
#### NOTE: Because I am lazy. I didn't test this on anything else than OpenRC. So basically this is OpenRC CPU Isolation Hook with probably some kind of support for other init systems.

### Requirements
 - Bash
   ```
   $ which bash
   ```
 - Kernel with CGROUPs support
   ```
   $ test $(zcat /proc/config.gz | grep 'CONFIG_CGROUPS=y') != "" && echo OK || echo No CGROUPs
   ```
   **or**
   ```
   $ test -d /sys/fs/cgroup && echo OK || echo No CGROUPs
   ```
 - Python >= 3.6
   ```
   $ python --version 
   ```
 - Preferably OpenRC as init system.
   ```
   test openrc && echo OK || echo Init not OpenRC   
   ```
   But others like DInit, SysVInit, S6 and RunIt should work perfectly fine.

### Limitations
 - Doesn't support running multiple isolated VMs at once **(and never will)**
 - Currently you have to define which cores to leave for the system manually. Preferably in future this hook would simply read VM's XML file and check what cores we are left with.

### How to install:
```
$ mkdir tmp_install_dir && git clone --depth 1 https://github.com/music-cat-bread/libvirt-cpu-isolation-hook/tree/main tmp_install_dir && cd tmp_install_dir
$ echo $(logname) > username.template && mv username.template username
$ mv vm-config $HOME/.config/ && chmod 444 $HOME/.config/vm-config
# mkdir -p /etc/libvirt/hooks/qemu.d/
# mv hook.sh username wrapper.py /etc/libvirt/hooks/qemu.d
# chown root:root /etc/libvirt/hooks/qemu.d/{hook.sh,username,wrapper.py}
# chmod 555 /etc/libvirt/hooks/qemu.d/{hook.sh,username}
# chmod 444 /etc/libvirt/hooks/qemu.d/wrapper.py
$ cd .. && rm -r tmp_install_dir
```

### How to uninstall:
```
# rm /etc/libvirt/hooks/qemu.d/{hook.sh,wrapper.py,username}
$ rm $HOME/.config/vm-config
```

### How to use
Open `$HOME/.config/vm-config` in your favorite text editor.  
Syntax is:
```
VM_NAME.CPUs_FOR_HOST
```
To list all your VMs:
```
$ virsh list --all
```
if you don't see anything it might be that you have connected to wrong URI. Try those two:
```
$ virsh -c qemu:///system list --all
$ virsh -c qemu:///session list --all
```
CPU syntax is:
`CPU` (thread) number, separated by `,` or range using `-`.  
Examples:
 - This will only leave threads `0` and `6` for host system and give Windows VM everything else.
   ```
   win10.0,6
   ```
 - This will give VM threads number `0` and `6` to VM and everything else remains for host.
   ```
   suicide_linux.1-5,7-11
   ```
To know which Cores (pairs of threads) to leave for your host use:
```
lscpu -e=CPU,CORE
```
Here's Intel i7-9750H in my Dell Precision 7740 laptop for reference.
```
CPU CORE
  0    0
  1    1
  2    2
  3    3
  4    4
  5    5
  6    0
  7    1
  8    2
  9    3
 10    4
 11    5
```
NOTE: If this was and AMD system it would like more like this:
```
CPU CORE
  0    0
  1    0
  2    1
  3    1
  4    2
  5    2
  6    3
  7    3
  8    4
  9    4
 10    5
 11    5
```
QEMU/KVM will have mapping similar to AMD. So assuming we are following `win10.0,6` example, on Intel system your VM xml would look like this:
```
<cputune>
  <vcpupin vcpu="0" cpuset="1"/>
  <vcpupin vcpu="1" cpuset="7"/>
  <vcpupin vcpu="2" cpuset="2"/>
  <vcpupin vcpu="3" cpuset="8"/>
  <vcpupin vcpu="4" cpuset="3"/>
  <vcpupin vcpu="5" cpuset="9"/>
  <vcpupin vcpu="6" cpuset="4"/>
  <vcpupin vcpu="7" cpuset="10"/>
  <vcpupin vcpu="8" cpuset="5"/>
  <vcpupin vcpu="9" cpuset="11"/>
</cputune>
```
And on AMD system with `win10.0,1` VM more like this:
```
<cputune>
  <vcpupin vcpu="0" cpuset="2"/>
  <vcpupin vcpu="1" cpuset="3"/>
  <vcpupin vcpu="2" cpuset="4"/>
  <vcpupin vcpu="3" cpuset="5"/>
  <vcpupin vcpu="4" cpuset="6"/>
  <vcpupin vcpu="5" cpuset="7"/>
  <vcpupin vcpu="6" cpuset="8"/>
  <vcpupin vcpu="7" cpuset="9"/>
  <vcpupin vcpu="8" cpuset="10"/>
  <vcpupin vcpu="9" cpuset="11"/>
</cputune>
```

### Debugging
If you want to debug then:
 - Edit `hook.sh` and in config section set DEBUG to true

Now hook will:
 - Print many things and don't actually try preform isolation
 - `/tmp/cpu_isolation_hook.lock` is owned by you

Normally libvirt will call this script in one of three ways (for testing purposes you can skip the dash, we never read it anyways):  
 - Starting
   ```
   bash /etc/libvirt/hooks/qemu.d/hook.sh VM_NAME prepare begin -
   ```
 - Restoring
   ```
   bash /etc/libvirt/hooks/qemu.d/hook.sh VM_NAME restore begin -
   ```
 - Stoping
   ```
   bash /etc/libvirt/hooks/qemu.d/hook.sh VM_NAME release end -
   ```

If you want to manually launch forked process that will run in background run:
```
/usr/bin/python wrapper.py bash ./hook.sh PLEASE_FOR_FUCKS_SAKE_DO_NOT_NAME_YOUR_VM_LIKE_THIS <VM_NAME> <CPUS_TO_LEAVE_FOR_HOST>
```
now python wrapper will write bash's PID to stdout. Write it to lock file
```
echo "VM_NAME.HOOK_PID" > /tmp/cpu_isolation_hook.lock
```
If you want to kill that process. Use `kill -15 PID` (`15` is `SIGTERM`). It will do some cleanup and most importantly de-isolate CPUs when receiving this signal.  

Note that I have removed option to run this script without root, because it was quirky. And bugs arising from running in debug mode just kinda defeats it's purpose.  

Also if you want to modify some code note that this hook uses:
```
set -euo pipefail
IFS=$'\n\t'
```
which makes bash more stricter.  
Read about it [here](http://redsymbol.net/articles/unofficial-bash-strict-mode/) to learn more and some workarounds for common things which are done differently.

### Contributing
Just open an issue or pull request. Or report that you had success running this on your system.

### License
This project is licensed under **MIT License**. See `LICENSE` file for full legal text.