import subprocess
import sys

args = sys.argv
args.pop(0)

proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
print(proc.pid)
