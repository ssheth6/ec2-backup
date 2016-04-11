#!/bin/bash 
#title			:ec2-backup.sh
#description	:This script will back up a local directory to an AWS EC2 Volume
#authors		:Sneha Sheth, Smruthi Karinat, Ramit Farwaha
#date			:April 11, 2016 
#version		:0.1
#bash_version	:4.2.25(1)-release
#=======================================================================================

##
##FUNCTIONS
##

flags_aws=''
flags_ssh=''
verbose=false

# echo >&2 message text...
# > redirect standard output
# & what comes next is a file descriptor, not a file (only for right hand side of >
# this links the command's stdout to the current stderr
verbose() {
  if [[ ! -z $EC2_BACKUP_VERBOSE ]]; 
  	then
    	echo $@ >&2
  fi
}

generateKeyPair() {

	if [ -n "`echo "$EC2_BACKUP_FLAGS_SSH"`" ]
                then
                flags_ssh="`echo $EC2_BACKUP_FLAGS_SSH`"
                key_path=$(echo $flags_ssh | awk '{print $2}')
                key_name=$(echo $key_path | awk -F "/" '{print ($NF)}')
                if [ ! -e "$key_path" ]
                then
                        echo "The key file does not exist."
                        exit 1
		else
			groupName="ec2-backup"
			checkGroup=$(aws ec2 describe-security-groups --group-names $groupName | grep GroupName | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g') 1>/dev/null 2>/dev/null
				verbose "Your Group Name is $groupName"	
			if [ "$checkGroup" == "" ];
			then
				verbose "Currently checking Security Group..."
				groupId=$(aws ec2 create-security-group --group-name $groupName --description "EC2 backup tool group" | grep GroupId | head -1 | awk '{print $2}' | sed 's/\"//g')
                        	tmp=$(aws ec2 authorize-security-group-ingress --group-name $groupName --protocol tcp --port 22 --cidr 0.0.0.0/0)
                	fi
		fi
	else
	# Check if a key pair already exisit and use the existing instead of creating a new on the fly			       
		if [ -f ec2BackUpKeyPair ]; then
			verbose "Key pair already exists"
			groupName="ec2-backup-sg"
			key_path="ec2BackUpKeyPair"
                        key_name="ec2BackUpKeyPair"
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
	[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "`echo "$EC2_BACKUP_FLAGS_AWS"`"
        if [ -n "`echo "$EC2_BACKUP_FLAGS_AWS"`" ]
        	then
                flags_aws="`echo $EC2_BACKUP_FLAGS_AWS`"
				groupId=$(aws ec2 describe-security-groups --group-names $groupName | grep GroupId | head -1 | awk '{print $2}' | sed 's/\"//g')
        		instanceId=$(aws ec2 run-instances $flags_aws --key $key_name --image-id ami-d9dd0eb0 --security-group-ids $groupId | grep InstanceId | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
        			[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "$flags_aws"
        else
                flags_aws="--instance-type t2.micro"
				groupId=$(aws ec2 describe-security-groups --group-names $groupName | grep GroupId | head -1 | awk '{print $2}' | sed 's/\"//g')
        		instanceId=$(aws ec2 run-instances $flags_aws --key $key_name --image-id ami-fce3c696 --security-group-ids $groupId | grep InstanceId | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
        			[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "$flags_aws"
        fi
	
		# Sleep is required here. Spinning up the Instance takes a bit of time to become visible.
		verbose 'Instance creation currently in process'
		verbose 'Waiting...'
			sleep 30
			
			# Change access permissions of generated key pair 
			chmod 400 $key_path
			publicDns=$(aws ec2 describe-instances --instance-ids $instanceId | grep PublicDns | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
				[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "Public DNS:" $publicDns
			instanceZone=$(aws ec2 describe-instances --instance-ids $instanceId | grep AvailabilityZone | head -1 | awk '{print $2}' | sed 's/\"//g')
				[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "Availability Zone:" $instanceZone
}

createVolume() {

		# Checks the size of the given dir ($dir) and will be used for the create-volume Variable to create volume double the size of the "CHECK"ed directory
        CHECK=$(du -ms $dir | cut -f1)
        if [ $CHECK -lt 1000 ]; then
               
                SIZE=1
        else
                SIZE=$((2*$CHECK/1000))
        fi
	
		# If volume flag value is empty we create a new one and attach
		if [ "$opt_v" == "" ]; then
			volumeId=$(aws ec2 create-volume --size $SIZE --availability-zone $instanceZone --volume-type standard | grep VolumeId | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
				echo "$volumeId"
				# Sleep here is required as it takes a bit of time (1min) for the volume to become visible
				verbose "Volume $volumeId created, please wait 1 min"
				verbose "Waiting..."
					sleep 60

			attachVolume=$(aws ec2 attach-volume --volume-id $volumeId --instance-id $instanceId --device /dev/sdf)
				verbose "New Volume $volumeId has been attached"
	
		# SSH on Remote Host
		# Create the Filesystem
		# Make and Mount Directory
		# Assumes user has "Sudo" permissions available
		ssh -t -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$key_path" ubuntu@$publicDns 1>/dev/null 2>/dev/null << EOF
		sudo mkfs -t ext4 /dev/xvdf 1>/dev/null 2>/dev/null
		sudo mkdir -m 755 /data
		sudo mount /dev/xvdf /data
		df -h
		exit
EOF
		# Continue to feed usual information when verbose is called
		[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "Mounted Complete"
	
	#If volume flag has a value, check if it is already attached. If so, echo an error and if not use that volume id to attach and mount
	else
        	volumeState=$(aws ec2 describe-volumes --volume-ids $vol | grep State | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
				verbose "Current Volume: $volumeState"

		if [ "$volumeState"="attached" ]; then
			verbose "Error: Please specify a volume that is available."

		else
			attachVolume=$(aws ec2 attach-volume --volume-id $vol --instance-id $instanceId --device /dev/sdf)
					
			# SSH on Remote Host
			# Create the Filesystem
			# Make and Mount Directory
			# Assumes user has "Sudo" permissions available
			ssh -t -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$key_path" ubuntu@$publicDns 1>/dev/null 2>/dev/null << EOF
                sudo mkfs -t ext4 /dev/xvdf 1>/dev/null 2>/dev/null
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
    verbose "Create Backup"
	if [ "$opt_m" == "rsync" ];
               then
                  rsync -avzhe "ssh -o StrictHostKeyChecking=no -i $key_path" --rsync-path="sudo rsync" $dir ubuntu@$publicDns:/data/ 1>/dev/null 2>/dev/null

        elif [ "$opt_m" == "dd" ];
                then      
                	timeStamp=$(date "+%Y.%m.%d-%H")
                	# Create tar on local host
			tar -cf - $dir 1>/dev/null 2>/dev/null | ssh -o StrictHostKeyChecking=no -i "$key_path" ubuntu@$publicDns "sudo dd of=/data/dir.tar" conv=sync 1>/dev/null 2>/dev/null
	else
                echo " Please specify a valid value. Available methods are 'rsync' and 'dd' "
        fi
}

volumeID()
{
	generateKeyPair
		[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "A Key Pair is being generated" 
        runInstance

	volumeState=$(aws ec2 describe-volumes --volume-ids $opt_v | grep State | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
        	[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "$volumeState"
		volumeZone=$(aws ec2 describe-volumes --volume-ids $opt_v | grep AvailabilityZone | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g')
        	[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "volumeZone : $volumeZone"
	
	if [ "$volumeState" == "attached" ]; then
		echo "The volume $opt_v provided is attached"
		#Complete - Shut down Instance
		[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "Instance is now Terminating"
		terminateInstance
		exit 1
	
	elif [ "$instanceZone" != "$volumeZone" ]; then
		echo "The volume $opt_v is  not in the same availability zone as the instance"
		#Conditional Err - Shut down Instance
		[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "Instance is now Terminating"
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
            ssh -t -T -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$key_path" ubuntu@$publicDns 1>/dev/null 2>/dev/null << EOF
            sudo mkfs -t ext4 /dev/xvdf 1>/dev/null 2>/dev/null
            sudo mkdir -m 755 /data
            	[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "Currently creating Directory to mount on Remote end"
            sudo mount /dev/xvdf /data
            	[ $EC2_BACKUP_VERBOSE = 'true' ] &&  echo "Currently mounting...Please Wait"
            df -h
            exit
EOF

                verbose "Volume has been Mounted"
		

	 fi
	
}

# We need to terminate instance for 3 situations:
# 1) User runs script and hits 'cntrl+C'
# 2) Script finishes and terminating instance (NOT Volume) is needed
# 3) Call termination where 'exit' is being called as the script will 'exit'
terminateInstance()
{
	if [ "$instanceId" == "" ]; then 
		verbose "No instance was created"
	else
		aws ec2 stop-instances --instance-ids $instanceId 1>/dev/null 2>/dev/null
		aws ec2 terminate-instances --instance-ids $instanceId 1>/dev/null 2>/dev/null
		verbose "Instacnes have been terminated"
	fi 
}

# Terminate Instance when end-user hits cntrl+c during running script
function ctrl_c() {
  
      terminateInstance
	exit 1
}

# Print Help function page
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

# As long as the below is greater than 0, execute the following case statements
# using shift for corner cases when -m/-v is given blank without a valid parameter
while [ $# -gt 0 ] 
do
	case $1 in
		-h) displayHelp;;
		-m) 
			case $2 in
			dd) opt_m="$2"; shift; shift;;
			rsync) opt_m="$2"; shift; shift;;
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
				dir=$1; shift
		 	fi
		 	;;
	esac
done

# Statements for -m and -v calling
# Display If Statements if -m/-v has/doesn't have parameter
# Call IF for each possible situation
   if [[ "$opt_m" == "" && "$opt_v" != "" ]]; then
	opt_m="dd"
	volumeID
	createBackup
	terminateInstance
   elif [[ "$opt_m" != "" && "$opt_v" == "" ]]; then
	generateKeyPair
        runInstance
        createVolume
        createBackup
	terminateInstance
   elif [[ "$opt_m" == "" && "$opt_v" == "" ]]; then
	opt_m="dd"
	generateKeyPair
        runInstance
        createVolume
        createBackup
	terminateInstance
   elif [[ "$opt_m" != "" && "$opt_v" != "" ]]; then 
	volumeID
        createBackup
	terminateInstance
  else
	echo "Error"
  fi 

###end of case statement

exit
