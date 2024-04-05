#!/bin/bash
# This program is to simplify ReaR backup process. This bash script is forked from mondobackup.sh. It is modified to be compatible with ReaR (Relax-and-Recover)
# Author: RPA/YMUS/Oct2015
# Modified : ILR/YMUS/Jan2024
# Version : 1
# Release Date: Jan 17, 2024
##########################################

if [ `uname` != "Linux" ]; then
   echo "This script runs on Linux only."
   exit 3
fi

FLAGFILE=/var/log/mondorun.flag
MSGFILE=/tmp/`basename $0`.msg
>$MSGFILE

echo "Running hostinfo.sh"
/usr/local/bin/hostinfo.sh

RECIPIENT="richard_aranas@yamaha-motor.com brad_crowder@yamaha-motor.com richard_on@yamaha-motor.com isauro_ringor@yamaha-motor.com"

REL=`cat /etc/redhat-release |awk -F"release" '{print $2}' |awk -F. '{print $1}'`

HOSTNAME=$(hostname -s)

SENDER="donotreply@yamaha-motor.com"

send_message()
{
    cat $MSGFILE | mailx -s "$SUBJ" -r $SENDER $RECIPIENT
}

# Check if rear is installed:
if [ -f /usr/sbin/rear ]; then
   echo "ReaR is installed, proceeding"
else
   SUBJ="rear: ${HOSTNAME} backup failed"
   echo -e "ReaR Backup run failure in ${HOSTNAME} on `date`. " |tee -a $MSGFILE
   echo -e "/usr/sbin/rear does not exist. " |tee -a $MSGFILE
   send_message
   exit 3
fi

# Check if mondo or rear is already running:
if [ -f $FLAGFILE ]; then
   SUBJ="rear: ${HOSTNAME} backup failed"
   echo "rear or mondo may already be running or $FLAGFILE exists, exiting. " |tee -a $MSGFILE
   send_message
   exit 3
fi

touch $FLAGFILE

case ${HOSTNAME} in
   pdcpdb1|pdvicdb3)
      # Newnan, GA
      REARSAVE="pdmondo5:/rearsave"
      ;;
   pdydsws1|pdydsws2|pdydsws3|npsftas1|pdsftas1|pdftps1|pdproas1|pd3sws1|pd3sws2|pdycows2|pd3sws4|pd3sws5)
      # DMZ
      REARSAVE="pdmondo1:/rearsave"
      ;;
   pdewmdb2|pdnblms3)
      # Lakeview, GA
      REARSAVE="pdmondo6:/rearsave"
      ;;
   pdewmdb4|pdnbmst3|pdemcas3|pdnbkms3)
      REARSAVE="ddksw:/data/col1/backup/ignite2/kennesaw"
      ;;
   pdydla4)
      # Miami, Florida
      REARSAVE="pdmondo3:/rearsave"
      ;;
   pdymcgf4)
      # Toronto, Canada
      REARSAVE="pdmondo4:/rearsave"
      ;;
   *)
      REARSAVE="ddcyp:/backup/ignite2/cypress"
      ;;
esac

if [ ! -d /mnt/rear ]; then
   mkdir -p /mnt/rear
fi

grep /mnt/rear /proc/mounts >/dev/null 2>&1
if [ $? -eq 0 ]; then
   umount /mnt/rear
fi

mount -t nfs -o hard,rsize=32768,rsize=32768 ${REARSAVE} /mnt/rear

if [ $? -ne 0 ]; then # we don't want to fill up the local file system
   SUBJ="rear: ${HOSTNAME} backup failed"
   echo -e "rear backup run failure in ${HOSTNAME} on `date`. " |tee -a $MSGFILE
   echo -e "Mount failure of ISO storage directory, exiting. " |tee -a $MSGFILE
   send_message
   exit 3
fi

mkdir -p /mnt/rear/${HOSTNAME}

# generate EXCLUDE directories:  This is included in /etc/rear/site.conf
if [ ! -f /etc/rear/site.conf ]; then # we need to check if this file exist
   SUBJ="rear: ${HOSTNAME} backup failed"
   echo -e "ReaR Backup run failure in ${HOSTNAME} on `date`. " |tee -a $MSGFILE
   echo -e "/etc/rear/site.conf does not exist. " |tee -a $MSGFILE
   send_message
   exit 3
fi

# export TMPDIR to a separate partition than root.  It needs at least 10G to temporary hold the ISO and the scratch
if [ ! -d /rear ]; then # check if /rear directory has already been created
   SUBJ="rear: ${HOSTNAME} backup failed"
   echo -e "rear backup run failure in ${HOSTNAME} on `date`. " |tee -a $MSGFILE
   echo -e "/rear directory is missing, exiting. " |tee -a $MSGFILE
   send_message
   exit 3
fi

# Check available space for /rear
if [ $REL -eq 6 ]; then
    # Use different field number for RHEL 6
    AVAILABLE_SPACE=$(df -BG /rear | awk 'NR==3 {print $3}' | sed 's/G//')
else
    AVAILABLE_SPACE=$(df -BG /rear | awk 'NR==2 {print $4}' | sed 's/G//')
fi

if [ "$AVAILABLE_SPACE" -ge 10 ]; then # check if /rear has at least 10G space
   echo "/rear has at least 10G of available space to save temporary files and ISO."
