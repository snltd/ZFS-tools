# ZFS Tools

Some tools I wrote (a few years ago now) to assist me in my
day-to-day ZFS business. Probably mostly only of historical interest
now. (Though they are not very interesting.)

They're all written in The One True Shell (`ksh`) and should run
happily under `ksh` or `ksh93` on Solaris 10 or 11, or Illumos
derivatives. I've used them for years with no trouble. They will
most likely work on ZFS equipped bedroom-hobbyist operating systems,
but come with no guarantees.

## zfs_snapshot.sh

I run this from `cron`, and it takes automatic snapshots of my
systems. Solaris has the `auto-snapshot` SMF service for this now,
but `zfs_snapshot.sh` predates that by several years and, IMO, is
simpler to use.

    zfs_snapshot.sh [-pr] [-t day|month|date|time|now] [-o ptn,ptn] zfs
    zfs_snapshot.sh [-pr] [-t day|month|date|time|now] [-o ptn,ptn] -d dir

Options are as follows:

* `-d dir`: snapshots the dataset containing the directory `dir`.
* `-t type`: the type of snapshot to make. This applies an automatic
  naming convention. For example:
  * `-t day    @wednesday`
  * `-t month  @january`
  * `-t date   @2008-30-01`
  * `-t time   @08:45`
  * `-t now    @2008-30-01_08:45:00`
* `-o`: lets you supply a comma-separated list of filesystems which
  you do no want to snapshot. Wildcards are allowed, but must be
  quoted. Useful for omitting, say, all log directories.
* `-p`: "dry-run" mode. Instead of removing the snaps, the script
  will print the `zfs` commands it would use, and exit.
* `-r`: recurse down the dataset heirachy. (`zfs` can do this itself
  now, with its own `-r` option.)

Existing snapshots with the same name are overwritten. With no
arguments, the script snapshots every dataset it finds, though you
can omit things with `-o`.

### Examples

From my own `crontab`.

```
# Snapshot ZFS filesystems every day
#
45 6 * * * /usr/local/bin/zfs_snapshot.sh -t day -o "*build,*logs"

# Snapshot home dirs twice an hour
#
0,30 * * * * /usr/local/bin/zfs_snapshot.sh -t time space/export/home

# Snapshot monthly
#
45 5 1 * * /usr/local/bin/zfs_snapshot.sh -t month -o "*patches,*build,*logs"
```    

## zfs_remove_snap.sh

This script batch-removes ZFS snapshots. It takes the following
options:

* `-d dir`: removes all snapshots in the dataset which contains the
  given directory.
* `-D name`: removes all snapshots belonging to datasets which
  contain `name`, in any pool on the machine. For instance, `-D
  logs` removes all snapshots on all `*/logs` datasets.
* `-n name`: removes snapshots with the given name. That is, the
  part following the `@`. So, say you snapshot with the weekday name
  every day and you want to remove all Monday's snaps, use `-n
  monday`.
* `-r`: tells the script to recurse down datasets. So, if you have a
  pool called `tank`, `-r tank` would remove every snapshot it
  holds.
* `-p`: "dry-run" mode. Instead of removing the snaps, the script
  will print the `zfs` commands it would use, and exit.
* `-h`: print usage and exit.

## zfs_real_usage.sh

The way ZFS reports space can be a little confusing. This script
tells you what datasets and snapshots are taking up real-estate on
disk. It sorts from the least to the most, and takes no options. If
you want to filter, `grep` is your friend.

I've found this script useful when I need to clear some space, and
some deeply buried snapshot somewhere is hogging a stack of room.


## zfs_scrub.sh

This is a wrapper to `zfs scrub`, which I used to run monthly from
`cron`. It scrubs every pool on the box sequentially, and when the
scrub completes, it mails you the result. If you want to
be contacted whether the scrub passes or fails, uncomment the
`MAILSUCCESS` variable. With that commented out, the script only
mails when the scrub finds errors.

By default the script writes its actions to the `syslog`, via the
`LOCAL7` facility.

## zfs_send_stream.sh

This was written in the days before Sun gave us recursive
snapshotting and sending. I wrote it to do full transfers of pools,
including all their snapshots and attributes, between machines.

It has two modes, which we'll call 'send' and 'restore'. Send mode
is invoked like this:

    zfs_send_stream.sh -s <remote_host> -p <remote_pool> <dataset>

* `-s user@host`: this is fed straight to `ssh -C`. It's your
  responsibility to set up the users at each end, and do any
  necessary key exchange.
* `-p pool`: Doesn't necessarily have to be a pool (though I think
  it did in the original version.) It's the top-level target
  dataset on the receiving host.
* `n`: by default, the script will create a file which records all
  the properties of the datasets being sent (more of which in a
  moment.) If you don't want these, use this flag.

Restore mode is run *on the receiving host* like this:

    zfs_send_stream.sh -r <file>

It reads in the properties file I told you about in the `-n` option,
and applies them to the received datasets.

