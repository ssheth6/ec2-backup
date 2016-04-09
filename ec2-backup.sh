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

        	aws ec2 create-key-pair --key-name ec2BackUpKeyPair --query 'KeyMaterial' --output text > ~/ec2BackUpKeyPair.pem
		#chmod 600 /home/ssheth6/ec2BackUpKeyPair.pem
		groupId=$(aws ec2 create-security-group --group-name ec2-backup-sg --description "EC2 backup tool group" | grep GroupId | head -1 | awk '{print $2}' | sed 's/\"//g')
	        tmp=$(aws ec2 authorize-security-group-ingress --group-name ec2-backup-sg --protocol tcp --port 22 --cidr 0.0.0.0/0)
		echo "Key pair created"
	fi
}

runInstance() {

	#aws ec2-create-group --group-name ec2-backup-sg -d "EC2 backup tool group" 
	#aws ec2 authorize-security-group-ingress --group-name ec2-backup-sg --protocol tcp --port 22 --cidr 0.0.0.0/0
	groupId=$(aws ec2 describe-security-groups --group-names ec2-backup-sg | grep GroupId | head -1 | awk '{print $2}' | sed 's/\"//g')
	instanceId=$(aws ec2 run-instances --instance-type t2.micro --key ec2BackUpKeyPair --image-id ami-fce3c696 --security-group-ids $groupId | grep InstanceId | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
	echo "from echo $instanceId"
	sleep 30
	chmod 400 ~/ec2BackUpKeyPair.pem
	#echo "Adding Security Group"
	#aws ec2 modify-instance-attribute --instance-id $instanceId --groups ec2-backup-sg
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
	if [ "$v"=" " ]; then
		volumeId=$(aws ec2 create-volume --size $SIZE --availability-zone $timeZone --volume-type standard | grep VolumeId | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
		echo $volumeId
		sleep 60
		attachVolume=$(aws ec2 attach-volume --volume-id $volumeId --instance-id $instanceId --device /dev/sdf)
		echo "attached new volume"
	#	mountVolume=$(ssh -o StrictHostKeyChecking=no -i "ec2BackUpKeyPair.pem" ubuntu@$publicDns 'sudo mkfs -t ext4 /dev/xvdf | sleep 10 | sudo mkdir -m 755 /data | sudo mount /dev/xvdf /data -t ext4')
		ssh -t -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "ec2BackUpKeyPair.pem" ubuntu@$publicDns > /dev/null << EOF
		sudo mkfs -t ext4 /dev/xvdf
		sudo mkdir -m 755 /data
		sudo mount /dev/xvdf /data
		df -h
		exit
EOF
		
		echo "Mounted"
	##If volumen flag has a value, check if it is already attached. If so, echo an error and if not use that volume id to attach and mount
	else
        	volumeState=$(aws ec2 describe-volumes --volume-ids $vol | grep State | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
		echo "$volumeState"
		if [ "$volumeState"="attached" ]; then
			echo "Please specify a volume that is available."
		else
			attachVolume=$(aws ec2 attach-volume --volume-id $vol --instance-id $instanceId --device /dev/sdf)
		#	mountVolume=$(ssh -o StrictHostKeyChecking=no -i "ec2BackUpKeyPair.pem" ubuntu@$publicDns 'sudo mkfs -t ext4 /dev/xvdf | sudo mkdir -m 755 /data | sudo mount /dev/xvdf /data -t ext4')
			ssh -t -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "ec2BackUpKeyPair.pem" ubuntu@$publicDns > /dev/null << EOF
                sudo mkfs -t ext4 /dev/xvdf
                sudo mkdir -m 755 /data
                sudo mount /dev/xvdf /data
                df -h
                exit
EOF
		fi
	fi
}

createBackup()
{
        if [ "$m"="rysnc" ];
                then
                #rsync -az $dir ubuntu@$publicDns:/data
		#rsync -avz -e 'ssh -i "ec2BackUpKeyPair.pem" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' $dir ubuntu@$publicDns:/data
		rsync -avzhe "ssh -o StrictHostKeyChecking=no -i ec2BackUpKeyPair.pem" --rsync-path="sudo rsync" $dir ubuntu@$publicDns:/data/

        elif [ "$m"="dd" ];
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
