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

# Written By

Lester Hightower, in March of 2025.
