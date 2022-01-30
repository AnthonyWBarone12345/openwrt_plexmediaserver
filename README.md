# openwrt_plexmediaserver
A set of scripts to quickly and easily setup Plex Media Server on an OpenWRT Router. These scripts are specifically designed to work with the Netgear R9000, but could (with minor modifications) work for other OpenWRT devices. 

It is worth noting thjat this sets up the newest publically available plex media server version, which is considerasbly newer than the one you get with the R900 stock firmware. It is also considerably better performing and more stable than running plex on stock netgear firmware.

Other powerful ARMv7-based devices may work with no modification. For devices based on other architectures, the main change is that you will likely need to manually do what `plex_download.sh` automates - downloading the plex media server binarier and libraries with the correct architecture, adding in any required libraries that might be missing (e.g., because plex is assuming a desktop system and thus these libraries would be already available on the system), and then creating an xz-compresssed archive with everything.

These scripts make plex work by extracting the contents of the archive mentioned in the previous paragraph onto /tmp/plexmediaserver (which is on a ramdisk) and then runs plex from there. UCI is uysed to store some parameters that are loaded and passed to the plex binary when it gets run. The decompression of the archive and the UCI setup are all automated.

WARNING: MEMORY REQUIREMENTS ARE QUITE LARGE (for the sort of embedded devices that OpenWRT usually runs on). Between the space on disk to hold the plex binaries and libraries and the memory actively used by plex we are talking A FEW HUNDRED MB. I doubt that this would work on any device with under 512 MB of RAM, and 1GB has (like the R9000 has) is probably a lower limit for "good" performance.

Note: the codes are fairly well documented and have help sections at the top. Refer to these for additional information and specifics.

-----------------------------------------------------------------SETUP-----------------------------------------------------------------------------

If you have a R9000, setting things up is almost entirely automated. You will need to:

1. copy `plexmediaserver.sh`, `plex_download.s`h and `plex_setup.sh` to `/etc/plexmediaserver`
2. mount the usb harddrive you want to use for plex (e.g., at `/mnt/plex`)
3. run `/etc/plexmediaserver/plex_setup.sh /mnt/plex` (replace `/mnt/plex` with whatever mountpoint you choose. Also, dont forget to `chmod +x` the script first)
4. run `service plexmediaserver start`

This will (hopefully) set everything up properly. Note: I build my R9000 images to explicitly support/use the NEON SIMD hardware. I *think* the plex ARMv7neon arch will still work even if you dont do this, but I cant say for sure if this is the case or not.

If you have another sufficiently powerful ARMv7 device the above instructions might also work for you.

If you have another OpenWRT device, the setup is a bit more involved. You will need to:

1. copy `plexmediaserver.sh` and `plex_setup.sh` to `/etc/plexmediaserver`
2. mount the usb harddrive you want to use for plex (e.g., at `/mnt/plex`)
3. run `/etc/plexmediaserver/plex_setup.sh --no-download /mnt/plex` (replace `/mnt/plex` with whatever mountpoint you choose. Also, dont forget to `chmod +x` the script first)
4. Put together a plex package (binaries and libraries) that runs on your device. This will probably involve some trial-and-error You may need to add in missing required libraries...put these in a folder called `extra_libs` in the main plex package root. Put `gconv` libraries on `extra_libs/gconv`.
5. rename the directory put together in step 4 with the plex version string (e.g., something like `1.25.3.5409-f11334058-armv7neon`)
6. make an xz-compressed tar archive on this folder using `tar -cvOf - "${plex_ver}" | xz -6e -zc > "${plex_tmp}/plexmediaserver.txz"`, where `${plex_ver}` is the name of the directory from step #5 and `${plex_tmp}` is the path `<plex_drive_mountpoint>/.plex/Library/Application`
7. run `service plexmediaserver start`

Good luck on this endeavor.
