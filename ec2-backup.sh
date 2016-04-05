#!/bin/bash
##
##FUNCTIONS
##
method_type()
{
	
}

##
##
## Main
##
##
  while getopts ":h:m:v:" o; do
    case "${o}" in
        m)
            m=${OPTARG}
            dir=$3
                echo "$m"
                echo "$dir"
            ;;
        v)
            v=${OPTARG}
         dir=$3
                echo "$v"
                echo "$dir"
          ;;
        h)
            echo "Usage: $0 [-m type of backup] [-v volume-id ]"
            ;;
    esac done

###end of case statement

exit
