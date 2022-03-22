#!/bin/sh

# This script:
# 1. downloads the netgear r9000 plex package (old plex version), extracts it, steals its "extra_libs dir, then discards the rest
# 2. downloads the asustor armv7neon plex package (recent plex version), extracts it, steals it main plex binaries + libraries dir, then discards the rest
# 3. combines the parts kept in (1) and (2) and generates a compressed .txz archive from it
#
# The following variables *might* need to be manually altered in some situations
#
# 'plex_archive_type' : extension to use for archive. Allowable values are:
#	'xz' or 'tar.xz' or 'txz' produces a *.tar.xz archive
# 	'sqfs' produces a squashfs archive
# 	'both' produces both
#
# `plex_tmp` is the tmp/working directory and where the generated archive will be output to. 
# 	It must be on a filesystem with enough free space to hold the downloaded plex files.
# 	    It needs to hold a compressed and uncompressed copy of the plex package 
# 	     --> a few hundred MB max data usage (so it might or might not fit in RAM)
# 	If set in UCI, "plex_compressed_archive_path" is used (since this is where the generated archive needs to go). Otherwise, /tmp/plex_tmp is used.
#
# `plex_url` is the download link for the up-to-date plex version to use. By default it tries to fetch the latest asustor armv7neon plex packagee released.
#
# `netgear_url` is where we find the URL to download the netgear r9000 (outdated) plex package. This is done just to grab the "extra_libs" dir it includes.
# 	This probably wont need to be changed, unless netgear decides to change where the server address where they are hosting the netgear r9000 plex package

# set archive type
plex_archive_type='sqfs'

# determine URL's and tmp directories to use during the script
plex_url="$(curl https://plex.tv/api/downloads/5.json | sed -E s/'"id"'/'\n\n\n"id"'/g | grep asustor | sed -E s/'\{"label"'/'\n\n\n{"label"'/g | grep ARMv7 | sed -E s/'^.*"url"\:"(.*\.apk)"\,.*$'/'\1'/)"
[ -z "${plex_url}" ] && plex_url='https://downloads.plex.tv/plex-media-server-new/1.25.3.5409-f11334058/asustor/PlexMediaServer-1.25.3.5409-f11334058-armv7neon.apk'

# check archive type
{ [ "${plex_archive_type}" == 'txz' ] || [ "${plex_archive_type}" == 'tar.xz' ]; } && plex_archive_type='xz'
{ [ "${plex_archive_type}" == 'xz' ] || [ "${plex_archive_type}" == 'sqfs' ]; } || plex_archive_type='both'


if [ -n "$(/sbin/uci get plexmediaserver.@main[0].plex_compressed_archive_path)" ]; then
	plex_tmp="$(dirname "$(/sbin/uci get plexmediaserver.@main[0].plex_compressed_archive_path)")" 
else
	plex_tmp=/tmp/plex_tmp
fi

kk=0
while [ -e "${plex_tmp}/${kk}" ]; do
	kk=$((( ${kk} + 1 )))
done
mkdir -p "${plex_tmp}/${kk}"

netgear_url='http://updates1.netgear.com/sw-apps/plex/r9000/'

# get url for most recent netgear plex download from netgear "verify_binary" url and download plex from it
cd "${plex_tmp}/${kk}"

wget -r "${netgear_url}"

find "${plex_tmp}/${kk}" -type f -name 'verify_binary*.txt' | while read -r vb; do
	wget "$(cat "${vb}" | grep -F 'url="' | sed -E s/'^.* url\="(.*)".*$'/'\1'/)"
done

# extract netgear plex package, strip away the extra_libs dir, discard everything else

gzip -dc "${plex_tmp}/${kk}"/*.tgz | tar -x

mv "${plex_tmp}/${kk}"/*/extra_libs "${plex_tmp}"

cd "${plex_tmp}"

rm -rf "${plex_tmp}/${kk}"

mkdir -p "${plex_tmp}/${kk}"
cd "${plex_tmp}/${kk}"

# download (up-to-date) plex version

wget "${plex_url}"

# extract it, strip away the main binaries/libs dir, discard everything else

plex_filename="${plex_tmp}/${kk}/$(echo "${plex_url}" | sed -E s/'^.*\/'// | sed -E s/'\.apk$'//)"

mv "${plex_filename}.apk" "${plex_filename}.zip"
unzip "${plex_filename}.zip"

plex_ver="$(echo "${plex_filename}" | sed -E s/'^.*PlexMediaServer\-'//)"
mkdir "${plex_tmp}/${kk}/${plex_ver}"
mv data.tar.gz  "${plex_tmp}/${kk}/${plex_ver}"
cd "${plex_tmp}/${kk}/${plex_ver}"

gzip -dc "${plex_tmp}/${kk}/${plex_ver}/data.tar.gz" | tar -x
mv "${plex_tmp}/${kk}/${plex_ver}/data.tar.gz" "${plex_tmp}/${kk}"
cd "${plex_tmp}/${kk}"

mv "${plex_tmp}/extra_libs" "${plex_tmp}/${kk}/${plex_ver}"

[ -e "${plex_tmp}/plexmediaserver.txz" ] && mv "${plex_tmp}/plexmediaserver.txz" "${plex_tmp}/plexmediaserver.txz.old"

mkdir -p "${plex_tmp}/${kk}/${plex_ver}/tmp"
{ [ "${plex_archive_type}" == 'xz' ] || [ "${plex_archive_type}" == 'both' ]; } && tar -cvOf - "${plex_ver}" | xz -6e -zc > "${plex_tmp}/plexmediaserver.txz"
{ [ "${plex_archive_type}" == 'sqfs' ] || [ "${plex_archive_type}" == 'both' ]; } && ln -s "${plex_ver}/extra_libs" "extra_libs" && mksquashfs "${plex_ver}" "extra_libs" "plexmediaserver.sqfs" -all-root -keep-as-directory -comp zstd -Xcompression-level 22


cd "${plex_tmp}"

rm -rf "${plex_tmp}/${kk}"

echo "plex archive generated!. Archive is located at: ${plex_tmp}/plexmediaserver.txz" >&2


