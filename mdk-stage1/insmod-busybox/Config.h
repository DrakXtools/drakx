/* vi: set sw=4 ts=4: */
// This file defines the feature set to be compiled into busybox.
// When you turn things off here, they won't be compiled in at all.
//
//// This file is parsed by sed. You MUST use single line comments.
//   i.e.  //#define BB_BLAH
//
//
// BusyBox Applications
#define BB_INSMOD
// End of Applications List
//
//
//
// ---------------------------------------------------------
// This is where feature definitions go.  Generally speaking,
// turning this stuff off makes things a bit smaller (and less 
// pretty/useful).
//
//
//
// Turn this on to use Erik's very cool devps, and devmtab kernel drivers,
// thereby eliminating the need for the /proc filesystem and thereby saving
// lots and lots memory for more important things.  You can not use this and
// USE_PROCFS at the same time...  NOTE:  If you enable this feature, you
// _must_ have patched the kernel to include the devps patch that is included
// in the busybox/kernel-patches directory.  You will also need to create some
// device special files in /dev on your embedded system:
//        mknod /dev/mtab c 10 22
//        mknod /dev/ps c 10 21
// I emailed Linus and this patch will not be going into the stock kernel.
//#define BB_FEATURE_USE_DEVPS_PATCH
//
// enable features that use the /proc filesystem (apps that 
// break without this will tell you on compile)...
// You can't use this and BB_FEATURE_USE_DEVPS_PATCH 
// at the same time...
#define BB_FEATURE_USE_PROCFS

//
// Enable tab completion in the shell (not yet 
// working very well -- so don't turn this on)
//#define BB_FEATURE_SH_TAB_COMPLETION
//
//Turn on extra fbset options
//#define BB_FEATURE_FBSET_FANCY
//
//Turn on fbset readmode support
//#define BB_FEATURE_FBSET_READMODE
//
// You must enable one or both of these features
// Support insmod/lsmod/rmmod for post 2.1 kernels
#define BB_FEATURE_NEW_MODULE_INTERFACE
//
// Support insmod/lsmod/rmmod for pre 2.1 kernels
//#define BB_FEATURE_OLD_MODULE_INTERFACE
//
// Support module version checking
//#define BB_FEATURE_INSMOD_VERSION_CHECKING
//
// Support for Minix filesystem, version 2
//#define BB_FEATURE_MINIX2
//
//
// Enable busybox --install [-s]
// to create links (or symlinks) for all the commands that are 
// compiled into the binary.  (needs /proc filesystem)
// #define BB_FEATURE_INSTALLER
//
// Clean up all memory before exiting -- usually not needed
// as the OS can clean up...  Don't enable this unless you
// have a really good reason for cleaning things up manually.
//#define BB_FEATURE_CLEAN_UP
//
// End of Features List
//
//
//
//
//
//
//---------------------------------------------------
// Nothing beyond this point should ever be touched by 
// mere mortals so leave this stuff alone.
//
#ifdef BB_FEATURE_MOUNT_MTAB_SUPPORT
#define BB_MTAB
#endif
//
#if defined BB_FEATURE_SH_COMMAND_EDITING && defined BB_SH
#define BB_CMDEDIT
#endif
//
#ifdef BB_KILLALL
#ifndef BB_KILL
#define BB_KILL
#endif
#endif
//
#ifdef BB_FEATURE_LINUXRC
#ifndef BB_INIT
#define BB_INIT
#endif
#define BB_LINUXRC
#endif
//
#ifdef BB_GZIP
#ifndef BB_GUNZIP
#define BB_GUNZIP
#endif
#endif
//
#if defined BB_MOUNT && defined BB_FEATURE_NFSMOUNT
#define BB_NFSMOUNT
#endif
//
#if defined BB_FEATURE_SH_COMMAND_EDITING
#ifndef BB_FEATURE_USE_TERMIOS
#define BB_FEATURE_USE_TERMIOS
#endif
#endif
//
#if defined BB_FEATURE_AUTOWIDTH
#ifndef BB_FEATURE_USE_TERMIOS
#define BB_FEATURE_USE_TERMIOS
#endif
#endif
//
#if defined BB_INSMOD
#ifndef BB_FEATURE_INSMOD_OLD_KERNEL
#define BB_FEATURE_INSMOD_NEW_KERNEL
#endif
#endif
