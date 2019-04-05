#!/bin/ksh

#=============================================================================
#
# zfs_real_usage.sh
# -----------------
#
# Shows you what ZFS datasets, be they filesystems or snapshots, are using
# the most disk space.
#
# R Fisher 06/2012
#
#=============================================================================

typeset -R6 size

zfs list -t all -Ho name,used,usedbydataset | while read n u ud
do
	[[ $ud == - ]] && size=$u || size=$ud

	if [[ $size == *K ]]
	then
		sf=3	
	elif [[ $size == *M ]]
	then
		sf=6
	elif [[ $size == *G ]]
	then
		sf=9
	elif [[ $size == *T ]]
	then
		sf=12
	else
		continue
	fi

	print "$(print "scale=0;${size%[A-Z]} * 10 ^ $sf" | bc) $size  $n"
done | sort -n | sed 's/^[^ ]*/ /'


