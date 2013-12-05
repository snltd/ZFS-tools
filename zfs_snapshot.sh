#!/bin/ksh

#=============================================================================
#
# zfs_snapshot.sh
# ---------------
#
# Make a snapshot of every ZFS filesystem on the host. It overwrites
# existing snapshots, and has a number of ways of running.
#
#   day - creates a snapshot named after the day of the week. So, if you run
#         it every with "day" as the argument, you'll always have a week's
#         worth of snaps.  If run with no argument, this is the default,
#         because the script was orignally written to keep a week's worth of
#         daily snaps.
#
#  date - creates a snapshot named after today's date. Use this whenever. I
#         find it's useful to run before a big change, or every monday, to
#         keep snaps going back a long way.
#
# month - creates a snapshot named after the month. Run it on the first of
#         month perhaps?
#
#  time - creates a snapshot named with the time in HH:mm. I decided there
#         was a chance of the seconds ticking over if they were used, which,
#         if the script were run from cron, might leave the odd :01 snapshot
#         lying about rather than always overwriting the :00 one
#
#   now - creates a snapshot named with the date and the time, rounded to
#         down to the minute.
#
# This might be run from cron on a server, or by the SMF when a workstation
# boots up. It runs silently on successful execution.
#
# R Fisher 05/2006
#
# v1.0 initial release
#
# v1.1 Only snap filesystems with a proper mountpoint 18/04/2007 RDF
#
# v1.2 Add day/date/month methods RDF
#
# v1.3 More sensible ordering, better reporting, and no output if run by
#      cron RDF 18/07/07
#
# v1.4 Added -o option to omit snapshotting of certain filesystems. RDF
#      20/07/07
#
# v2.0 Major reworking. Now requires that you specify a type of snapshot,
#      allows specification of directories rather than filesystems, using
#      -d. You can also recursively snapshot down a filesystem tree with -r.
#      RDF 08/02/08
#
# v2.1 Bugfix for incorrect exit code. Now counts errors and exits with the
#      number of failed snapshots. RDF 24/12/08
#
# v2.2 Integrated with syslog. Now counts the number of successfully snapped
#      filesystems. RDF 09/01/09
#
# v2.3 Ignores unmounted datasets when doing a recursive snap. Added -V flag
#      to display version number. RDF 21/04/09
#
# v2.4 First public release.
#
#=============================================================================

#-----------------------------------------------------------------------------
# VARIABLES

MYVER=2.4
	# Version number. PLEASE UPDATE!

PATH=/bin:/usr/bin:/sbin:/usr/sbin
	# Always set your PATH. You know where you are when you set your PATH

typeset -l SNAPNAME
	# So snapshot names are always lower case. Upper case has no place on a
	# filesystem

ERRS=0
	# Count failed snapshots

SUCCESS=0
	# Count successfully snapped datasets

#-----------------------------------------------------------------------------
# FUNCTIONS

is_cron()
{
    # Are we being run from cron? True if we are, false if we're not. Value
    # is cached in IS_CRON variable. This works by examining the tty the
    # process is running on. Cron doesn't allocate one, the shells have a
    # pts/n, on Solaris at least

    RET=0

    if [[ -n $IS_CRON ]]
    then
        RET=$IS_CRON
    else
        [[ $(ps -otty= -p$$)  == "?"* ]] || RET=1
        IS_CRON=$RET
    fi

    return $RET

}


die()
{
	# Print an error to standard out and quit.
	# $1 is the message
	# $2 is the optional exit code

    log "$1" "err"
	exit ${2:-1}
}

log()
{
    # Shorthand wrapper to logger, so we are guaranteed a consistent message
    # format. We write through syslog if we're running through cron, through
    # stderr if not

    # $1 is the message
    # $2 is the syslog level. If not supplied, defaults to info

	typeset -u PREFIX

	PREFIX=${2:-info}

    is_cron \
        && logger -p ${LOGDEV}.${2:-info} "${0##*/}: $1" \
        || print -u2 "${PREFIX}: $1"

}

