#!/bin/ksh

#=============================================================================
#
# zfs_send_stream.sh
# ------------------
#
# Send a heirachy of ZFS filesystems and snapshots across the network to
# another machine. This functionality is (I think) handled by the -R option
# in version 10 of ZFS.
#
# This script also (optionally) records information about each filesystem's
# mountpoints, compression settings etc and copies that to an info file on
# the new machine. That file can then be read back in and the filesystem
# properties restored.
#
# v1.0 initial release
#
# v1.1 Now doesn't send top level dataset, e.g. the "space" filesystem at
#      the top of the "space" pool. This lets you send the entire zpool to
#      another host in one shot. Now checks to see the source pool exists.
#      RDF 16/01/09
#
# R Fisher 08/08
#
#=============================================================================

#-----------------------------------------------------------------------------
# VARIABLES

PATH=/usr/bin:/usr/sbin

#-----------------------------------------------------------------------------
# FUNCTIONS

die()
{
	# Print an error message to stderr and exit

	# $1 is the message to print
	# $2 is the exit code. If not supplied, exit 1
	
	print -u2 "ERROR: $1"
	exit ${2:-1}
}

usage()
{
	# Display usage information and exit
	
	cat <<-EOHELP

	usage:

	  ${0##*/} [-s <target server>] -p <target pool> <filesystem> 

	or:
	
	  ${0##*/} -r <properties_file>

	where:
	    -r, --restore       restore attributes from a properties file
	    -s, --server        the server which will receive the ZFS
	                        filesystems. You need some kind of root
	                        equivalency between the sending and recieving
	                        hosts. Omit this to transfer to a different pool
	                        on the local host
	    -p, --pool          the top of the ZFS heierachy on the receiving
	                        machine
	    -n, --noprops       don't copy the properties of the ZFS filesystems
	                        to the remote server
	    -h, --help          display this message

	EOHELP

	exit 2
}


#-----------------------------------------------------------------------------
# SCRIPT STARTS HERE

# Are we root?

[[ $(id) == "uid=0(root)"* ]] || die "script can only be run by root"

while getopts "s:(server)p:(pool)h:(help)n(noprops)r:(restore)" option
do
	case $option in

		p)	RECV_POOL=$OPTARG
			;;

		s)	RECV_HOST=$OPTARG
			CMD="ssh -C $RECV_HOST"
			;;

		n)	OMIT_PROPS=true
			;;

		r)	PROPS_FILE=$OPTARG
			;;

		*)	usage
		
	esac
done

shift $(($OPTIND - 1))

#- PROPERTIES RESTORE --------------------------------------------------------

# We might just doing a properties restore. This is a nasty two-in-one job.
# Watch out for the exit!

if [[ -n $PROPS_FILE ]]
then
	[[ -s $PROPS_FILE ]] || die "properties file not found"

	while read fs key value
	do
		print -n "setting $key to $value for $fs: "
		zfs set $key=$value $fs && print "ok" || print "FAILED"
	done < $PROPS_FILE

	exit 0

fi

#- ZFS STREAM SEND -----------------------------------------------------------

# We're doing a Check we've got what we need

[[ -n $RECV_POOL ]] || die "ZFS target filesystem not specified (use -p)"

[[ $# == 0 ]] && die "no filesystems specified"

# Is the source actually a ZFS dataset?

zfs list $1 >/dev/null 2>&1 || die "local pool '$1' does not exist"

# If a remote server is being used, see if we can communicate with it, and
# if so, if it has the filesystem we're going to use

if [[ -n $CMD ]]
then
	:
	[[ -n $(ssh $RECV_HOST zfs list -o name $RECV_POOL 2>/dev/null) ]] \
	|| die "no $RECV_POOL on $RECV_HOST, or $RECV_HOST cannot be reached"
else
	zfs list -o name $RECV_POOL >/dev/null 2>&1 \
	|| die "no $RECV_POOL on local host"
fi

if [[ -z $OMIT_PROPS ]]
then
	PROP_FILE="$HOME/zfs_send_$(print $1 | tr / -).properties"
	print "preserving ZFS properties in $PROP_FILE"
	rm -f $PROP_FILE
fi

# Loop through the filesystems. We want exact matches for the supplied
# argument, or subdirectories of that argument

for fs in $(zfs list -t filesystem -o name | sort | egrep "^$1$|^$1/")
do
	print $fs
	unset LAST_SNAP

	# Skip the top level zpool name. This is okay for us, because we don't
	# keep anything in there.

	[[ $fs == */* ]] || continue

	zfs list -t snapshot -o name | grep ^$fs@ | while read snap
	do

		# The first snapshot has to be sent whole, all the others have to be
		# incremental. This is the only way to get them all across. The
		# LAST_SNAP variable remembers what we've just sent, and therefore
		# what to use as the base for the incremental.

		[[ -z $LAST_SNAP ]] && TO_SEND=$snap || TO_SEND="-i $LAST_SNAP $snap"

		print -n "  sending $snap: "

		zfs send $TO_SEND | $CMD zfs receive -d $RECV_POOL \
		&& print "ok" || print "FAILED"

		LAST_SNAP=$snap
	done

	# Now we have take a snapshot RIGHT NOW and send that, so we don't miss
	# anything created after the last existing snapshot

	print -n "  right-now snapshot: "
	SNAPNAME="${fs}@$$.$RANDOM"
	zfs snapshot $SNAPNAME \
	&& print -n "created [$SNAPNAME] " || die "failed to create snapshot"

	[[ -z $LAST_SNAP ]] && TO_SEND=$SNAPNAME || \
	TO_SEND="-i $LAST_SNAP $SNAPNAME"

	zfs send $TO_SEND | $CMD zfs receive -d $RECV_POOL \
	&& print -n "sent " || die "failed to send right-now snapshot"

	zfs destroy $SNAPNAME \
	&& print -n "removed " || die "failed to remove right-now snapshot"

	# Remove the "right now" snapshot on the remote host, so we have the
	# right number of snapshots. After all, "right now" doesn't exist here
	# any more.

	$CMD zfs destroy ${RECV_POOL}/${SNAPNAME#*/} \
	&& print "removed remote" || print "FAILED to remove remote"

	# Now, unless we've been asked not to, record the locally set properties
	# of the filesystem. When you've moved the filesystems to wherever you
	# want them, run this script with -r and the name of the properties file
	# to have everything put back how it used to be.

	if [[ -z $OMIT_PROPS ]]
	then
		print -n "  recording properties: "
		zfs get -H -o name,property,value -s local all $fs  >> $PROP_FILE \
		&& print "ok" || print "FAILED"
	fi

done

