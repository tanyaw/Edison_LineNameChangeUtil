#!/bin/bash
#--------------------------------------------------------------------------------
# This script performs a line name change utility for PCM versions 6.0 and 7.x
# Line name changes are made in both RTDB/SITEDDD and RTDB/mySQL respectively.
# 
# Tanya Wanwatanakool 07.06.16
#--------------------------------------------------------------------------------
echo "-----------ChangeName Script is running-----------"
echo "Enter substation name (IN ALL CAPS):"
read NAME

echo "Enter old line name, followed by [ENTER]:"
read oName

echo "Enter new line name, followed by [ENTER]:"
read nName

#----------------------PART ONE-------------------------
#  Check pricom license number
#-------------------------------------------------------
echo "Check PCM license number..."
license=( $( chklic | grep 'PCM6.2\|PCM7.*' | cut -d':' -f2 | sed "s/^ *//" ) )
lic=${license:0:6}

case $lic in
	"PCM6.2") echo -e "\tPCM Version 6.2" 
		;;
	"PCM7.0" | "PCM7.1") echo -e "\tPCM Version 7.x"
		;;
	"*") echo "This script does not work with this $lic pricom version, please perform this operation manually"
	     exit 0
		;;
esac

#-----------------------PART TWO--------------------------
#  Grab all .asc files with <Name> replace with <NewName>
#---------------------------------------------------------
pricomdown
dbup
rtdbexport

pathname=/ABB/${NAME}/Data
cd $pathname

echo "Extract filenames into list..."
#Grabs entire pathname of .asc file
files=( $( grep "${oName}" *.asc | find -name '*.asc' ) )

for file in "${files[@]}"; do
	#Extract only filename from pathname
	filename="${file##*/}"

	#Col2 - DESCRPT, Col4 - USRDESC
	cut -d'|' -f2 $filename | grep "${oName}" >> col.txt
	cut -d'|' -f4 $filename | grep "${oName}" >> col.txt
done

cp col.txt new_col.txt
echo "Name change in temp files..."
sed -i "s%${oName}%${nName}%g" ${pathname}/new_col.txt

#-----------------------PART THREE-------------------------
#  RTDB name changes in .asc files
#    1. Verify 32 characters in columns
#	  wc > 32, cut characters
#	  wc < 32, append spaces
#    2. While-loop to replace entire columns in .asc files
#----------------------------------------------------------
echo "Adding line name changes in .asc files..." 
while IFS= read -r oldName && IFS= read -r newName <&3; do
	newLine=""
	words=${#newName}

	#Debugging purposes
	if [ $words -gt 32 ]; then
		oCount=${#oName}
		nCount=${#nName}
		diff=$(( nCount - oCount ))
		
		#Fixes cutting off end of line with name change
		if [[ "${newName:0:1}" == " " && $diff -gt 0 ]]; then
			end=$(( 32 + $diff ))
			newLine=${newName:$diff:$end}
			echo "Append+Short: $newLine"	
		else
			newLine=${newName:0:32}
			#echo "count: $words"
			echo "Shortened: $newLine"
		fi
	elif [ $words -lt 32 ]; then
		newLine=$(printf "%-32s" "$newName")
		#echo "Append spaces: $newLine"
	else 
		newLine=$newName
		#echo "Same: $newName"
	fi

	echo "Replace $oldName with $newLine"
	grep "${oldName}" *.asc | find -name '*asc' | xargs sed -i "s%${oldName}%${newLine}%g"

done <./col.txt 3<new_col.txt

rm col.txt new_col.txt
rtdbimport

#----------------------PART FOUR---------------------------
#  Determine PCM# 
#   1. PCM6.2 - TYPHOON name changes in .kom files
#   2. PCM7.x - mySQL name changes in .sql files
#----------------------------------------------------------
if [ "$lic" = "PCM6.2" ]; then
	echo "Adding line name changes in .kom files..."
	cd siteddd	
	tyexport siteddd
	grep "${oName}" *.kom | find -name '*kom' | xargs sed -i "s%${oName}%${nName}%g"
	rm -rf *.idx *.dat
	tyimport siteddd
else 
	echo "Adding line name changes in .sql files..."
	cd sitedb	
	mysqldump -u pcmadm --password=access -P $MYSQL_PORT -S $MYSQL_SOCK pricom_db > ./db.sql
	sed -i "s%${oName}%${nName}%g" ./db.sql
	mysql -u pcmadm --password=access -P $MYSQL_PORT -S $MYSQL_SOCK pricom_db < ./db.sql	
	rm -rf ./db.sql	
fi

pricomdown
exit 0;
