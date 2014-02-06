#!/bin/sh
#
# Common functions to be used by build scripts
#
#  builder_embedded.sh
#  Copyright (C) 2004-2009 Scott Ullrich
#  All rights reserved.
#  
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#  
#  1. Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.
#  
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#  
#  THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
#  INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
#  AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
#  AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
#  OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
#  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
#  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
#  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#  POSSIBILITY OF SUCH DAMAGE.
#
# Crank up error reporting, debugging.
#  set -e 
#  set -x

# If a full build has been performed we need to nuke
# /usr/obj.pfSense/ since embedded uses a different
# src.conf
if [ -f /usr/obj.pfSense/pfSense.$FREEBSD_VERSION.world.done ]; then
	echo -n "Removing /usr/obj* since full build performed prior..."
	rm -rf /usr/obj*
	echo "done."
fi

# Suck in local vars
. ./pfsense_local.sh

# Suck in script helper functions
. ./builder_common.sh

# This should be run first
launch

# Make sure source directories are present.
ensure_source_directories_present

# Ensure binaries are present that builder system requires
install_required_builder_system_ports

# Ensure pbi tools are installed
install_pbi_tools

# Check if we need to force a ports rebuild
check_for_forced_pfPorts_build

# Clean up items that should be cleaned each run
freesbie_clean_each_run

# Output build flags
print_flags

# Allow old CVS_CO_DIR to be deleted later
chflags -R noschg $CVS_CO_DIR

export NO_COMPRESSEDFS=yes

if [ ! -z "${CUSTOM_REMOVE_LIST:-}" ]; then
	echo ">>> Using ${CUSTOM_REMOVE_LIST:-} ..."
	export PRUNE_LIST="${CUSTOM_REMOVE_LIST:-}"
else
	echo ">>> Using ${BUILDER_SCRIPTS}/conf/rmlist/remove.list.iso.$FREEBSD_VERSION ..."
	export PRUNE_LIST="${BUILDER_SCRIPTS}/conf/rmlist/remove.list.iso.$FREEBSD_VERSION"
fi

# Use embedded src.conf
export SRC_CONF="${BUILDER_SCRIPTS}/conf/src/src.conf.embedded.$FREEBSD_VERSION"
export SRC_CONF_INSTALL="${BUILDER_SCRIPTS}/conf/src/src.conf.embedded.$FREEBSD_VERSION.install"

# Clean up items that should be cleaned each run
freesbie_clean_each_run

# Checkout a fresh copy from pfsense cvs depot
update_cvs_depot

# Calculate versions
version_kernel=`cat $CVS_CO_DIR/etc/version_kernel`
version_base=`cat $CVS_CO_DIR/etc/version_base`
version=`cat $CVS_CO_DIR/etc/version`

# Build if needed and install world and kernel
echo ">>> Building world for Embedded... $FREEBSD_VERSION  $FREEBSD_BRANCH ..."
make_world

# Build kernels
echo ">>> Building kernel configs: $BUILD_KERNELS for FreeBSD: $FREEBSD_BRANCH ..."
build_all_kernels

# Add extra files such as buildtime of version, bsnmpd, etc.
echo ">>> Phase populate_extra..."
cust_populate_extra

# Add installer bits
cust_populate_installer_bits

# Add extra pfSense packages
install_custom_packages

# Overlay pfsense checkout on top of FreeSBIE image
# using the customroot plugin
echo ">>> Merging extra items..."
freesbie_make extra

# Overlay host binaries
cust_overlay_host_binaries

# Must be run after overlay_host_binaries and freesbie_make extra
cust_fixup_wrap

# Check for custom config.xml
cust_install_config_xml

# Install custom pfSense-XML packages from a chroot
pfsense_install_custom_packages_exec

# Overlay final files
install_custom_overlay_final

# Ensure config.xml exists
copy_config_xml_from_conf_default

# Invoke FreeSBIE2 toolchain
check_for_zero_size_files
freesbie_make clonefs

# Ensure /home exists
mkdir -p $CLONEDIR/home

echo "#### Building bootable UFS image ####"

UFS_LABEL=${FREESBIE_LABEL:-"pfSense"} # UFS label
CONF_LABEL=${CONF_LABEL:-"pfSenseCfg"} # UFS label

