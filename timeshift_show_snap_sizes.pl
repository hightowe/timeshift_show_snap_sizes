#!/usr/bin/perl

#############################################################################
# A program to show approximate timeshift snapshot sizes far more rapidly
# and directionally more accurate than "du -sh ./timeshift/snapshots/*" can.
#
# It collects the "rsync-log-changes" log files for each snapshot and uses
# those to estimate the storage used by each snapshot. This method is far
# faster than du can achieve because it does not have to visit every single
# file (inode). The results also "packs" the bulk of the usage that comes
# from files with multiple hardlinks into the most recent snapshot, where
# du does that essentially randomly, by assigning usage for a given hardlink
# to the directory within which it is first encountered.
#
# The program is to be run with its pwd at the root of the timeshift backup
# device or have the snapshots path provided as an argument:
#  - root@host /vol/budev $ timeshift_show_snap_sizes.pl ./timeshift/snapshots
#
# Written in March of 2025 by Lester Hightower
#############################################################################

use strict;
use File::Slurp qw(read_file read_dir);
use File::Basename qw(dirname basename);
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use constant KERN_BLKSIZE => 1024; # Wish I knew how to get this from the OS

# Find the Timeshift snapshots' root or die
my $SNAPS_ROOT = undef;
my @snap_roots = qw(
	./timeshift/snapshots
	./snapshots
	);
@snap_roots = ($ARGV[0]) if (defined($ARGV[0]));
snap_roots: for my $snap_root (@snap_roots) {
  if ( ! defined($SNAPS_ROOT) && -d $snap_root) {
    $SNAPS_ROOT = $snap_root;
    last snap_roots;
  }
}
die "Failed to find SNAPS_ROOT in ".Dumper(\@snap_roots)."\n" if (!defined($SNAPS_ROOT));
print "Processing snapshots underneath $SNAPS_ROOT/...\n";

# Gather all of the rsync-log-changes from the snapshots
my @rsync_chg_logs = `find "$SNAPS_ROOT" -maxdepth 2 -type f -name rsync-log-changes`;
chomp @rsync_chg_logs; # Remove trailing newlines
if (scalar(@rsync_chg_logs) < 1) {
  my $cnt = scalar(@rsync_chg_logs);
  die "ERROR: Found no rsync-log-changes files within 2-levels down from $SNAPS_ROOT.\n";
}

# Find the hostname used within the snapshot directories
my @hostname_dirs = `find "$SNAPS_ROOT" -mindepth 2 -maxdepth 2 -type d | awk -F/ '{ print \$NF; }' | sort -u`;
chomp @hostname_dirs; # Remove trailing newlines
if (scalar(@hostname_dirs) != 1) {
  my $cnt = scalar(@hostname_dirs);
  die "ERROR: Found more than one ($cnt) hostname directories at $SNAPS_ROOT.\n";
}
my $HOSTNAME = $hostname_dirs[0];

