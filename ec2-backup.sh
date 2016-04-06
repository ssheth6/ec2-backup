#!/bin/bash


##Begin Variables##
publicDns= aws ec2 describe-instances | grep PublicDns | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g'
instanceId= aws ec2 describe-instances | grep InstanceId | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g'
timeZone= aws ec2 describe-instances | grep AvailabilityZone | awk '{print $2}' | sed 's/\"//g'

createKeyPair= aws ec2 create-key-pair --key-name ec2BackUpKeyPair --output text > ~/ec2BackUpKeyPair.pem | chmod 600 ~/ec2BackUpKeyPair.pem
runInstance= aws ec2 run-instances --instance-type t1.micro --key ec2BackUpKeyPair --image-id ami-c27e48aa

createVolume= aws ec2 create-volume --size $CHECK --availability-zone $timeZone --volume-type standard
attachVolume= aws ec2 attach-volume --volume-id $volume --instance-id $instanceId --device /dev/sdf

volume= aws ec2 describe-volumes | grep VolumeId volume.txt | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g'

mount_dir= ssh ec2-user@$publicDns 'sudo su file -s /dev/sdf | mkfs -t ext4 /dev/sdf | mkdir /$dir | mount /dev/sdf /$dir'
####End Variables ###


##
##FUNCTIONS
##
method_type()
{
	if [$m = rysnc]
		then
			rsync -az $dir ec2-user@$publicDns:/dev/sdf
	else
		dd if=$dir of=$publicDns:/dev/sdf bs=$CHECK
	fi	
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
                #echo "$m"
                #echo "$dir"
            ;;
        v)
            v=${OPTARG}
         dir=$3
                #echo "$v"
                #echo "$dir"
          ;;
        h)
            echo "Usage: $0 [-m type of backup] [-v volume-id ]"
            ;;
    esac done

###end of case statement

exit
