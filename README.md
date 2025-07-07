# timeshift_show_snap_sizes
A program to show approximate timeshift snapshot sizes rapidly

# Purpose

This program strives to show approximate timeshift snapshot sizes far more
rapidly and directionally more accurately than "`du -sh
./timeshift/snapshots/*`" can.

# Methodology

The program collects the "rsync-log-changes" log files for each snapshot and uses
those to estimate the storage used by each snapshot. This method is far
faster than du can achieve because it does not have to visit every single
file (inode). The results also "packs" the bulk of the usage that comes
from files with multiple hardlinks into the most recent snapshot, where
du does that essentially randomly, by assigning usage for a given hardlink
to the directory within which it is first encountered.

The program is to be run with its pwd at the root of the timeshift backup
device or have the snapshots path provided as an argument:

`root@host:/vol/budev $ timeshift_show_snap_sizes.pl ./timeshift/snapshots`

# Motivation and Results

The motivation for this program was that running du over the timeshift USB
harddrive target of my workstation took almost 6 hours to complete and the
results left a lot to be desired.

By comparison, this program completes on the same drive in rougly 5 minutes
and gives far more meaningful results.

# Sample Run

~~~
hightowe@eden /vol/wd_4T_usb_ext4A $ time sudo ./timeshift_show_snap_sizes.pl ./timeshift/snapshots
Processing snapshots underneath ./timeshift/snapshots/...
Snapshots (128):
 - ./timeshift/snapshots/2024-08-01_06-15-39:   0.29G
 - ./timeshift/snapshots/2024-09-01_06-15-38:   0.29G
 - ./timeshift/snapshots/2024-10-01_06-15-31:   0.21G
 - ./timeshift/snapshots/2024-11-01_06-15-31:   0.24G
[...snip...]
 - ./timeshift/snapshots/2025-07-04_05-45-09:   1.45G
 - ./timeshift/snapshots/2025-07-05_05-45-13:   1.39G
 - ./timeshift/snapshots/2025-07-06_05-45-13:   1.32G
 - ./timeshift/snapshots/2025-07-07_05-45-07:   6.02G

Analyzed 128 snapshots...
Snapshot files total: 322.26G
Snapshot dirs estimate:  45.12G (  0.35G each)
Newest snapshot: 223.71G: ./timeshift/snapshots/2025-07-07_05-45-07
Approximate total: 591.10G

NOTE: Directories (usually 4KB each) are estimated and symlinks ignored.

real   5m37.248s
user   0m0.011s
sys    0m0.005s
~~~

# Written By

Lester Hightower, in March of 2025.
