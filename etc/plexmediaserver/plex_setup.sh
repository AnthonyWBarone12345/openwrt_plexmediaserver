# Before starting, mount the drive you will use plex on and set its mountpoint below
# Alternately, you can give the mountpoint as an argument when calling this script 
# (this will supercede the mount point listed below as long it is a valid directory)
#
# The scripts "plexmediaserver.sh" and "plex_download.sh" need to be present
# Ideally these should be in /etc/plexmediaserver, though as long as they are either:
#     a) in the same directory as this script, or
#     b) anywhere in /etc, /root, or /usr
# then this script will find them (albeit with a increasing time penalty as these places are searched)

plex_drive_mountpoint=/mnt/plex

# check mountpoint and flags
no_download_flag=0
for inArg in "${@}"; do
	[ "${inArg}" == '--no-download' ] && no_download_flag=1 && continue
	[ -d "${inArg}" ] && plex_drive_mountpoint="${inArg}"
done
! [ -d "${plex_drive_mountpoint}" ] && echo 'ERROR: mount point directory not found. Aborting.' >&2 && return 1 || echo "Using plex drive mountpoint: ${plex_drive_mountpoint}" >&2

# setup directory tree for plex
mkdir -p "${plex_drive_mountpoint}/.plex/Library/Application"
mkdir -p "${plex_drive_mountpoint}/.plex/Library/Application Support"

# automount drive
cat /etc/fstab | grep -Fq "${plex_drive_mountpoint}" || cat /etc/mtab | grep "${plex_drive_mountpoint}" | tee -a /etc/fstab

# find paths for plexmediaserver.sh and plex_download.sh
plex_find_path() { 
	for pth in /etc/plexmediaserver "$(dirname "$(readlink -f $0)")" /etc /root /usr;
    do
        find "$pth" -type f -name "${1}" | head -n 1 | grep -E '^.+$' && break
    done
}
plex_script_path="$(plex_find_path plexmediaserver.sh)" 
[ -n ${plex_script_path} ] && echo "plexmediaserver.sh found at ${plex_script_path}" >&2 || echo "WARNING: plexmediaserver.sh could not be found. UCI will not be setup." >&2
[ "${no_download_flag}" == '0' ] && plex_download_path="$(plex_find_path plex_download.sh)"
[ -n ${plex_download_path} ] && echo "plex_download.sh found at ${plex_download_path}" >&2 || echo "WARNING: plex_download.sh could not be found. plex archive will not be downloaded." >&2 

# setup UCI
if [ -n ${plex_script_path} ]; then
	chmod +x "${plex_script_path}" && "${plex_script_path}" setup_uci

# setup very basic service to allow plex to be controlled by running `service plexmediaplayer {start,stop,restart}`
cat << EOF | tee -a /etc/init.d/plexmediaserver
#!/bin/sh /etc/rc.common

START=99
NAME=plexmediaserver

start() {
	"${plex_script_path}" start
}

stop() {
	"${plex_script_path}" stop
}

restart() {
	"${plex_script_path}" stop start
}
EOF

	/etc/init.d/plexmediaserver enable


fi

# download/generate plex archive
[ -n ${plex_download_path} ] && chmod +x "${plex_download_path}" && "${plex_download_path}"

# auto-start plex on boot (via /etc/rc.local)
[ -n ${plex_script_path} ] && [ -n ${plex_download_path} ] &&  cp /etc/rc.local /etc/rc.local.backup && echo "$(cat /etc/rc.local | grep -v 'exit 0' | grep -v 'service plexmediaserver start' | grep -v '/etc/init.d/plexmediaserver start'; echo 'sleep 20; /etc/init.d/plexmediaserver start'; echo 'exit 0')" > /etc/rc.local

[ -n ${plex_script_path} ] && { [ -n ${plex_download_path} ] || [ "${no_download_flag}" == '1' ]; } &&  echo -e "\n\n-------------------------------------------------------\n\nPlex has been sucessfully installed and setup! \n\nPlex will automatically start up during the boot process. \nTo manually start|stop|restart Plex, you can use the following commands: \n\n\tservice plexmediaserver start \n\tservice plexmediaserver stop \n\tservice plexmediaserver restart\n\nTo access Plex from a web browser, go to: \n\n$(ip addr show br-lan | grep 'inet '| sed -E s/'^.*inet (.*)\/.*$'/'\1'/):32400/web \n\n"
