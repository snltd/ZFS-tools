#!/bin/ksh

#=============================================================================
#
# zfs_remove_snaps.sh
# -------------------
#
# Remove multiple ZFS snapshots in a single command.
#
# Removes all snapshots belonging to a given dataset or directory; all
# snapshots with a given name.
#
# R Fisher 04/2007
#
# Please log all changes below.
#
# v2.0 first public release
#
#=============================================================================

#-----------------------------------------------------------------------------
# VARIABLES

PATH=/usr/bin:/usr/sbin

#-----------------------------------------------------------------------------
# FUNCTIONS

usage()
{
	cat <<-EOUSAGE
	usage:
	  ${0##*/} [-r] dataset [dataset2 ... datasetn]

	  ${0##*/} -D dataset_name [dataset_name2 ... dataset_namen]

	  ${0##*/} -n snap_name

	  ${0##*/} -d dir1 [dir2 ... dirn]

	  ${0##*/} all
	
	where:
	 -d, --dir     : purge the filesystems containing the given dir
	 -D, --dname   : purge ALL datasets called "dname", anywhere in the
	                 heirachy. e.g. "logs" removes snaps for all */logs
	                 filesystems
	 -n, --name    : specifies that args are snapshot names, not fs names,
	                 for example "monday"
	 -p, --print   : only print the commands that would be run
	 -r, --recurse : recurse down datasets
	 -h, --help    : print this message

	EOUSAGE
	exit 2
}

#-----------------------------------------------------------------------------
# SCRIPT STARTS HERE

# We want to be silent if we're running from cron, but verbose if we aren't.
# This doesn't affect file I/O

[[ $(ps -p $$ -otty ) == *pts/* ]] || { exec >&-; exec 2>&-; }

# Got any args?

[[ $# == 0 ]] && usage

# What have we been asked to do?

while getopts "h(help)D(dname)d(dir)n(name)pr(recurse)" option 2>/dev/null
do

	case $option in
		
		D)	DNAME=true
			;;

		d)	DIRS=true
			;;

		n)	NAME=true
			;;

		p)	PRINT=true
			;;

		r)	RECURSE=true
			;;

		*)	usage
			;;

	esac

done

shift $(($OPTIND - 1))

# Prepare the list of snapshot to destroy. Have we been asked to destroy a
# particular class of snapshots, or all snapshots belonging to one of more
# filesystems?

# First, look for directories

if [[ -n $DIRS ]]
then

	for dir in $@
	do
		[[ $dir == /* ]] && d=$dir || d=$(pwd)/$dir
		[[ -d $d ]] && dlist="$dlist $d" || print "skipping $dir"
	done

	if [[ -n $dlist ]]
	then

		# We have $dlist, a list of directories. We need to convert that to
		# a list of the ZFS filesystems those directories are on, without
		# duplicates.  Loop through the list, checking the fs is ZFS, and
		# chop the ZFS name out of df. Once we've done that, get the
		# snapshots belonging to each of those filesystems.

		snaplist=$(zfs list -rH -t snapshot -o name $(df -h \
			$(for d2 in $dlist
			do
				[[ $(df -n $d2) == *": zfs"* ]] && print $d2 \
				|| print -u2 "$d2 is not on a ZFS filesystem - skipping"
			done | sort -u) | sed '1d;s/ .*$//')
		)

		# God, that was horrible. Sorry.

	fi

elif [[ -n $NAME ]]
then

	# Snapshots. This is easy. Just list all snaps on the box and grep for
	# whatever the generic snap name is.  Loop to handle multiple args. I
	# love how zfs(1) has options like -H and -o to make things nice for
	# scripters.

	for ptn in $*
	do
		snaplist=" $snaplist $(zfs list -H -t snapshot -o name \
		| grep @${ptn}$)"
	done

elif [[ -n $DNAME ]]
then
	# We want all filesystems called /arg.

	for dname in $*
	do
		snaplist=" $snaplist $(zfs list -t snapshot -Ho name \
		| egrep "/${dname}@")"
	done

else

	# We've been given dataset names. Probably. If arg[1] is "all", we're
	# looking at all ZFS filesystems on the box.

	[[ $1 == "all" ]] \
		&& fslist=$(zfs list -H -t filesystem -o name) \
		|| fslist="$*"
	
	# We used to use a simple zfs list -r here, but that doesn't let us
	# choose whether or not to recurse

	for fs in $fslist
	do

    	if zfs list -H -t filesystem -o name $fs >/dev/null 2>&1 
		then

			# Get exactly matching snap names

        	snaplist=" $snaplist $(zfs list -rH -t snapshot -o name $fs \
			| egrep ^$fs@)"

			# If recursion is on, get snaps for sub-datasets
			
			[[ -n $RECURSE ]] && \
        		snaplist=" $snaplist $(zfs list -rH -t snapshot -o name $fs \
				| egrep ^$fs/)"

		else
        	print -u2 -- "$fs is not a zfs filesystem"
		fi

	done

fi

# Now we have a list of snapshots to destroy. Let's destroy them. (Unless
# we've been asked not to.)

[[ -z $snaplist ]] && { print "no snapshots to destroy"; exit 0; }

for snap in $snaplist
do

	if [[ -n $PRINT ]]
	then
		print "zfs destroy $snap"
	else
		print -n "  destroying ${snap}: "

		if zfs destroy $snap >/dev/null 2>&1
		then
			print "ok"
		else
			print "failed"
			EXIT=1
		fi

	fi

done

exit $EXIT
