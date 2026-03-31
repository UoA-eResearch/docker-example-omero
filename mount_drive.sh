#!/bin/bash

drive_name="ressci202100010-Scotter-Images"
share="//files.auckland.ac.nz/research/${drive_name}"

# unifiles doesn't work with smb versions earlier than 2.1, and smb version 2.1 has some issues with caja file manager
# we therefore specify smb version 3.0, introduced with Windows 8 / Windows Server 2012
smb_version="3.0"

mountpoint="${drive_name}"
# A read only mount
common_options="iocharset=utf8,workgroup=uoa,uid=${USER},ro,dir_mode=0555,file_mode=0444,nodev,nosuid,vers=${smb_version}"
options="username=${USER},${common_options}"

mkdir -p ${mountpoint}
sudo mount -t cifs "${share}" "${mountpoint}" -o "${options}"
if [ "$?" -gt "0" ]; then
  rmdir ${mountpoint}
fi
