#!/bin/bash
###
 # COPYRIGHT NOTICE
 # Copyright 2023 Horizon Robotics, Inc.
 # All rights reserved.
 # @Date: 2022-12-18 16:06:50
 # @LastEditTime: 2023-04-25 12:14:22
### 

set -e

#
# This script synchronizes the kernel, bootloader and debian package
# sources in the horizon public git repository.
# The script also provides opportunities to the sync to a specific tag
# so that the binaries shipped with a release can be replicated.
#
# Usage:
# By default it will download all the listed sources
# ./source_sync.sh
# Use the -t <TAG> option to provide the TAG to be used to sync all the sources.
# Use the -k <TAG> option to download only the kernel and device tree repos and optionally sync to TAG
# For detailed usage information run with -h option.
#

# verify that git is installed
if  ! which git > /dev/null  ; then
  echo "ERROR: git is not installed. If your linux distro is 10.04 or later,"
  echo "git can be installed by 'sudo apt-get install git-core'."
  exit 1
fi

# source dir
RDK_DIR=$(cd `dirname $0` && pwd)
RDK_DIR="${RDK_DIR}/source"
# script name
SCRIPT_NAME=`basename $0`
# info about sources.
# NOTE: *Add only kernel repos here. Add new repos separately below. Keep related repos together*
SOURCE_INFO="
k:kernel:HorizonRDK/x5-kernel.git:
o:bootloader:HorizonRDK/x5-bootloader.git:
o:uboot:HorizonRDK/x5-uboot.git:
o:hobot-boot:HorizonRDK/x5-hobot-boot.git:
o:hobot-dtb:HorizonRDK/x5-hobot-dtb.git:
"

# exit on error on sync
EOE=0
# after processing SOURCE_INFO
NSOURCES=0
declare -a SOURCE_INFO_PROCESSED
# download all?
DALL=1

function Usages {
	local ScriptName=$1
	local LINE
	local OP
	local DESC
	local PROCESSED=()
	local i

	echo "Use: $1 [options]"
	echo "Available general options are,"
	echo "     -h     :     help"
	echo "     -e     : exit on sync error"
	echo "     -d [DIR] : root of source is DIR"
	echo "     -t [TAG] : Git tag that will be used to sync all the sources"
	echo ""
	echo "By default, all sources are downloaded."
	echo "Only specified sources are downloaded, if one or more of the following options are mentioned."
	echo ""
	echo "$SOURCE_INFO" | while read LINE; do
		if [ ! -z "$LINE" ]; then
			OP=$(echo "$LINE" | cut -f 1 -d ':')
			DESC=$(echo "$LINE" | cut -f 2 -d ':')
			if [[ ! " ${PROCESSED[@]} " =~ " ${OP} " ]]; then
				echo "     -${OP} [TAG]: Download $DESC source and optionally sync to TAG"
				PROCESSED+=("${OP}")
			else
				echo "           and download $DESC source and sync to the same TAG"
			fi
		fi
	done
	echo ""
}

function ProcessSwitch {
	local SWITCH="$1"
	local TAG="$2"
	local i
	local found=0

	for ((i=0; i < NSOURCES; i++)); do
		local OP=$(echo "${SOURCE_INFO_PROCESSED[i]}" | cut -f 1 -d ':')
		if [ "-${OP}" == "$SWITCH" ]; then
			SOURCE_INFO_PROCESSED[i]="${SOURCE_INFO_PROCESSED[i]}${TAG}:y"
			DALL=0
			found=1
		fi
	done

	if [ "$found" == 1 ]; then
		return 0
	fi

	echo "Terminating... wrong switch: ${SWITCH}" >&2
	Usages "$SCRIPT_NAME"
	exit 1
}

function UpdateTags {
	local SWITCH="$1"
	local TAG="$2"
	local i

	for ((i=0; i < NSOURCES; i++)); do
		local OP=$(echo "${SOURCE_INFO_PROCESSED[i]}" | cut -f 1 -d ':')
		if [ "${OP}" == "$SWITCH" ]; then
			SOURCE_INFO_PROCESSED[i]=$(echo "${SOURCE_INFO_PROCESSED[i]}" \
				| awk -F: -v OFS=: -v var="${TAG}" '{$4=var; print}')
		fi
	done
}

