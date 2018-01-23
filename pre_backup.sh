#!/bin/bash

# don't use versioning for these files because this directory is backuped and there is versioning active.

# abort on error
set -e

DEVICE="/dev/sda"
BOOT_PARTITION="/dev/sda1"
LUKS_HEADER_DEVICE="/dev/sda2"
BACKUP_DIR="/backup"
hostname=$(hostname)

BOOT_PARTITION_BACKUP=${BACKUP_DIR}/${hostname}_${BOOT_PARTITION}_boot-partition.img
MBR_BACKUP=${BACKUP_DIR}/${hostname}_${DEVICE}_mbr.img
PARTITION_TABLE_SFDISK_BACKUP=${BACKUP_DIR}/${hostname}_${DEVICE}_partitiontable_sfdisk.txt
PARTITION_TABLE_PARTED_BACKUP=${BACKUP_DIR}/${hostname}_${DEVICE}_partitiontable_parted.txt
LUKS_HEADER_BACKUP=${BACKUP_DIR}/${hostname}_sda2_luks-header.img
PACMAN_BACKUP=${BACKUP_DIR}/${hostname}_pacman.txt
AUR_BACKUP=${BACKUP_DIR}/${hostname}_aur.txt

rm -f $BOOT_PARTITION_BACKUP
rm -f $MBR_BACKUP
rm -f $PARTITION_TABLE_SFDISK_BACKUP
rm -f $PARTITION_TABLE_PARTED_BACKUP
rm -f $LUKS_HEADER_BACKUP
rm -f $PACMAN_BACKUP
rm -f $AUR_BACKUP

dd if=${BOOT_PARTITION} of=$BOOT_PARTITION_BACKUP bs=512 count=2048 >/dev/null 2>&1
dd if=${DEVICE} of=$MBR_BACKUP bs=512 count=2048 >/dev/null 2>&1
sfdisk -d ${DEVICE} > $PARTITION_TABLE_SFDISK_BACKUP
parted ${DEVICE} print > $PARTITION_TABLE_PARTED_BACKUP
cryptsetup luksHeaderBackup ${LUKS_HEADER_DEVICE} --header-backup-file $LUKS_HEADER_BACKUP
pacman -Qqen > $PACMAN_BACKUP
pacman -Qqem > $AUR_BACKUP
