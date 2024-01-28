#! /bin/bash
# version 28-01-2024
# author email: tech@amer.ovh
# this script aims to enhance Yunohost backup by 
# - calling Yunohost to list the existing backups and delete the extra ones beyond a defined number
# - mirroring the yunohost.backup archives folder to another given location
# - exporgting the last backup to an external site using curl
# - logging to syslog, and send email at the end, so it can be run as a cron job with any desired frequency
# - be called with parameters, otherwise use the following default values 
# This script is provided as a courtesy to the Yunohost community, and without any warranty. Use-it at your own responsibility.
# Don't hesitate also to propose enhancements.


ListFile="temp.txt" # temporary file to read the existing backups
MailBody="Running Yunohost cycling backup script\r\n"
Src="/home/yunohost.backup/archives/" # the files where Yunohost store backups
Shell=$0

# set these parameters to your need or pass them as parameters
ArchFolder="/mnt/bkp/backups/" # where the copy of the backup should be archived. this must be a local map
NbBkps=7 # number of backups to cycle
RemoteURL=""; #TODO. Upload via curl has not been tested yet
Debug='No'; # Debug to Yes to prevent actual copy and delete, to active echo instead of logger to check the script output
MailTo="admin@your.domain";


# check whether user had supplied -h or --help . If yes display usage
if [[ ( $@ == "--help") ||  $@ == "-h" ]]
then 
    echo "Usage: $0 [arguments]";
    echo -e "Without parameters, the script will use the default values, that can be changed in the script\r\n"\
            "-a Archive folder to mirror the backuos\r\n"\
            "-r Remote URL to upload the backup\r\n"\
            "-n Number of backups to keep. Older ones will be deleted\r\n"\
            "-m Email address to send the backup report to. Usefull if run from cron"\
            "-d Yes to display debug information, default=No";
    exit 0;
fi

function log () {
if [[ $Debug == "Yes" ]]; then
  echo $*;
else
  logger $Shell":"$*; # log to /var/log/syslog
fi
}

while getopts a:r:n:d:m: flag
do
    case "${flag}" in
        a) ArchFolder=${OPTARG};;
        r) RemoteURL=${OPTARG};;
        n) NbBkps=${OPTARG};;
        d) Debug=${OPTARG};;
        m) MailTo=${OPTARG};;
    esac
done

if [[ $Debug = 'Yes'|| $Debug = 'yes' ]]; then
  echo "Debug mode";
  Run=0;
else
  Run=1;
fi


rm -f $ListFile # start by cleanin up the temporary file
yunohost backup list >> $ListFile # get the list of existing backups
# cat $ListFile
readarray -t Backups < $ListFile # read this list into an array
# TODO check if there's a need to sort the backup and line format=  - yyyymmdd_nnnnnn


if [ ${Backups[0]} = "archives:" ]; then
  unset Backups[0] # delete the first text line 
fi
#echo ${Backups[*]}

NLines=${#Backups[@]}

Msg="There are "$NLines" backups" # debug info
log $Msg
MailBody=$MailBody$Msg"\r\n"

if [ $NLines > $NbBkps ]; then # if there are more backups than needed
  for (( i=$NLines ; i>$NbBkps ; i-- )); do # delete the extra backups starting from the bottom of the list
    Clean=${Backups[$i]}
    Clean=${Clean:4} # remove the leading spaces and dash
    if [ $Run == 1 ]; then 
      Msg= "Deleting backup:"$Clean"."
      log $Msg
      MailBody=$MailBody$Msg"\r\n"
      yunohost backup delete $Clean
      rm -f $ArchFolder$Clean".info.json"
      rm -f $ArchFolder$Clean".tar"
      rm -f $ArchFolder$Clean".tar.gz"
    fi
  done
fi

# now do a new backup
Result=0
if [ $Run == 1 ]; then 
  Msg="Generating a new backup. This might take some time ...."
  log $Msg
  MailBody=$MailBody$Msg"\r\n"

  yunohost backup create 
  Result=$?
fi


if [ $Result == 0 ]; then #if backup succeeds then copy it to External folder

  # Copy the new backup, it is the last in the list
  rm -f $ListFile # start by cleanin up the temporary file
  yunohost backup list >> $ListFile # get the list of existing backups
  readarray -t Backups < $ListFile # read this list into an array

  NLines=${#Backups[@]}
  Clean=${Backups[$NLines-1]}
  Clean=${Clean:4} # remove the leading spaces and dash

  # the first line is the new backup
  Bkp=$Src$Clean
  Msg="Copy backup:"$Bkp" to:"$ArchFolder
  log $Msg
  MailBody=$MailBody$Msg"\r\n"

  if [ $Run == 1 ]; then
    cp $Bkp".info.json" $ArchFolder
    cp $Bkp".tar" $ArchFolder
    cp $Bkp".tar.gz" $ArchFolder
    Msg=$Bkp"Backup copied with succedd to :"$ArchFolder
    log $Msg
    MailBody=$MailBody$Msg"\r\n"
    if [ $RemoteURL -ne "" ]; then
       curl -F $RemoteURL$Bkp".info.json"
       curl -F $RemoteURL$Bkp".tar"
       curl -F $RemoteURL$Bkp".tar.gz"
       Msg=$Bkp"Remote URL uploaded with success"
       log $Msg
       MailBody=$MailBody$Msg"\r\n"
    fi
  fi
else
  Msg="Erreur " $?
  log $Msg
  MailBody=$MailBody$Msg"\r\n"
fi
if [ $MailTo -ne "" ]; then 
  echo -e $MailBody | mail -s "Yunohost backup report" $MailTo 
fi