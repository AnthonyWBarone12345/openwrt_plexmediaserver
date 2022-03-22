#!/bin/sh +x

##################################################
# SETUP AND CONTROL (START/STOP) PLEX MEDIA SERVER
##################################################
#
# # # # # IMPORTANT VARIABLES # # # # #
#
# PLEX_BROWSER_ROOT: the mountpoint of the usb HDD containing the plex library and media files
# PLEX_LIBRARY_DIR: the path to the main plex library where the application stores its data
#                    ---> This needs to be at "${PLEX_BROWSER_ROOT}/.plex/Library" or "${PLEX_BROWSER_ROOT}/*/.plex/Library"
# PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR: the plex application uses this for storing metadata and stuff liker that
#                    ---> This needs to be at "${PLEX_LIBRARY_DIR}/Application Support"
# PLEX_COMPRESSED_ARCHIVE_PATH: this is where the plex binary and libraries (in a xz-compressed tar archive) are stored 
#                    This archive will be decompressed and extracted onto the device memory before plex can be started
#                    When extracted, this should produce a folder whose title identifies the plex version that contains the plex binaries (Plex Media Server) and libraries (libs/)
#                    ---> This needs to be at "${PLEX_LIBRARY_DIR}/Application/plexmediaserver.txz"
# PLEX_TMP_DIR: The main dir (ideally, though not absolutely required to be) on the device RAM where plex binaries and libraries are decompressed
#                    Should you desire (e.g., for testing a new plex release) multiple versions of plex can be used side-by-side here
#                    ---> The default location for this is "/tmp/plexmediaserver"
# PLEX_VERSION: The plex version in use. This is auto-determined based on the folder name that decompressing the archive with the binaries and libraries gives
#                    If multiple versions are available, the highest version (found via `sort -Vr | head -n 1`) is used. 
#                    ---> A specific plex version can be forced using the UCI variable "plexmediaserver.@main[0].force_version"
# PLEX_BIN_DIR: The directory actually containing the (version-specific) plex binaries and libraries
#                   ---> This will be at "${PLEX_TMP_DIR}/${PLEX_VERSION}"
# TMPDIR: stores temp files for a specific plex instance that is running. 
#                   ---> This will be at "${PLEX_BIN_DIR}/tmp"
# extra_libs: a folder with some extra libraries (including gconv libraries) that are not typically included with plex - they only ship with the (outdated) netgear-provided R9000-specific plex package
#                   ---> These need to be at either "${PLEX_BIN_DIR}/extra_libs" or "${PLEX_TMP_DIR}/extra_libs"
#
# # # # # NOTE: UCI variables must be setup for things to work right. If they havent been setup yet, call this sacript with the 1st argument set to either 'setup_uci' or 'check_uci'


#################################################################################################################

# user-settable default browser root (note: only used if search for '*/.plex/Library' dir fails)

PLEX_BROWSER_ROOT_default='/mnt/plex'

# If 1st argument is "setup_uci" or "check_uci", or if /etc/config/plexmediaserver doesnt exist, then do initial uci setup

if { [ "${1}" == 'check_uci' ] || [ "${1}" == 'setup_uci' ]; }; then

	echo "setting up UCI config" >&2

	[ -e /etc/config/plexmediaserver ] || touch /etc/config/plexmediaserver 
	plex_UCI="$(/sbin/uci show plexmediaserver)"
	
	# if plexmediaserver.@main[0] doesnt exist, scrap config and start from scratch
	if ! echo "${plex_UCI}" | grep -Fq 'plexmediaserver.@main[0]'; then
		/sbin/uci delete plexmediaserver; 
		/sbin/uci add plexmediaserver main; 
		/sbin/uci commit plexmediaserver; 
		plex_UCI="$(/sbin/uci show plexmediaserver)"; 
	fi
	
	# add (empty) config values for any missing UCI options
	for UCI_opt in plex_script_path plex_library_dir plex_application_support_dir plex_browser_root plex_compressed_archive_path plex_tmp_dir force_version version plex_bin_dir; do
		echo "${plex_UCI}" | grep -qF "${UCI_opt}" || /sbin/uci add_list plexmediaserver.@main[0].${UCI_opt}=''
	done
	
	# commit changes
	/sbin/uci commit plexmediaserver;
	
	shift 1
