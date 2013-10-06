#!/bin/ksh

#=============================================================================
#
# zfs_scrub.sh
# ------------
#
# Scrub Zpools and mail out if there's an issue. Needs a working MTA or it
# won't mail out. Automatically silent when run from cron.
#
# please log changes below
#
# v2.0 first public release
#
# (c) 2011 SearchNet Ltd. Released under BSD license.
#
#=============================================================================

#-----------------------------------------------------------------------------
# VARIABLES

PATH=/usr/bin:/usr/sbin
	# Always set the PATH for safety and security

MAILTO="sysadmin@yourdomain"
	# Who to mail

LOGDEV="local7"
    # System log facility to which we record any errors

#MAILSUCCESS=true
	# Mail whatever the result of the scrub. For testing or the paranoid.
	# Comment out and it will only mail failed scrubs.

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

log()
{
    # Shorthand wrapper to logger, so we are guaranteed a consistent message
    # format. We write through syslog if we're running through cron, through
    # stderr if not

    # $1 is the message
    # $2 is the syslog level. If not supplied, defaults to info

    is_cron \
        && logger -p ${LOGDEV}.${2:-info} "${0##*/}: $1" \
        || print -u2 "ERROR: $1"
}

#-----------------------------------------------------------------------------
# SCRIPT STARTS HERE

# We want to be silent if we're running from cron, but verbose if we aren't.
# This doesn't affect file I/O

is_cron && { exec >&-; exec 2>&-; }

# If a scrub is already running, just exit

zpool status | egrep -s "scrub in progress" \
	&& die "scrub already in progress"

# It takes a long time to do a scrub. We'll check every minute to see
# if it's finished. Use a loop because the 3510 has more than one zpool.
# We're so hardcore here!

zpool list -Ho name | while read pool
do
	START_MSG="pool '${pool}': scrub began" 

	log "$START_MSG"
	is_cron || print "$(date "+%b %d %T") $START_MSG"

	zpool scrub $pool
	sleep 5

	# Keep checking every minute. The sleep 5 above is necessary. Without it
	# the first grep won't match

	while zpool status $1 | egrep -s "scrub in progress"
	do
		sleep 60
	done

	# Okay, we've finished. How did it go?

	if zpool status $pool | egrep -s "with 0 errors"
	then
		END_MSG="pool '${pool}': scrub completed successfully"
		MSG="succeeded"
		LEVEL=""
	else
		END_MSG="pool ${pool}: scrub found errors: $(zpool status $pool \
		| grep "scrub: ")"
		ERR=1
		MSG="failed"
		LEVEL="err"
	fi

	# Report and write to the log

	is_cron || print "$(date "+%b %d %T") $END_MSG"
	log "$END_MSG" $LEVEL

	# Now send a message, if we need to

	if [[ -n "${MAILSUCCESS}$ERR" ]]
	then
		cat <<-EOMAIL | mailx -s "zpool scrub $MSG on $(uname -n)" $MAILTO
		zpool scrub command ${MSG}. Below is the output of zpool
		status $pool:

		$(zpool status $pool)

		Message generated at $(date) by $0
		EOMAIL
	fi

done

# Done!

exit $ERR

