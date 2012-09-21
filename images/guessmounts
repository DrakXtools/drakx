#!/bin/sh

drvinst STORAGE

mdadm --assemble --scan

# lvm::init()
lvm2 vgscan
lvm2 vgchange -a y

