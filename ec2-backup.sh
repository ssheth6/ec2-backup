#!/bin/bash

##
###Begin Variables###
#publicDns= aws ec2 describe-instances | grep PublicDns | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g'
#instanceId= aws ec2 describe-instances | grep InstanceId | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g'
#timeZone= aws ec2 describe-instances | grep AvailabilityZone | awk '{print $2}' | sed 's/\"//g'

#createKeyPair= aws ec2 create-key-pair --key-name ec2BackUpKeyPair --output text > ~/ec2BackUpKeyPair.pem | chmod 600 ~/ec2BackUpKeyPair.pem
#runInstance= aws ec2 run-instances --instance-type t1.micro --key ec2BackUpKeyPair --image-id ami-c27e48aa

#createVolume= aws ec2 create-volume --size $CHECK --availability-zone $timeZone --volume-type standard
#attachVolume= aws ec2 attach-volume --volume-id $volume --instance-id $instanceId --device /dev/sdf

#volume= aws ec2 describe-volumes | grep VolumeId | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g'

#volumeId= aws ec2 describe-volumes | grep VolumeId | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g'

#mount_dir= ssh ec2-user@$publicDns 'sudo su file -s /dev/sdf | mkfs -t ext4 /dev/sdf | mkdir /$dir | mount /dev/sdf /$dir'

#mountVolume= ssh -i ec2BackUpKeyPair.pem ec2-user@$publicDns 'sudo file -s /dev/sdf | sudo mkfs -t ext4 /dev/sdf | sudo mkdir /data | sudo mount /dev/sdf /data'

#volumeState= aws ec2 describe-volumes | grep State | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g'
####End Variables ###
##

##
##FUNCTIONS
##

generateKeyPair() {
	if [ -f ~/ec2BackUpKeyPair.pem ]; then
		echo "Key pair already exists"
	else

        	aws ec2 create-key-pair --key-name ec2BackUpKeyPair --output text > ~/ec2BackUpKeyPair.pem | chmod 600 ~/ec2BackUpKeyPair.pem
		echo "Key pair created"
	fi
}

runInstance() {

	instanceId=$(aws ec2 run-instances --instance-type t1.micro --key ec2BackUpKeyPair --image-id ami-c27e48aa | grep InstanceId | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
	echo "from echo $instanceId"
	#instanceId= $runInstance | grep InstanceId | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g'
        #echo "Instance ID:" $instanceId
	publicDns=$(aws ec2 describe-instances --instance-ids $instanceId | grep PublicDns | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
	echo "Public DNS:" $publicDns
	timeZone=$(aws ec2 describe-instances --instance-ids $instanceId | grep AvailabilityZone | head -1 | awk '{print $2}' | sed 's/\"//g')
	echo "Time Zone:" $timeZone
}

createVolume() {

        CHECK=$(du -ms $dir | cut -f1)
        if [ $CHECK -lt 1000 ]; then
               
                SIZE=1
        else
                SIZE=$((2*$CHECK/1000))
        fi
	
	##If volume flag value is empty we create a new one and attach
	if [ "$v" == " " ]; then
		createVolume=$(aws ec2 create-volume --size $CHECK --availability-zone $timeZone --volume-type standard)
		volumeId=$(aws ec2 describe-volumes | grep VolumeId | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
		echo $volumeId
		attachVolume=$(aws ec2 attach-volume --volume-id $volume --instance-id $instanceId --device /dev/sdf)
		mountVolume=$(ssh -i ec2BackUpKeyPair.pem ec2-user@$publicDns 'sudo file -s /dev/sdf | sudo mkfs -t ext4 /dev/sdf | sudo mkdir /data | sudo mount /dev/sdf /data')
	
	##If volumen flag has a value, check if it is already attached. If so, echo an error and if not use that volume id to attach and mount
	else
        	volumeState=$(aws ec2 describe-volumes | grep State | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
		echo "$volumeState"
		if [ "$volumeState" == "attached" ]; then
			echo "Please specify a volume that is available."
		else
			attachVolume=$(aws ec2 attach-volume --volume-id $vol --instance-id $instanceId --device /dev/sdf)
                	mountVolume=$(ssh -i ec2BackUpKeyPair.pem ec2-user@$publicDns 'sudo file -s /dev/sdf | sudo mkfs -t ext4 /dev/sdf | sudo mkdir /data | sudo mount /dev/sdf /data')
		fi
	fi
}

createBackup()
{
        if [ "$m" == "rysnc" ];
                then
                rsync -az $dir ec2-user@$publicDns:/data
        elif [ "$m" == "dd" ];
		then
                dd if=$dir of=$publicDns:/data bs=$CHECK
	else
		echo "Please specify a valid value. Available methods are 'rsync' and 'dd'"
        fi
}

##
##
## Main
##
##
  while getopts ":hm:v:" o; do
    case "${o}" in
        m)
            m=${OPTARG}
            dir=$3
               # echo $m
               # echo $dir
		generateKeyPair
		runInstance
		createVolume
		createBackup
		
            ;;
        v)
            v=${OPTARG}
            vol=$3
                #echo "$v"
                #echo "$dir"
          ;;
        h)
            echo "Usage: $0 [-m type of backup] [-v volume-id ]"
            ;;
    esac done

###end of case statement

exit