###############################################################################
#		59 megabyte image.
#		ROOTSIZE=${ROOTSIZE:-"116740"}  # Total number of sectors - 59 megs
#		CONFSIZE=${CONFSIZE:-"4096"}
###############################################################################
#		128 megabyte image.
#		ROOTSIZE=${ROOTSIZE:-"235048"}  # Total number of sectors - 128 megs
#		CONFSIZE=${CONFSIZE:-"4096"}
###############################################################################
#		500 megabyte image.  Will be used later.
#		ROOTSIZE=${ROOTSIZE:-"1019990"}  # Total number of sectors - 500 megs
#		CONFSIZE=${CONFSIZE:-"4096"}
###############################################################################

unset ROOTSIZE
unset CONFSIZE

FBSD_VERSION=`/usr/bin/uname -r | /usr/bin/cut -d"." -f1`
if [ "$FBSD_VERSION" = "7" ]; then
	ROOTSIZE=${ROOTSIZE:-"235048"}  # Total number of sectors - 236 megabytes (for 256 cards)
	CONFSIZE=${CONFSIZE:-"10240"}
else
	ROOTSIZE=${ROOTSIZE:-"470096"}  # Total number of sectors - 128 megabytes
	CONFSIZE=${CONFSIZE:-"10240"}
fi

SECTS=$((${ROOTSIZE} + ${CONFSIZE}))
# Temp file and directory to be used later
TMPFILE=`mktemp -t freesbie`
TMPDIR=`mktemp -d -t freesbie`

echo "Initializing image..."
dd if=/dev/zero of=${IMGPATH} count=${SECTS}

# Attach the md device
DEVICE=`mdconfig -a -t vnode -f ${IMGPATH}`

cat > ${TMPFILE} <<EOF
a:	*			0	4.2BSD	1024	8192	99
c:	${SECTS}	0	unused	0		0
d:	${CONFSIZE}	*	4.2BSD	1024	8192	99
EOF

bsdlabel -BR ${DEVICE} ${TMPFILE}

newfs -L ${UFS_LABEL} -O2 /dev/${DEVICE}a
newfs -L ${CONF_LABEL} -O2 /dev/${DEVICE}d

mount /dev/${DEVICE}a ${TMPDIR}
mkdir ${TMPDIR}/cf
mount /dev/${DEVICE}d ${TMPDIR}/cf

echo "Currently mounted Embedded partitions:"
df -h | grep ${DEVICE}

echo "Writing files..."

cd ${CLONEDIR}

FBSD_VERSION=`/usr/bin/uname -r | /usr/bin/cut -d"." -f1`
if [ "$FBSD_VERSION" = "7" ]; then
	echo ">>> Using CPIO to clone {$TMPDIR}..."
	find . -print -depth | cpio -dump ${TMPDIR}
else
	echo ">>> Using TAR to clone build_embedded.sh..."
	mkdir -p ${TMPDIR}
	( tar cf - * | ( cd /$TMPDIR; tar xfp - ) )
fi

echo -n ">>> Creating md5 summary of files present..."
rm -f $CLONEDIR/etc/pfSense_md5.txt
echo "#!/bin/sh" > $CLONEDIR/chroot.sh
echo "find / -type f | /usr/bin/xargs /sbin/md5 >> /etc/pfSense_md5.txt" >> $CLONEDIR/chroot.sh
chmod a+rx $CLONEDIR/chroot.sh
chroot $CLONEDIR /chroot.sh
rm $CLONEDIR/chroot.sh
echo "Done."

echo "/dev/ufs/${UFS_LABEL} / ufs ro 1 1" > ${TMPDIR}/etc/fstab
echo "/dev/ufs/${CONF_LABEL} /cf ufs ro 1 1" >> ${TMPDIR}/etc/fstab

umount ${TMPDIR}/cf
umount ${TMPDIR}

mdconfig -d -u ${DEVICE}
rm -f ${TMPFILE}
rm -rf ${TMPDIR}

ls -lh ${IMGPATH}

# Check for zero sized files.  loader.conf is one of the culprits.
check_for_zero_size_files
report_zero_sized_files

# Email that the operation has completed
email_operation_completed

# Run final finish routines
finish