fi

[ -e "/etc/config/plexmediaserver" ] || "$(readlink -f $0)" setup_uci


# read identification variables from UCI

PLEX_BROWSER_ROOT="$(/sbin/uci get plexmediaserver.@main[0].plex_browser_root)"
PLEX_LIBRARY_DIR="$(/sbin/uci get plexmediaserver.@main[0].plex_library_dir)"
PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR="$(/sbin/uci get plexmediaserver.@main[0].plex_application_support_dir)"
PLEX_COMPRESSED_ARCHIVE_PATH="$(/sbin/uci get plexmediaserver.@main[0].plex_compressed_archive_path)"
PLEX_TMP_DIR="$(/sbin/uci get plexmediaserver.@main[0].plex_tmp_dir)"
PLEX_VERSION="$(/sbin/uci get plexmediaserver.@main[0].version)"
PLEX_BIN_DIR="$(/sbin/uci get plexmediaserver.@main[0].plex_bin_dir)"

# check UCI variables and set empty/invalid ones to default values

{ [ -z "${PLEX_BROWSER_ROOT}" ] || ! [ -e "${PLEX_BROWSER_ROOT}" ]; } && PLEX_BROWSER_ROOT="$(cat /proc/mounts | grep -E '^\/dev\/' | grep -Ev 'squashfs|ubifs' | sed -E s/'^\/dev\/[^ \t]*[ \t]+([^ \t]*)[ \t]+.*$'/'\1'/ | while read -r nn; do find "$nn" -maxdepth 2 -type d -name '.plex'; done | while read -r nn; do [ -e "${nn}/Library" ] && echo "$nn" | sed -E s/'\/[^\/]*$'// && break; done)"
{ [ -z "${PLEX_BROWSER_ROOT}" ] || ! [ -e "${PLEX_BROWSER_ROOT}" ]; } && cat /proc/mounts | grep -q "${PLEX_BROWSER_ROOT_default}" && PLEX_BROWSER_ROOT="${PLEX_BROWSER_ROOT_default}" 
[ -n "${PLEX_BROWSER_ROOT}" ] && /sbin/uci set plexmediaserver.@main[0].plex_browser_root="${PLEX_BROWSER_ROOT}"

if { [ -z "${PLEX_LIBRARY_DIR}" ] || ! [ -e "${PLEX_LIBRARY_DIR}" ]; }; then
	if [ -e "${PLEX_BROWSER_ROOT}/.plex/Library" ]; then
		PLEX_LIBRARY_DIR="${PLEX_BROWSER_ROOT}/.plex/Library"
	else
		PLEX_LIBRARY_DIR="$(find "${PLEX_BROWSER_ROOT}" -type d -maxdepth 3 -path '*/.plex/Library' | head -n 1)"
	fi
	[ -n "${PLEX_LIBRARY_DIR}" ] && [ -e "${PLEX_LIBRARY_DIR}" ] && /sbin/uci set plexmediaserver.@main[0].plex_library_dir="${PLEX_LIBRARY_DIR}"
fi

{ [ -z "${PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR}" ] || ! [ -e "${PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR}" ]; } && [ -e "${PLEX_LIBRARY_DIR}/Application Support" ] && PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR="${PLEX_LIBRARY_DIR}/Application Support"  && /sbin/uci set plexmediaserver.@main[0].plex_application_support_dir="${PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR}"

{ [ -z "${PLEX_COMPRESSED_ARCHIVE_PATH}" ] || ! [ -e "${PLEX_COMPRESSED_ARCHIVE_PATH}" ]; } && [ -e "${PLEX_LIBRARY_DIR}/Application/plexmediaserver.txz" ] && PLEX_COMPRESSED_ARCHIVE_PATH="${PLEX_LIBRARY_DIR}/Application/plexmediaserver.txz" && /sbin/uci set plexmediaserver.@main[0].plex_compressed_archive_path="${PLEX_COMPRESSED_ARCHIVE_PATH}"

