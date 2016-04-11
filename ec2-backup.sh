#!/bin/bash

##
##FUNCTIONS
##

flags_aws=''
flags_ssh=''
EC2_BACKUP_VERBOSE='false'

generateKeyPair() {

	if [ -n "`echo "$EC2_BACKUP_FLAGS_SSH"`" ]
                then
                flags_ssh="`echo $EC2_BACKUP_FLAGS_SSH`"
                echo "form if loop $flags_ssh"
                key_path=$(echo $flags_ssh | awk '{print $2}')
                key_name=$(echo $key_path | awk -F "/" '{print ($NF)}')
                echo "from if loop $key_path"
                echo "from if loop $key_name"
                if [ ! -e "$key_path" ]
                then
                        echo "The key file does not exist."
                        exit 1
		else
			groupName="ec2-backup"
			checkGroup=$(aws ec2 describe-security-groups --group-names $groupName | grep GroupName | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')	

			if [ "$checkGroup" == "" ];
			then
				groupId=$(aws ec2 create-security-group --group-name $groupName --description "EC2 backup tool group" | grep GroupId | head -1 | awk '{print $2}' | sed 's/\"//g')
                        	tmp=$(aws ec2 authorize-security-group-ingress --group-name $groupName --protocol tcp --port 22 --cidr 0.0.0.0/0)
                	fi
		fi
	else			       
		if [ -f ec2BackUpKeyPair ]; then
			echo "Key pair already exists"
		else
				# Generate a Key Pair and output to users directory where script is executed
				# Generate a Security Group and authorize all IPs via port 22
				# This code ignores the vulnerability of having all IPs able to connect to port 22 
			groupName="ec2-backup-sg"
        		aws ec2 create-key-pair --key-name ec2BackUpKeyPair --query 'KeyMaterial' --output text > ec2BackUpKeyPair
			groupId=$(aws ec2 create-security-group --group-name $groupName --description "EC2 backup tool group" | grep GroupId | head -1 | awk '{print $2}' | sed 's/\"//g')
	        	tmp=$(aws ec2 authorize-security-group-ingress --group-name $groupName --protocol tcp --port 22 --cidr 0.0.0.0/0)
			key_path="ec2BackUpKeyPair"
                        key_name="ec2BackUpKeyPair"
			
			[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "A new Key pair has been created - ec2BackUpKeyPair"
		fi
	fi
}


# The runInstance will either choose the type by user input or by default will use t2.micro
# Since Ubuntu does not have an AMI with t1.micro and t2.micro we will have to use 2 different AMIs for each scenario
# If using the user input, will be forcing a 't1.micro' for AMI - ami-d9dd0eb0
# The Else statement will take a t2.micro for a different AMI - ami-fce3c696
runInstance() {
	echo "run Instance Fun"
	[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "`echo "$EC2_BACKUP_FLAGS_AWS"`"
        if [ -n "`echo "$EC2_BACKUP_FLAGS_AWS"`" ]
        	then
                flags_aws="`echo $EC2_BACKUP_FLAGS_AWS`"
					echo "from if loop $flags_aws"
				groupId=$(aws ec2 describe-security-groups --group-names $groupName | grep GroupId | head -1 | awk '{print $2}' | sed 's/\"//g')
        		instanceId=$(aws ec2 run-instances $flags_aws --key $key_name --image-id ami-d9dd0eb0 --security-group-ids $groupId | grep InstanceId | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
        else
                flags_aws="--instance-type t2.micro"
                	echo "from else loop $flags_aws"
				groupId=$(aws ec2 describe-security-groups --group-names $groupName | grep GroupId | head -1 | awk '{print $2}' | sed 's/\"//g')
        		instanceId=$(aws ec2 run-instances $flags_aws --key $key_name --image-id ami-fce3c696 --security-group-ids $groupId | grep InstanceId | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
        fi
	
	echo "from echo $instanceId"

		# Sleep is required here. Spinning up the Instance takes a bit of time to become visible.
		[ $EC2_BACKUP_VERBOSE = 'true' ] && echo 'Instance creation currently in process'
		[ $EC2_BACKUP_VERBOSE = 'true' ] && echo 'Waiting...'
			sleep 30
			
			# Change access permissions of generated key pair 
			chmod 400 $key_path
			publicDns=$(aws ec2 describe-instances --instance-ids $instanceId | grep PublicDns | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
				[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "Public DNS:" $publicDns
			instanceZone=$(aws ec2 describe-instances --instance-ids $instanceId | grep AvailabilityZone | head -1 | awk '{print $2}' | sed 's/\"//g')
				[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "Availability Zone:" $instanceZone
}

createVolume() {
	echo "Create Volume Fun"

		# Checks the size of the given dir ($dir) and will be used for the create-volume Variable to create volume double the size of the "CHECK"ed directory
        CHECK=$(du -ms $dir | cut -f1)
        if [ $CHECK -lt 1000 ]; then
               
                SIZE=1
        else
                SIZE=$((2*$CHECK/1000))
        fi
	
	##If volume flag value is empty we create a new one and attach
	if [ "$opt_v" == "" ]; then
		volumeId=$(aws ec2 create-volume --size $SIZE --availability-zone $instanceZone --volume-type standard | grep VolumeId | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
			
			# Sleep here is required as it takes a bit of time (1min) for the volume to become visible
			[ $EC2_BACKUP_VERBOSE = 'true' ] && echo "Volume $volumeId created, please wait 1 min"
			[ $EC2_BACKUP_VERBOSE = 'true' ] && echo "Waiting..."
				sleep 60

		attachVolume=$(aws ec2 attach-volume --volume-id $volumeId --instance-id $instanceId --device /dev/sdf)
			[ $EC2_BACKUP_VERBOSE = 'true' ] && echo "New Volume $volumeId has been attached"
	
		# SSH on Remote Host
		# Create the Filesystem
		# Make and Mount Directory
		# Assumes user has "Sudo" permissions available
		ssh -t -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$key_path" ubuntu@$publicDns > /dev/null << EOF
		sudo mkfs -t ext4 /dev/xvdf
		sudo mkdir -m 755 /data
		sudo mount /dev/xvdf /data
		df -h
		exit
EOF
		
		[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "Mounted Complete"
	
	#If volume flag has a value, check if it is already attached. If so, echo an error and if not use that volume id to attach and mount
	else
        	volumeState=$(aws ec2 describe-volumes --volume-ids $vol | grep State | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
				[ $EC2_BACKUP_VERBOSE = 'true' ] && echo "Current Volume: $volumeState"

		if [ "$volumeState"="attached" ]; then
			[ $EC2_BACKUP_VERBOSE = 'true' ] && echo "Error: Please specify a volume that is available."

		else
			attachVolume=$(aws ec2 attach-volume --volume-id $vol --instance-id $instanceId --device /dev/sdf)
		#	mountVolume=$(ssh -o StrictHostKeyChecking=no -i "ec2BackUpKeyPair.pem" ubuntu@$publicDns 'sudo mkfs -t ext4 /dev/xvdf | sudo mkdir -m 755 /data | sudo mount /dev/xvdf /data -t ext4')
					
			# SSH on Remote Host
			# Create the Filesystem
			# Make and Mount Directory
			# Assumes user has "Sudo" permissions available
			ssh -t -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$key_path" ubuntu@$publicDns > /dev/null << EOF
                sudo mkfs -t ext4 /dev/xvdf
                sudo mkdir -m 755 /data
                sudo mount /dev/xvdf /data
                df -h
                exit
EOF
		fi
	fi
}

#
# Mount backup volume to the instance
#
createBackup()
{
    [ $EC2_BACKUP_VERBOSE = 'true' ] && echo "Create Backup"
	if [ "$opt_m" == "rsync" ];
               then
                  rsync -avzhe "ssh -o StrictHostKeyChecking=no -i $key_path" --rsync-path="sudo rsync" $dir ubuntu@$publicDns:/data/

        elif [ "$opt_m" == "dd" ];
                then      
                	timeStamp=$(date "+%Y.%m.%d-%H")
                #tar -cf backup_$timeStamp.tar $dir > /dev/null 2>&1
                	echo "Before dd cmd execution"
                	# Create tar on local host
					tar -cf - $dir | ssh -o StrictHostKeyChecking=no -i "$key_path" ubuntu@$publicDns "sudo dd of=/data/dir.tar" conv=sync
       				echo "After DD"
	else
                echo " Please specify a valid value. Available methods are 'rsync' and 'dd' "
        fi
}

volumeID()
{
	
	echo "Volume ID Fun"
	generateKeyPair
        runInstance
      	#aws ec2 describe-volumes --volume-id $vol 1>/dev/null 2>/dev/null
        #if [ $? -ne 0 ];
        #then
        #        echo "The volume $vol doesn't exist"
        #        terminateInstance
#		exit 1
#        fi

	volumeState=$(aws ec2 describe-volumes --volume-ids $opt_v | grep State | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
        	[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "$volumeState"
		volumeZone=$(aws ec2 describe-volumes --volume-ids $opt_v | grep AvailabilityZone | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
        	[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "volumeZone : $volumeZone"
	
	if [ "$volumeState" == "attached" ]; then
		echo "The volume $opt_v provided is attached"
		terminateInstance
		exit 1
	
	elif [ "$instanceZone" != "$volumeZone" ]; then
		echo "The volume $opt_v is  not in the same availability zone as the instance"
		terminateInstance
		exit 1
	
	else
			# Sleep here is required as it takes a bit of time (1min) for the volume to become visible
        	[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "Waiting to be attached"
        	[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "Waiting..."
				sleep 60
				
			attachVolume=$(aws ec2 attach-volume --volume-id $opt_v --instance-id $instanceId --device /dev/sdf)
                [ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "Attaching Volume"
            
            # SSH on Remote Host
			# Create the Filesystem
			# Make and Mount Directory
			# Assumes user has "Sudo" permissions available
            ssh -t -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$key_path" ubuntu@$publicDns > /dev/null << EOF
            sudo mkfs -t ext4 /dev/xvdf
            sudo mkdir -m 755 /data
            sudo mount /dev/xvdf /data
            df -h
            exit
EOF

                [ $EC2_BACKUP_VERBOSE = 'true' ] && echo "Volume has been Mounted"
		

	 fi
	
}

terminateInstance()
{
	if [ "$instanceId" == "" ]; then 
		[ $EC2_BACKUP_VERBOSE = 'true' ] && echo "No instance was created"
	else
		aws ec2 stop-instances --instance-ids $instanceId 1>/dev/null 2>/dev/null
		aws ec2 terminate-instances --instance-ids $instanceId 1>/dev/null 2>/dev/null
		[ $EC2_BACKUP_VERBOSE = 'true' ] && echo "Instacnes have been terminated"
	fi 
}


function ctrl_c() {
  
      terminateInstance
	exit 1
}

displayHelp()
{
	echo "

	SYNOPSIS:
	ec2-backup [-h] [-m method] [-v volume-id] dir 

	DESCRIPTION:
	ec2-backup accepts the following command-line flags:

	-h	 	   Print a usage statement and exit.

     	-m method	   Use the given method to perform the backup.	Valid methods
			   are 'dd' and 'rsync'; default is 'dd'.

     	-v volume-id	   Use the given volume instead of creating a new one.
	"
	exit 1
}

##
## Main
##
##
opt_m=""
opt_v=""
trap ctrl_c INT

while [ $# -gt 0 ] 
do
	case $1 in
		-h) displayHelp;;
		-m) 
			case $2 in
			dd) opt_m="$2"; echo " m : $opt_m"; shift; shift;;
			rsync) opt_m="$2"; echo "m : $opt_m"; shift; shift;;
			-*) echo "Invalid Parameter"; exit 1;;
			*) echo "Please specify a valid value. Available methods are 'rsync' and 'dd'"; exit 1;;
			esac
			;;
		-v) 
			case $2 in
			vol-*) opt_v="$2";  shift; shift;;
			-*) echo "Invalid Parameter"; exit 1;;
			*) echo "No volume ID was provided"; exit 1;;
			esac
			;;
		-*) displayHelp;;
		 *) 
		 	if [ $# -gt 1 ] 
		 	then
		 		echo "Specify the directory at the end"; displayHelp
		 	else
		 		echo "$1"
				dir=$1; shift
		 	fi
		 	;;
	esac
done

   if [[ "$opt_m" == "" && "$opt_v" != "" ]]; then
	echo "1"
	opt_m="dd"
	volumeID
	createBackup
	terminateInstance
   elif [[ "$opt_m" != "" && "$opt_v" == "" ]]; then
	echo "2"
	generateKeyPair
        runInstance
        createVolume
        createBackup
	terminateInstance
   elif [[ "$opt_m" == "" && "$opt_v" == "" ]]; then
	echo "3"
	opt_m="dd"
	generateKeyPair
        runInstance
        createVolume
        createBackup
	terminateInstance
   elif [[ "$opt_m" != "" && "$opt_v" != "" ]]; then 
	echo "4"
	echo "$opt_v $opt_m"
	volumeID
        createBackup
	terminateInstance
  else
	echo "Error"
  fi 

###end of case statement

exit
