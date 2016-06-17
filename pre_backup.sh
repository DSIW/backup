#!/bin/bash

# don't use versioning for these files because this directory is backuped and there is versioning active.

set -e

DEVICE="sda"
BOOT_PARTITION="sda1"
hostname=$(hostname)

BOOT_PARTITION_BACKUP=/backup/${hostname}_${BOOT_PARTITION}_boot-partition.img
MBR=/backup/${hostname}_${DEVICE}_mbr.img
PARTITION_TABLE_SFDISK=/backup/${hostname}_${DEVICE}_partitiontable_sfdisk.txt
PARTITION_TABLE_PARTED=/backup/${hostname}_${DEVICE}_partitiontable_parted.txt
LUKS_HEADER=/backup/${hostname}_sda2_luks-header.img
PACMAN=/backup/${hostname}_pacman.txt
AUR=/backup/${hostname}_aur.txt

rm -f $BOOT_PARTITION_BACKUP
rm -f $MBR
rm -f $PARTITION_TABLE_SFDISK
rm -f $PARTITION_TABLE_PARTED
rm -f $LUKS_HEADER
rm -f $PACMAN
rm -f $AUR

dd if=/dev/${BOOT_PARTITION} of=$BOOT_PARTITION_BACKUP bs=512 count=2048 >/dev/null 2>&1
dd if=/dev/${DEVICE} of=$MBR bs=512 count=2048 >/dev/null 2>&1
sfdisk -d /dev/${DEVICE} > $PARTITION_TABLE_SFDISK
parted /dev/${DEVICE} print > $PARTITION_TABLE_PARTED
cryptsetup luksHeaderBackup /dev/sda2 --header-backup-file $LUKS_HEADER
pacman -Qqen > $PACMAN
pacman -Qqem > $AUR
