#!/bin/bash
#
# cnc2mdv /etc/group file merger
#
# What it does:
#
#   - Adds three new groups: 
#     - Check if these groups or its gids already exists;
#   - Remove root from the wheel group.
#

destfile=${destfile:-/etc/group}
backupfile=${destfile}.cnc2mdv

# these are the new groups that are introduced by Mandriva
groups=( usb 43 tape 21 nogroup 65534 )

# error codes
group_already_exists_=8
group_already_exists=9
gid_not_unique=4

sort_groups_by_gid()
{
    sort -nt: +2 -3 -o $destfile $destfile #wow

    return 0
}


add_new_groups()
{
    for (( i=0; i < ${#groups[@]}; i += 2)); do 
        n=$[$i+1]
        gid=${groups[$n]}
        gname=${groups[$i]}
        
        errors=yes
        while [ $errors = "yes" ]; do
            groupadd -g $gid $gname
            case $? in
                0)
                    # ok, no errors, group really added
                    errors=no
                ;;
                
                $group_already_exists | $group_already_exists_ )
                    # ok, no problem at all
                    errors=no
                ;;
                
                $gid_not_unique)
                    # bleh, increment gid and try again
                    # hum, but if ... 65534?
                    gid=$[$gid+1]
                ;;

                *)
                    echo "unexpected error during groupadd ($?)"
                    return 1;
                ;;
            esac
        done # while errors
    done # for
    
    return 0
}


remove_root_from_wheel()
{
    sed -i 's/\(wheel:[^:]*:[^:]*:\)root,*\(.*\)/\1\2/' ${destfile}

    return 0
}


main()
{
    add_new_groups &&
        sort_groups_by_gid && 
        remove_root_from_wheel 
}

main

# vim:ts=4:sw=4:ai