else
   SUBJ="rear: ${HOSTNAME} backup failed"
   echo -e "rear backup run failure in ${HOSTNAME} on `date`. " |tee -a $MSGFILE
   echo "/rear does not have enough available space. " |tee -a $MSGFILE
   send_message
   exit 3
fi

SUFFIX=`date +%Y%m%d%H%M%S`
STORE="/mnt/rear/${HOSTNAME}"

export TMPDIR="/rear"

# Check if its really in env:
if env | grep -q "TMPDIR=/rear"; then
    echo "TMPDIR is set to /rear "
else
    #echo "TMPDIR is not set to /rear "
    SUBJ="rear: ${HOSTNAME} backup failed"
    echo "rear backup run failure in ${HOSTNAME} on `date`. " |tee -a $MSGFILE
    echo "TMPDIR is not set to /rear " |tee -a $MSGFILE
    send_message
    exit 3
fi

# Run ReaR backup!
/usr/sbin/rear -v mkbackup

if [ $? -eq 0 ]; then #Check if mkbackup has completed successully
   SUBJ="rear: ${HOSTNAME} backup OK"
   echo -e "ReaR backup ran successfully in ${HOSTNAME} on `date` \n" |tee -a $MSGFILE
   # Count number of files to be moved, if there is more than 1 files then send a warding
   COUNT=$(ls -1 /rear/rear-${HOSTNAME}*.iso 2>/dev/null | wc -l)
   if [ "$COUNT" -gt 1 ]; then
    # Send email notification if theres more than 1 file
    echo "Multiple ISO files found. Sending email..."
    SUBJ="rear: ${HOSTNAME} backup warning"
    echo -e "Multiple ISO files was generated in ${HOSTNAME} on `date`.\n" |tee -a $MSGFILE
    echo -e "Please clean up the root file system so that image can be smaller. \nThank you." |tee -a $MSGFILE
    send_message
   fi
   # Move or copy file from local file system to NFS share
   echo -e "Moving ISOs and log files to ${REARSAVE}/${HOSTNAME}/"
   #mv "/rear/rear-${HOSTNAME}.iso" "${STORE}/rear-${SUFFIX}.iso"
   for ISOFILE in /rear/rear-${HOSTNAME}*.iso; do
      mv "$ISOFILE" "${STORE}/$(basename "$ISOFILE" .iso)-${SUFFIX}.iso" && echo -e "ISO image is in ${REARSAVE}/${HOSTNAME}/$(basename "$ISOFILE" .iso)-${SUFFIX}.iso" |tee -a $MSGFILE
   done
   if [ $? -eq 0 ]; then #check if transfer is successful
      #Also copy the log files
      cp -p "/var/log/rear/rear-${HOSTNAME}.log" "${STORE}/rear-${HOSTNAME}.log"
      cp -p /tmp/hostinfo.out $STORE/hostinfo.${HOSTNAME}.txt
      cp -p /var/lib/rear/sysreqs/Minimal_System_Requirements.txt $STORE/info-${HOSTNAME}.txt
      #echo -e "ISO image is in ${REARSAVE}/${HOSTNAME}/rear-${SUFFIX}.iso" |tee -a $MSGFILE
      #cat /var/lib/rear/sysreqs/Minimal_System_Requirements.txt | tee -a $MSGFILE
      echo -e "\nPhysical Volume Info:" |tee -a $MSGFILE
      /sbin/pvs |tee -a $MSGFILE
      echo -e "\nVolume Groups Info:" |tee -a $MSGFILE
      /sbin/vgs |tee -a $MSGFILE
      echo -e "\nLogical Volume Info:" |tee -a $MSGFILE
      /sbin/lvs |tee -a $MSGFILE
   # Cleanup
   cd $STORE
   DAYS=45
   echo -e "\nDeleting ISO and log files older than $DAYS days"
   find $STORE -name "*.iso" -mtime +$DAYS -exec rm -f {} \;
   find $STORE -name "*.log" -mtime +$DAYS -exec rm -f {} \;
   echo -e "\nListing current ISO images in $STORE" |tee -a $MSGFILE
   du -h *.iso |tee -a $MSGFILE
   else
      SUBJ="rear: ${HOSTNAME} backup failed"
      echo -e "rear backup run failure in ${HOSTNAME} on `date`. " |tee -a $MSGFILE
      echo -e "rear backup completed but failed to move the ISO to the NFS share ${REARSAVE}/${HOSTNAME}/ " |tee -a $MSGFILE
      send_message
      exit 3
   fi

else
   SUBJ="rear: ${HOSTNAME} backup failed"
   echo -e "rear backup run failure in ${HOSTNAME} on `date`. " |tee -a $MSGFILE
   echo "Error running rear mkbackup, please check /var/log/rear/rear-${HOSTNAME}.log " |tee -a $MSGFILE
   send_message
   exit 3
fi

echo -e "\nSaved useful information in:
/var/log/rear/rear-${HOSTNAME}.log
$STORE/info-${HOSTNAME}.txt
/tmp/hostinfo.out
$STORE/hostinfo.${HOSTNAME}.txt" |tee -a $MSGFILE

send_message

cd /
umount -l -v /mnt/rear 2>&1
rm -f $FLAGFILE 2>&1