# Run through the snapshots' rsync-log-changes grabbing just the files
# from each and then totalling up the space used for hardlink=1 files.
my %changed_files = ();
RSYNC_LOG: foreach my $chg_log (@rsync_chg_logs) {
  my @log_lines = read_file($chg_log);
  chomp @log_lines; # Remove trailing newlines

  # Extract just files from the log
  # .d..t...... ./
  # cd..t...... etc/cups/
  # >f..t...... etc/cups/subscriptions.conf
  # >f..t...... etc/cups/subscriptions.conf.O
  my @files = grep(/^>f/, @log_lines);
  @files = map { $_ =~ s/^[^ ]+ //; $_; } @files; # Reduce to just filenames

  # Add the files in the snapshot that are above the hostname; the info.json,
  # rsync logs, etc.
  {
    my $snap_dir = dirname($chg_log);
    my @snap_files = read_dir($snap_dir, prefix => 1);
    unshift(@files, reverse sort @snap_files);
  }

  # The actual snapshot is in "HOSTNAME" at this level
  my $snap_path = dirname($chg_log) . '/' . $HOSTNAME;

  # Go through the @files gathering the sizes
  my %files_sizes = ();
  foreach my $fn (@files) {
    my $fp = $snap_path . '/'. $fn;
    my @stat = stat($fp);
    my $nlink = $stat[3];
    my $size = $stat[7];  # file size (apparent size) not space used
    my $st_blocks = $stat[12]; # Number of kernel blocks allocated
    # $blksize = $stat[11]; # This returns 4096 which != blocks UOM
    # Add this file's size if it appears only in this snapshot
    if ($nlink == 1) {
      if (0) { # Toggle --apparent-size or not
        $files_sizes{$fn} = $size; # same as du --apparent-size
      } else {
        my $kern_size = $st_blocks * KERN_BLKSIZE;
        $files_sizes{$fn} = $kern_size; # the kernel-blocks space used
        # NOTE: I wrote the code just below thinking that the kernel would
        # return st_blocks that would not always align with filesytem blocks,
        # but after writing it I discovered that the st_blocks is always an
        # even multiuple of 4 (equating to 4096, 8192, 12288, etc).
        #die "SHIT!" if ($st_blocks % 4); # THIS NEVER DIES
        #if (0) {
        #  my $disk_size = $kern_size;
        #  my $fsys_blksize = 4096; # stat --printf="%o" /etc/hosts
        #  if (int($disk_size / $fsys_blksize) > 0 && $disk_size % $fsys_blksize) {
        #    $disk_size += $fsys_blksize - ($disk_size % $fsys_blksize);
        #    print "LHHD: $kern_size -> $disk_size\n";
        #  }
        #  $files_sizes{$fn} = $disk_size; # the disk-blocks space used
        #}
      }
    }
  }

  $changed_files{dirname($chg_log)} = \%files_sizes;
  #print Dumper(\%changed_files)."\n"; last RSYNC_LOG;
}

# Run through the snapshots totalling up the space used.
my $grand_total_size = 0;
my %snap_sizes = ();
foreach my $snap_dir (sort keys %changed_files) {
  my $total_size = 0;
  foreach my $size (values %{$changed_files{$snap_dir}}) {
    $total_size += $size;
  }
  $grand_total_size += $total_size;
  $snap_sizes{$snap_dir} = $total_size;
}

# Get the disk usage of the newest snapshot
my $newest_snap = (reverse sort keys %changed_files)[0];
#my $du_sh_newest_snap = `du -sb "$newest_snap" | awk '{print \$1}'`;
my $du_sh_newest_snap = `du -s --block-size=1 "$newest_snap" | awk '{print \$1}'`;
chomp $du_sh_newest_snap;

# Approximate storage used by dirs in the snapshots
my %extras = ();
{
  my @dirs = `find "$newest_snap" -type d`;
  chomp @dirs;
  my @stat = stat($dirs[0]);
  my $dir_size = $stat[7];
  #print "dir_size = $dir_size\n";
  %extras = (
    dir_count => scalar(@dirs),
    dir_sizes => $dir_size,
  );

  # Symlinks don't seem to take up space like dirs do
  #my @symlinks = `find "$newest_snap" -type l`;
  #chomp @symlinks;
  #my @stat = stat($symlinks[0]);
  #my $sym_size = $stat[7];
}

#print Dumper(\%snap_sizes)."\n";
my $snapshots = scalar(keys %changed_files);
print "Snapshots ($snapshots):\n";
foreach my $snap_dir (sort keys %changed_files) {
  print " - $snap_dir: ".to_gb($snap_sizes{$snap_dir})."G\n";
}
print "\n";
print "Analyzed $snapshots snapshots...\n";
print "Snapshot files total: ".to_gb($grand_total_size)."G\n";
my $snapshot_dirs_estimate = $snapshots * $extras{dir_count} * $extras{dir_sizes};
print "Snapshot dirs estimate: ".to_gb($snapshot_dirs_estimate)."G (".to_gb($snapshot_dirs_estimate / $snapshots)."G each)\n";
print "Newest snapshot: ".to_gb($du_sh_newest_snap)."G: $newest_snap\n";
print "Approximate total: ".to_gb($grand_total_size + $du_sh_newest_snap + $snapshot_dirs_estimate)."G\n";
print "\n";
print "NOTE: Directories (usually 4KB each) are estimated and symlinks ignored.\n";

exit;

##############################################################################
##############################################################################
##############################################################################

sub to_gb {
  my $bytes = shift @_;
  return sprintf("%6.2f", $bytes/1024/1024/1024);
}

