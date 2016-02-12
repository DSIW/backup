#!/bin/bash

# don't use versioning for these files because this directory is backuped and there is versioning active.

DEVICE="sda"
BOOT_PARTITION="sda1"
hostname=$(hostname)
dd if=/dev/${BOOT_PARTITION} of=/backup/${hostname}_${BOOT_PARTITION}_boot-partition.img bs=512 count=2048 >/dev/null
dd if=/dev/${DEVICE} of=/backup/${hostname}_${DEVICE}_mbr.img bs=512 count=2048 >/dev/null
sfdisk -d /dev/${DEVICE} > /backup/${hostname}_${DEVICE}_partitiontable.txt
cryptsetup luksHeaderBackup /dev/sda2 --header-backup-file /backup/${hostname}_sda2_luks-header.img
pacman -Qqen > /backup/${hostname}_pacman.txt
pacman -Qqem > /backup/${hostname}_aur.txt