function DownloadAndSync {
	local WHAT_SOURCE="$1"
	local RDK_SOURCE_DIR="$2"
	local REPO_URL="$3"
	local TAG="$4"
	local OPT="$5"
	local RET=0

	if [ -d "${RDK_SOURCE_DIR}" ]; then
		echo "Directory for $WHAT, ${RDK_SOURCE_DIR}, already exists!"
		pushd "${RDK_SOURCE_DIR}" > /dev/null
		git status 2>&1 >/dev/null
		if [ $? -ne 0 ]; then
			echo "But the directory is not a git repository -- clean it up first"
			echo ""
			echo ""
			popd > /dev/null
			return 1
		fi
		git fetch --all 2>&1 >/dev/null
		local_head=$(git rev-parse HEAD)
		remote_head=$(git rev-parse @{u})
		if [[ $local_head != $remote_head ]]; then
			echo "There are remote updates for $WHAT, pulling latest code..."
			git pull --ff-only
		fi
		popd > /dev/null
	else
		echo "Downloading default $WHAT source..."

		git clone "$REPO_URL" -n ${RDK_SOURCE_DIR} 2>&1 >/dev/null
		if [ $? -ne 0 ]; then
			echo "$2 source sync failed!"
			echo ""
			echo ""
			return 1
		fi

		echo "The default $WHAT source is downloaded in: ${RDK_SOURCE_DIR}"
	fi

	if [ -z "$TAG" ]; then
		echo "Please enter a tag to sync $2 source to"
		echo -n "(enter nothing to skip): "
		read TAG
		TAG=$(echo $TAG)
		UpdateTags $OPT $TAG
	fi

	if [ ! -z "$TAG" ]; then
		if [ "xmain" == x"$TAG" ] || [ "xdevelop" == x"$TAG" ]; then
			# checkout main or develop
			pushd ${RDK_SOURCE_DIR} > /dev/null
			echo "Syncing up with branch origin/$TAG..."
			git checkout ${TAG}
			echo "$2 source sync'ed to branch origin/$TAG successfully!"
			popd > /dev/null
		else 
			pushd ${RDK_SOURCE_DIR} > /dev/null
			git tag -l 2>/dev/null | grep -q -P "^$TAG\$"
			if [ $? -eq 0 ]; then
				echo "Syncing up with tag $TAG..."
				git checkout -b mybranch_$(date +%Y-%m-%d-%s) $TAG
				echo "$2 source sync'ed to tag $TAG successfully!"
			else
				echo "Couldn't find tag $TAG"
				echo "$2 source sync to tag $TAG failed!"
				RET=1
			fi
			popd > /dev/null
		fi
	fi
	echo ""
	echo ""

	return "$RET"
}

# prepare processing ....
GETOPT=":ehd:t:"

OIFS="$IFS"
IFS=$(echo -en "\n\b")
SOURCE_INFO_PROCESSED=($(echo "$SOURCE_INFO"))
IFS="$OIFS"
NSOURCES=${#SOURCE_INFO_PROCESSED[*]}

for ((i=0; i < NSOURCES; i++)); do
	OP=$(echo "${SOURCE_INFO_PROCESSED[i]}" | cut -f 1 -d ':')
	GETOPT="${GETOPT}${OP}:"
done

# parse the command line first
while getopts "$GETOPT" opt; do
	case $opt in
		d)
			case $OPTARG in
				-[A-Za-z]*)
					Usages "$SCRIPT_NAME"
					exit 1
					;;
				*)
					RDK_DIR="$OPTARG"
					;;
			esac
			;;
		e)
			EOE=1
			;;
		h)
			Usages "$SCRIPT_NAME"
			exit 1
			;;
		t)
			TAG="$OPTARG"
			PROCESSED=()
			for ((i=0; i < NSOURCES; i++)); do
				OP=$(echo "${SOURCE_INFO_PROCESSED[i]}" | cut -f 1 -d ':')
				if [[ ! " ${PROCESSED[@]} " =~ " ${OP} " ]]; then
					UpdateTags $OP $TAG
					PROCESSED+=("${OP}")
				fi
			done
			;;
		[A-Za-z])
			case $OPTARG in
				-[A-Za-z]*)
					eval arg=\$$((OPTIND-1))
					case $arg in
						-[A-Za-Z]-*)
							Usages "$SCRIPT_NAME"
							exit 1
							;;
						*)
							ProcessSwitch "-$opt" ""
							OPTIND=$((OPTIND-1))
							;;
					esac
					;;
				*)
					ProcessSwitch "-$opt" "$OPTARG"
					;;
			esac
			;;
		:)
			case $OPTARG in
				#required arguments
				d)
					Usages "$SCRIPT_NAME"
					exit 1
					;;
				#optional arguments
				[A-Za-z])
					ProcessSwitch "-$OPTARG" ""
					;;
			esac
			;;
		\?)
			echo "Terminating... wrong switch: $@" >&2
			Usages "$SCRIPT_NAME"
			exit 1
			;;
	esac
done
shift $((OPTIND-1))

for ((i=0; i < NSOURCES; i++)); do
	OPT=$(echo "${SOURCE_INFO_PROCESSED[i]}" | cut -f 1 -d ':')
	WHAT=$(echo "${SOURCE_INFO_PROCESSED[i]}" | cut -f 2 -d ':')
	REPO=$(echo "${SOURCE_INFO_PROCESSED[i]}" | cut -f 3 -d ':')
	TAG=$(echo "${SOURCE_INFO_PROCESSED[i]}" | cut -f 4 -d ':')
	DNLOAD=$(echo "${SOURCE_INFO_PROCESSED[i]}" | cut -f 5 -d ':')

	if [ $DALL -eq 1 -o "x${DNLOAD}" == "xy" ]; then
		DownloadAndSync "$WHAT" "${RDK_DIR}/${WHAT}" "git@github.com:${REPO}" "${TAG}" "${OPT}"
		tRET=$?
		if [ $tRET -ne 0 -a $EOE -eq 1 ]; then
			exit $tRET
		fi
	fi
done

exit 0