[ -z "${PLEX_TMP_DIR}" ] && PLEX_TMP_DIR="/tmp/plexmediaserver" && /sbin/uci set plexmediaserver.@main[0].plex_tmp_dir="${PLEX_TMP_DIR}"
[ $(echo ${PLEX_TMP_DIR} | sed -E s/'^.*\/([^\/]*)$'/'\1'/) != plexmediaserver ] && PLEX_TMP_DIR="${PLEX_TMP_DIR}/plexmediaserver" && /sbin/uci set plexmediaserver.@main[0].plex_tmp_dir="${PLEX_TMP_DIR}"

[ "$(/sbin/uci get plexmediaserver.@main[0].plex_script_path)" == "$(pwd)" ] || /sbin/uci set plexmediaserver.@main[0].plex_script_path="$(readlink -f $0)"

mkdir -p "${PLEX_TMP_DIR}"

/sbin/uci commit plexmediaserver

unpackme() {
  # decompress Plex Binaries and Libs from plexmediaserver.txz
  echo "Preparing Plex for Use - Extracting Plex Binaries and Library Files" >&2

  xz -dc "${PLEX_COMPRESSED_ARCHIVE_PATH}" | tar -C "${PLEX_TMP_DIR}" -xf -
}

startme() {
  echo "Starting Plex Media Server" >&2

  # run unpack operation is plex binary not found
  [ -e "${PLEX_BIN_DIR}/Plex Media Server" ] || unpackme

  cd "${PLEX_BIN_DIR}"
  
  # abort if we cant switch to directoiry with plex binary
  [ "$(pwd)" != "${PLEX_BIN_DIR}" ] && echo "Something went wrong, not able to switch to ${PLEX_BIN_DIR}. Aborting plex startup." >&2 && exit 1
  ln -sf "${PLEX_LIBRARY_DIR}" "${PLEX_BIN_DIR}/Library"

  # link "extra_libs" directory in PLEX_TMP_DIR and link this script into PLEX_BIN_DIR
  ! [ -e "${PLEX_TMP_DIR}/extra_libs" ] && [ -e "${PLEX_BIN_DIR}/extra_libs" ] && ln -sf "${PLEX_BIN_DIR}/extra_libs" "${PLEX_TMP_DIR}/extra_libs"
  ln -sf "$(/sbin/uci get plexmediaserver.@main[0].plex_script_path)" "${PLEX_BIN_DIR}/plexmediaserver.sh" 

  # start plex
  [ "${inArg}" == 'start-nd' ] && "${PLEX_BIN_DIR}/Plex Media Server" || "${PLEX_BIN_DIR}/Plex Media Server" &

  echo -e "\n\nTo access Plex from a web browser, go to: \n\n$(ip addr show br-lan | grep 'inet '| sed -E s/'^.*inet (.*)\/.*$'/'\1'/):32400/web"

}

stopme() {
  echo "Stopping Plex Media Server"
  if [ -f "${PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR}/Plex Media Server/plexmediaserver.pid" ]; then
    # kill process listed in  plexmediaserver.pid
    kill -3 $(cat "${PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR}/Plex Media Server/plexmediaserver.pid")
    echo "Quit sent to server. Waiting 3 seconds and force killing if not dead" >&2
    sleep 3
  fi
  if [ "$(ps | egrep -e 'Plex Media Server|Plex DLNA Server' | grep -v grep | wc -l)" != "0" ]; then
    # kill any remnants still running
    echo "Force killing leftover procs" >&2
    ps | egrep -e "Plex Media Server|Plex DLNA Server" | awk '{print $1}' | xargs kill -9
  else
    echo "Plex Media Server shutdown cleanly" >&2
  fi
}