usage()
{
	# Print usage and exit

	cat<<-EOHELP
	usage:
	  ${0##*/} [-pr] [-t day|month|date|time|now] [-o pat1,patn] zfs
	  ${0##*/} [-pr] [-t day|month|date|time|now] [-o pat1,patn] -d dir
	  ${0##*/} -V
	  ${0##*/} -h

	where
	  zfs           : is any number of ZFS filesystems. If no arguments are
	                  supplied, the script will snapshot all mounted ZFS
	                  filesystems
	  dir           : is any number of directories

	options
	  -d, --dir     : snapshot the filesystem containing the given directory
	  -t, --type    : type of snapshot to do, determines snapshot name(s)
	                  e.g  day    @wednesday
	                       month  @january
	                       date   @2008-30-01
	                       time   @08:45
	                       now    @2008-30-01_08:45:00
	  -o, --omit    : comma separated list of filesystems to omit from
	                  snapshot.  Wildcards are allowed, but must be quoted
	  -p, --print   : only print the commands that would be run
	  -r, --recurse : recursively select down filesystem trees

	  -V, --version : print version number and exit

	  -h, --help    : print this message

	  e.g. ${0##*/} -o "*logs" -t day
	       produces a snap called $(date "+%A"), omitting all filesystems
	       whose names end with "logs"

	EOHELP
	exit 2
}

#-----------------------------------------------------------------------------
# SCRIPT STARTS HERE

# We want to be silent if we're running from cron, but verbose if we aren't.
# This doesn't affect file I/O

is_cron && { exec >&-; exec 2>&-; }

# Make sure we have ZFS filesystems on this host

whence zfs >/dev/null \
	|| die "zfs command not found" 2

[[ "$(zfs list)" == "no datasets found" ]] \
	&& die "no zfs datasets found" 3

# What are were going to do?

while getopts "h(help)d(dir)p(print)o:(omit)r(recurse)t:(type)V(version)" \
option \
	2>/dev/null
do

    case $option in

		d)	DIRS=true
			;;

		p)	PRINT=true
			;;

		o)	OMIT=$OPTARG
			;;

		r)	RECURSE=true
			;;

		t)	TYPE=$OPTARG
			;;

		V)	print $MYVER
			exit 0
			;;

		*)	usage
			;;

	esac

done

shift $(( $OPTIND -1 ))

# If we've been given -d, we need args

[[ -n $DIRS && $# == 0 ]] && usage

case $TYPE in

	"date")	SNAPNAME=$(date "+%Y-%m-%d")
			;;

	"day")	SNAPNAME=$(date "+%A")
			;;

	"month") SNAPNAME=$(date "+%B")
			;;

	"now")	SNAPNAME=$(date "+%Y-%m-%d_%H:%M")
			;;

	"time")	SNAPNAME=$(date "+%H:%M")
			;;

esac

[[ -z $SNAPNAME ]] && die "No snapshot type selected (use -t)"

# Make a list, SNAPLIST, of ZFS filesystems the user wants us to snapshot.

if [[ -n $DIRS ]]
then

    for dir in $@
    do
        [[ $dir == /* ]] && d=$dir || d=$(pwd)/$dir
        [[ -d $d ]] && dlist="$dlist $d" || print "skipping $dir"
    done

    # We have $dlist, a list of directories. We need to convert that to a
    # list of the ZFS filesystems those directories are on, without
    # duplicates.  Loop through the list, checking the fs is ZFS, and chop
    # the ZFS name out of df.

    SNAPLIST=$(zfs list -rH -t filesystem -o name $(df -h \
        $(for d2 in $dlist
        do
            [[ $(df -n $d2) == *": zfs"* ]] && print $d2 \
            || print -u2 "$d2 is not on a ZFS filesystem - skipping"
        done | sort -u) | sed '1d;s/ .*$//')
    )

    # God, that was horrible. Sorry.
elif [[ $# -gt 0 ]]
then
	# We've been given a list of ZFS filesystems to snap. Have we also been
	# asked to recurse? awk filters out unmounted filesystems, which we
	# don't want to snap

	if [[ -n $RECURSE ]]
	then
		SNAPLIST=$(for z in $@
		do
			zfs list -rH -t filesystem -o name,mountpoint $z
		done | awk '{

			if ($2 != "none")
				print $1

			}' | sort -u)
	else
		SNAPLIST="$@"
	fi

else
	# We're going to snapshot EVERYTHING mounted
	SNAPLIST=$(zfs list -H -o name,mountpoint -t filesystem \
	| sed '/none$/d;s/	.*//')
fi

[[ -z $SNAPLIST ]] && die "no valid ZFS filesystems supplied"

# Go through the snapshot list

for fs in $SNAPLIST
do

	if [[ -n $OMIT ]]
	then

		# Just match this filesystem against everything in the list. I know
		# this isn't very efficient coding, but it'll do for this purpose.
		# The condition lets the user supply wildcards, so long as they are
		# protected from the shell with quotes.

		unset SKIP

		for pattern in $(print $OMIT | tr "," " ")
		do
			[[ $fs == $pattern ]] && SKIP=TRUE
		done

		[[ -n $SKIP ]] && continue
	fi

	SNAP="${fs}@$SNAPNAME"

	# See if we have a snapshot. If we have one with this name, remove it

	if zfs list -H -t snapshot -o name | egrep -s "^$SNAP$"
	then
		[[ -n $PRINT ]] \
			&&  print "zfs destroy $SNAP" \
			|| zfs destroy $SNAP
	fi

	# Take a snapshot. ZFS is sweet.

	if [[ -n $PRINT ]]
	then
		print "zfs snapshot $SNAP"
	else
		print -n "snapshotting ${fs}: "

		if zfs snapshot $SNAP
		then
			print "ok"
			((SUCCESS = $SUCCESS + 1))
		else
			print "FAILED"
			((ERRS = $ERRS + 1))
		fi

	fi

done

# Write our progress to the system log

[[ $ERRS == 0 ]] && LEVEL="" || LEVEL="err"

log "${0##*/} completed. $SUCCESS datasets snapped, $ERRS failed" $LEVEL

exit $ERRS

