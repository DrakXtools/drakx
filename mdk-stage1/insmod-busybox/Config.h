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
// This compiles out everything but the most 
// trivial --help usage information (i.e. reduces binary size)
//#define BB_FEATURE_TRIVIAL_HELP
//
// Use termios to manipulate the screen ('more' is prettier with this on)
#define BB_FEATURE_USE_TERMIOS
//
// calculate terminal & column widths (for more and ls)
#define BB_FEATURE_AUTOWIDTH
//
// show username/groupnames (bypasses libc6 NSS) for ls
#define BB_FEATURE_LS_USERNAME
//
// show file timestamps in ls
#define BB_FEATURE_LS_TIMESTAMPS
//
// enable ls -p and -F
#define BB_FEATURE_LS_FILETYPES
//
// sort the file names (still a bit buggy)
#define BB_FEATURE_LS_SORTFILES
//
// enable ls -R
#define BB_FEATURE_LS_RECURSIVE
//
// enable ls -L
#define BB_FEATURE_LS_FOLLOWLINKS
//
// Change ping implementation -- simplified, featureless, but really small.
//#define BB_FEATURE_SIMPLE_PING
//
// Make init use a simplified /etc/inittab file (recommended).
#define BB_FEATURE_USE_INITTAB
//
//Enable init being called as /linuxrc
#define BB_FEATURE_LINUXRC
//
//Have init enable core dumping for child processes (for debugging only) 
//#define BB_FEATURE_INIT_COREDUMPS
//
// Allow init to permenently chroot, and umount the old root fs
// just like an initrd does.  Requires a kernel patch by Werner Almesberger. 
// ftp://icaftp.epfl.ch/pub/people/almesber/misc/umount-root-*.tar.gz
//#define BB_FEATURE_INIT_CHROOT
//
//Make sure nothing is printed to the console on boot
#define BB_FEATURE_EXTRA_QUIET
//
//Should syslogd also provide klogd support?
#define BB_FEATURE_KLOGD
//
// enable syslogd -R remotehost
#define BB_FEATURE_REMOTE_LOG
//
//Simple tail implementation (2.34k vs 3k for the full one).
//Both provide 'tail -f' support (only one file at a time.)
#define BB_FEATURE_SIMPLE_TAIL
//
// Enable support for loop devices in mount
#define BB_FEATURE_MOUNT_LOOP
//
// Enable support for a real /etc/mtab file instead of /proc/mounts
//#define BB_FEATURE_MOUNT_MTAB_SUPPORT
//
// Enable support for mounting remote NFS volumes
#define BB_FEATURE_NFSMOUNT
//
// Enable support forced filesystem unmounting 
// (i.e. in case of an unreachable NFS system).
#define BB_FEATURE_MOUNT_FORCE
//
// Enable support for creation of tar files.
#define BB_FEATURE_TAR_CREATE
//
// Enable support for "--exclude" for excluding files
#define BB_FEATURE_TAR_EXCLUDE
//
// Enable support for s///p pattern matching
#define BB_FEATURE_SED_PATTERN_SPACE
//
//// Enable reverse sort
#define BB_FEATURE_SORT_REVERSE
//
// Enable command line editing in the shell
#define BB_FEATURE_SH_COMMAND_EDITING
//
//Allow the shell to invoke all the compiled in BusyBox commands as if they
//were shell builtins.  Nice for staticly linking an emergency rescue shell
//among other thing.
#define BB_FEATURE_SH_STANDALONE_SHELL
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
// Support installing modules from pre 2.1 kernels
//#define BB_FEATURE_INSMOD_OLD_KERNEL
// Support installing modules from kernel versions after 2.1.18
#define BB_FEATURE_INSMOD_NEW_KERNEL
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