for inArg in "${@}"; do
 case "${inArg}" in
  unpack)
    unpackme
  ;;

  *)

  # finish checking UCI Identificzation variables that refference stuff about these decompressed binaries/libraries
  
  ls -1 "${PLEX_TMP_DIR}" | grep -q -E '^[0-9]+\..*$' && PLEX_VERSION="$(ls -1 "${PLEX_TMP_DIR}" | grep -E '^[0-9]+\..*$' | sort -Vr | head -n 1)" && /sbin/uci set plexmediaserver.@main[0].version="${PLEX_VERSION}"
  [ -n "$(/sbin/uci get plexmediaserver.@main[0].force_version)" ] &&  [ -e "${PLEX_TMP_DIR}/$(/sbin/uci get plexmediaserver.@main[0].force_version)" ] && PLEX_VERSION="$(/sbin/uci get plexmediaserver.@main[0].force_version)" && /sbin/uci set plexmediaserver.@main[0].version="${PLEX_VERSION}"

  #{ ! [ -e "${PLEX_BIN_DIR}" ] || [ "${PLEX_BIN_DIR}" != */${PLEX_VERSION} ]; } &&
  PLEX_BIN_DIR="${PLEX_TMP_DIR}/${PLEX_VERSION}" && /sbin/uci set plexmediaserver.@main[0].plex_bin_dir="${PLEX_BIN_DIR}"
  
 /sbin/uci commit plexmediaserver

  # export identification variables
#  export PLEX_MEDIA_SERVER_INFO_VENDOR="netgear"
#  export PLEX_MEDIA_SERVER_INFO_DEVICE="r9000"
#  export PLEX_MEDIA_SERVER_INFO_MODEL="$(uname -m)"
#  export PLEX_MEDIA_SERVER_INFO_PLATFORM_VERSION="OpenWRT"
  export PLEX_MEDIA_SERVER_INFO_VENDOR="$(grep \"id\": /etc/board.json | awk -F:\  '{print $2}' | tr -d \" | awk -F, '{print $1}')"
  export PLEX_MEDIA_SERVER_INFO_DEVICE="$(grep \"id\": /etc/board.json | awk -F:\  '{print $2}' | tr -d \" | awk -F, '{print $2}')"
  export PLEX_MEDIA_SERVER_INFO_MODEL="$(uname -m)"
  export PLEX_MEDIA_SERVER_INFO_PLATFORM_VERSION="$(grep ^NAME= /etc/os-release | awk -F= '{print $2}' | tr -d \")"
  export LD_LIBRARY_PATH="${PLEX_BIN_DIR}/lib:${PLEX_TMP_DIR}/extra_libs"
  export GCONV_PATH="${PLEX_TMP_DIR}/extra_libs/gconv"
  export PLEX_MEDIA_SERVER_HOME="${PLEX_BIN_DIR}"
  export PLEX_MEDIA_SERVER_MAX_PLUGIN_PROCS=6
  export PLEX_BROWSER_ROOT="${PLEX_BROWSER_ROOT}"
  export PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR="${PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR}"
  export PLEX_MEDIA_SERVER_DISABLE_AUTOUPDATES=1
  export PLEX_MEDIA_SERVER_DEFAULT_PREFERENCES="ScannerLowPriority=true&DlnaEnabled=false&TranscoderVideoResolutionLimit=1920x1080&TranscoderH264Preset=ultrafast"
  export LC_ALL="C"
  export LANG="C"
  export TMPDIR="${PLEX_BIN_DIR}/tmp"
  export PLEX_BIN_DIR="${PLEX_BIN_DIR}"
  export PLEX_TMP_DIR="${PLEX_TMP_DIR}"
  export PLEX_LIBRARY_DIR="${PLEX_LIBRARY_DIR}"
  export PLEX_VERSION="${PLEX_VERSION}"
  
  mkdir -p "${TMPDIR}"

  ulimit -s 3000
  
  case "${inArg}" in
    start)
      startme
    ;;

    start-nd)
      startme
    ;;
  
    stop)
      stopme
    ;;
  
    restart)
      stopme; startme
    ;;

    *)
      echo "plexmediaserver.sh needs one of the folling options (unpack|start|stop|restart)" >&2
  esac
 esac
done
