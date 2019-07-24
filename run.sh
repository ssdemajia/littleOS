#!/bin/bash
nasm boot.s -o boot.bin
dd if=boot.bin of=./build/boot.img bs=512 count=1 conv=notrunc
bochs