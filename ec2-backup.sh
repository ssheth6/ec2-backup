#!/bin/bash

##
##FUNCTIONS


generateKeyPair() {
	echo "Kepy PAir Fun"
	if [ -f ec2BackUpKeyPair.pem ]; then
		echo "Key pair already exists"
	else

        	aws ec2 create-key-pair --key-name ec2BackUpKeyPair --query 'KeyMaterial' --output text > ec2BackUpKeyPair.pem
	
		groupId=$(aws ec2 create-security-group --group-name ec2-backup-sg --description "EC2 backup tool group" | grep GroupId | head -1 | awk '{print $2}' | sed 's/\"//g')
	        tmp=$(aws ec2 authorize-security-group-ingress --group-name ec2-backup-sg --protocol tcp --port 22 --cidr 0.0.0.0/0)
		echo "Key pair created"
	fi
}

runInstance() {
	echo "run Instamce Fun"
	groupId=$(aws ec2 describe-security-groups --group-names ec2-backup-sg | grep GroupId | head -1 | awk '{print $2}' | sed 's/\"//g')
	instanceId=$(aws ec2 run-instances --instance-type t2.micro --key ec2BackUpKeyPair --image-id ami-fce3c696 --security-group-ids $groupId | grep InstanceId | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
	echo "from echo $instanceId"
	sleep 30
	chmod 400 ec2BackUpKeyPair.pem
	publicDns=$(aws ec2 describe-instances --instance-ids $instanceId | grep PublicDns | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
	echo "Public DNS:" $publicDns
	instanceZone=$(aws ec2 describe-instances --instance-ids $instanceId | grep AvailabilityZone | head -1 | awk '{print $2}' | sed 's/\"//g')
	echo "Availability Zone:" $instanceZone
}

createVolume() {
	echo "Create Volume Fun"

        CHECK=$(du -ms $dir | cut -f1)
        if [ $CHECK -lt 1000 ]; then
               
                SIZE=1
        else
                SIZE=$((2*$CHECK/1000))
        fi
	
	##If volume flag value is empty we create a new one and attach
	if [ "$opt_v" == "" ]; then
		volumeId=$(aws ec2 create-volume --size $SIZE --availability-zone $instanceZone --volume-type standard | grep VolumeId | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
		echo $volumeId
		sleep 60
		attachVolume=$(aws ec2 attach-volume --volume-id $volumeId --instance-id $instanceId --device /dev/sdf)
		echo "attached new volume"
	
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
        echo "Create Backup"
	if [ "$opt_m" == "rsync" ];
               then
                  rsync -avzhe "ssh -o StrictHostKeyChecking=no -i ec2BackUpKeyPair.pem" --rsync-path="sudo rsync" $dir ubuntu@$publicDns:/data/

        elif [ "$opt_m" == "dd" ];
                then
               
                timeStamp=$(date "+%Y.%m.%d-%H")
                #tar -cf backup_$timeStamp.tar $dir > /dev/null 2>&1
                echo "Before dd cmd execution"
		tar -cf - $dir | ssh -o StrictHostKeyChecking=no -i "ec2BackUpKeyPair.pem" ubuntu@$publicDns "sudo dd of=/data/dir.tar" conv=sync
		#tar -cf backup_$timeStamp.tar $dir | ssh -o StrictHostKeyChecking=no -i "ec2BackUpKeyPair.pem" ubuntu@$publicDns "sudo dd of=/data/$dir.tar" conv=sync
		#dd if=backup_$timeStamp.tar | (ssh -o StrictHostKeyChecking=no -i "ec2BackUpKeyPair.pem" ubuntu@$publicDns "sudo dd of=/data/backup_$timeStamp.tar" conv=sync)
       		echo "After DD"
	 #elif [ "$opt_m" == "" ]; 
	#then 
	#	timeStamp=$(date "+%Y.%m.%d-%H")
        #        tar -cf backup_$timeStamp.tar $dir > /dev/null 2>&1
        #        dd if=backup_$timeStamp.tar | (ssh -o StrictHostKeyChecking=no -i "ec2BackUpKeyPair.pem" ubuntu@$publicDns sudo dd of=/data/backup_$timeStamp.tar conv=sync)

	else
                echo "Please specify a valid value. Available methods are 'rsync' and 'dd'"
        fi
}

volumeID()
{
	echo "Volume ID Fun"
	generateKeyPair
        runInstance
      	volumeState=$(aws ec2 describe-volumes --volume-ids $vol | grep State | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
        echo "$volumeState"
	volumeZone=$(aws ec2 describe-volumes --volume-ids $vol | grep AvailabilityZone | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
        echo "volumeZone : $volumeZone"
	if [ $volumeState = 'attached' ]; then
		echo "Please specify a volume that is available"
		exit 1
	elif [ $instanceZone != $volumeZone ]; then
		echo "Please provide a Volume that is in the same zone as the instance : $instanceZone"
		exit 1
	else
        	echo "Waiting to be attached"
		sleep 60
		attachVolume=$(aws ec2 attach-volume --volume-id $vol --instance-id $instanceId --device /dev/sdf)
                echo "Attaching Volume"
                ssh -t -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "ec2BackUpKeyPair.pem" ubuntu@$publicDns > /dev/null << EOF
                sudo mkfs -t ext4 /dev/xvdf
                sudo mkdir -m 755 /data
                sudo mount /dev/xvdf /data
                df -h
                exit
EOF

                echo "Mounted"
		

	 fi
	


}

##
## Main
##
##
opt_m=""
opt_v=""

  while getopts ":hm:v:" o; do
    case "${o}" in
        m)
            opt_m=${OPTARG}
            dir=$3
            echo $opt_m
            echo $dir
		#generateKeyPair
		#runInstance
		#createVolume
		#createBackup
		
            ;;
        v)
            opt_v=${OPTARG}
            vol=$opt_v
	    dir=$3
		#volumeID
		#createBackup
                #echo "$v"
                #echo "$dir"
          ;;
        h)
            echo "Usage: $0 [-m type of backup] [-v volume-id ]"
            ;;
    esac done

   if [[ "$opt_m" == "" && "$opt_v" != "" ]]; then
	echo "1"
	opt_m="dd"
	volumeID
	createBackup
   elif [[ "$opt_m" != "" && "$opt_v" == "" ]]; then
	echo "2"
	generateKeyPair
        runInstance
        createVolume
        createBackup
   elif [[ "$opt_m" == "" && "$opt_v" == "" ]]; then
	echo "3"
	opt_m="dd"
	generateKeyPair
        runInstance
        createVolume
        createBackup
   elif [[ "$opt_m" != "" && "$opt_v" != "" ]]; then 
	echo "4"
	echo "$opt_v $opt_m"
	volumeID
        createBackup
  else
	echo "Error"
  fi 

###end of case statement

exit
