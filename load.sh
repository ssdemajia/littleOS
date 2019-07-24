#!/bin/bash
nasm loader.s -o loader.bin
mount ./build/boot.img /media/ -t vfat -o loop
cp  loader.bin /media/
sync
umount /media/