# Libvirt CPU Isolation Hook
Isolate CPUs when launching Libvirt Virtual Machines.  
For now this script is designed to run on non-SystemD systems and utilizes Control Groups (CGROUP) kernel feature.

### How to check if you have CGROUPs
```
$ zcat /proc/config.gz | grep 'CONFIG_CGROUPS=y' &>/dev/null; if [[ $? == 0 ]]; then echo OK; else echo No CGROUPs; fi
```
**or**
```
$ if [[ -d /sys/fs/cgroup ]]; then echo OK; else echo No CGROUPs; fi 
```

### Minimal python version
You need python version **>=3.6**.  
**Q: Why?**  
Because bash is a little bit weird, this hook uses small python wrapper to spawn a new process. And this hook also needs to redirect all output of fork into /dev/null. And below python 3.6 it's done differently. Tbh on like 99% of linux systems you will have python version higher than this. So no need to worry about this and no need for me to do some weird cross python versions gymnastics.

### How to install:
```
$ mkdir tmp_install_dir
$ git clone --depth 1 https://github.com/music-cat-bread/libvirt-cpu-isolation-hook/tree/main tmp_install_dir
$ cd tmp_install_dir
$ echo $(logname) > username
$ mv vm-config $HOME/.config/
$ chmod 444 $HOME/.config/vm-config
# mkdir -p /etc/libvirt/hooks/qemu.d/
# mv hook.sh username wrapper.py /etc/libvirt/hooks/qemu.d
# chown root:root /etc/libvirt/hooks/qemu.d/{hook.sh,username,wrapper.py}
# chmod 555 /etc/libvirt/hooks/qemu.d/{hook.sh,username}
# chmod 444 /etc/libvirt/hooks/qemu.d/wrapper.py
```

### How to uninstall:
```
# rm /etc/libvirt/hooks/qemu.d/{hook.sh,wrapper.py,username}
$ rm $HOME/.config/vm-config
```

### How to use
Now that hook has been installed, open `$HOME/.config/vm-config` in your favorite text editor.  
By default you will see two examples:
```
gentoo.0,6
gentoo_test.0,6,1,7
```
The general syntax is:
```
YOUR_VM_NAME.CPUS_FOR_HOST
```
`YOUR_VM_NAME` is VM name you chose when creating it (Labeled as `Name` in Virt Manager and virsh, NOT `Title`). After it follows a dot and CPUs you want to leave for your host os.
For example take my Intel i7-9750H.

```
$ lscpu -e=CPU,CORE
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
And as an exmaple let's say that I have following XML config in my gentoo VM
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
XML here takes everything besides thread (labeled as `CPU` in `lscpu`) `0` and `6` for VM. So in that case our `vm-config` would look like this:
```
gentoo.0,6
```
Important note here about threads on systems with hyper threading (aka two threads per core).  
**Intel** doesn't number their thread numbered next to each other. As you can see threads for core `0` are `0` and `6`.  
But **AMD** has them numbered one after another. So for core `0`, thread numbers would be `0` and `1`.  
My recommendation would be to always look at the output and decide which cores **(NOT THREADS)** you wan to leave for your system. And then write down corresponding thread numbers.

### Limitations
 - Doesn't support running multiple isolated VMs at once.
 - Currently you have to define which cores to leave for the system manually. Preferably in future this hook would simply read VM's XML file.

### Debugging
If you have a problem with hook. Do the following:
 - Copy `hook.sh`, `wrapper.py` and `username` to a directory which you have read/write access (so you don't have to use sudo/doas over and over again)
 - Edit `hook.sh` and set SKIP_ROOT to true.

Now hook will:
 - Print many things and don't actually try preform isolation
 - `/tmp/cpu_isolation_hook.lock` is owned by you

Normally libvirt will call this script in one of three ways:  
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
/usr/bin/python wrapper.py bash ./hook.sh PLEASE_FOR_FUCKS_SAKE_DO_NOT_NAME_YOUR_VM_LIKE_THIS <VM_NAME> /tmp/cpu_isolation_hook.lock <CPUS_TO_LEAVE_FOR_HOST>
```
now python will return bash's PID, now write it to lock file
```
echo "VM_NAME.HOOK_PID" > /tmp/cpu_isolation_hook.lock
```
If you want to kill that process. Use `kill -15 PID` (`15` is `SIGTERM`). It will do some cleanup and most importantly de-isolate CPUs when receiving this signal.  
Also important note that this script uses
```
set -euo pipefail
IFS=$'\n\t'
```
which makes bash more stricter.  
Read more about it [here](http://redsymbol.net/articles/unofficial-bash-strict-mode/) to learn about it and some workaround for common things which are done differently.

### Contributing
Just open an issue or pull request. Or report that you had success running this on init systems other than SystemD/OpenRC.

### License
This project is licensed under **MIT License**. See `LICENSE` file for full legal text.