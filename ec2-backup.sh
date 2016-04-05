#!/bin/bash


##Variables##
publicDns= aws ec2 describe-instances | grep PublicDns | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g'
instanceId= aws ec2 describe-instances | grep InstanceId | head -1 | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g'
timeZone= aws ec2 describe-instances | grep AvailabilityZone | awk '{print $2}' | sed 's/\"//g'

createKeyPair= aws ec2 create-key-pair --key-name ec2BackUpKeyPair --output text > ~/ec2BackUpKeyPair.pem | chmod 600 ~/ec2BackUpKeyPair.pem
runInstance= aws ec2 run-instances --instance-type t1.micro --key ec2BackUpKeyPair --image-id ami-c27e48aa

createVolume= aws ec2 create-volume --size 1 --availability-zone $timeZone --volume-type standard
attachVolume= aws ec2 attach-volume --volume-id $volume --instance-id $instanceId --device /dev/sdf

volume= aws ec2 describe-volumes | grep VolumeId volume.txt | awk '{print $2}' | sed 's/\"//g' | sed 's/\,//g'


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
  option=$1
  inet_string=""
  usage=$0"-h|-m|-v"
  case "$option" in

      "-h")
	  helptext
	  ;;

      "-m")
          method_type    #call method function
	  ;;

      "-v")
	  volume_id  #call volumeID function
	  ;;
      *)
        echo " The parameter passed is invalid" $usage
        
	;;
  esac

###end of case statement

exit
