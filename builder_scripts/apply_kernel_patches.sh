#!/bin/sh

# This script is for testing only!
# It will build a kernel for each patch line item and
# then output the kernels to $KERNELOUTPUTDIR

#set -e -x

CURRENTDIR=`pwd`
[ -r "${CURRENTDIR}/pfsense_local.sh" ] && . ${CURRENTDIR}/pfsense_local.sh

PATCHDIR=${PATCHDIR:-${BASE_DIR}/tools/patches/${freebsd_branch}}
SRCDIR=${SRCDIR:-/usr/src}

# If override is in place, use it otherwise
# locate fastest cvsup host
if [ ! -z ${OVERRIDE_FREEBSD_CVSUP_HOST:-} ]; then
	echo "Setting CVSUp host to ${OVERRIDE_FREEBSD_CVSUP_HOST}"
	echo $OVERRIDE_FREEBSD_CVSUP_HOST > /var/db/fastest_cvsup
else
	echo "Finding fastest CVSUp host... Please wait..."
	fastest_cvsup -c tld -q > /var/db/fastest_cvsup
fi

# CVSUp freebsd version
echo "Using FreeBSD ${pfSense_version} branch ${freebsd_branch}"
cvsup -h `cat /var/db/fastest_cvsup` ./${freebsd_branch}-supfile

echo "Removing old patch rejects..."
find /usr/src -name "*.rej" -exec rm {} \;

# Loop through and patch files
for LINE in `cat ${CURRENTDIR}/patches.${freebsd_branch}`
do
	PATCH_DEPTH=`echo $LINE | cut -d~ -f1`
	PATCH_DIRECTORY=`echo $LINE | cut -d~ -f2`
	PATCH_FILE=`echo $LINE | cut -d~ -f3`
	PATCH_FILE_LEN=`echo $PATCH_FILE | wc -c`
	MOVE_FILE=`echo $LINE | cut -d~ -f4`
	MOVE_FILE_LEN=`echo $MOVE_FILE | wc -c`
	if [ $PATCH_FILE_LEN -gt "2" ]; then
		echo "Patching ${PATCH_FILE}"
		(cd ${SRCDIR}/${PATCH_DIRECTORY} && patch -f ${PATCH_DEPTH} < ${PATCHDIR}/${PATCH_FILE})
	fi
	if [ $MOVE_FILE_LEN -gt "2" ]; then
		#cp ${SRCDIR}/${MOVE_FILE} ${SRCDIR}/${PATCH_DIRECTORY}
	fi
done

echo "Finding patch rejects..."
REJECTED_PATCHES=`find /usr/src -name "*.rej" | wc -l`
if [ $REJECTED_PATCHES -gt 0 ]; then
	echo
	echo "WARNING!  Rejected patches found!  Please fix before building!"
	echo 
	find /usr/src -name "*.rej" 
	echo
fi

