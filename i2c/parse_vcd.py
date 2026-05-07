import sys

vcd_file = sys.argv[1]
with open(vcd_file, 'r') as f:
    lines = f.readlines()

scl_sym = None
sda_sym = None

for line in lines:
    if '$var wire 1' in line and ' scl $' in line:
        scl_sym = line.split()[3]
    if '$var wire 1' in line and ' sda $' in line:
        sda_sym = line.split()[3]

if not scl_sym or not sda_sym:
    print("Could not find scl or sda symbols")
    sys.exit(1)

scl_val = 'x'
sda_val = 'x'
time = 0

print("Time\tSCL\tSDA")
for line in lines:
    if line.startswith('#'):
        time = int(line[1:])
    elif line.endswith(scl_sym + '\n'):
        scl_val = line[0]
        print(f"{time}\t{scl_val}\t{sda_val}")
    elif line.endswith(sda_sym + '\n'):
        sda_val = line[0]
        print(f"{time}\t{scl_val}\t{sda_val}")
