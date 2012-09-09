#define PCI_CONFIG_H
#if defined(__x86_64__)
#define PCI_ARCH_X86_64
#define PCI_HAVE_PM_INTEL_CONF
#elif defined(__ia64__)
#define PCI_ARCH_IA64
#define PCI_HAVE_PM_INTEL_CONF
#elif defined(__i386__)
#define PCI_ARCH_I386
#define PCI_HAVE_PM_INTEL_CONF
#elif defined(__ppc64__) || defined(__powerpc64__)
#define PCI_ARCH_PPC64
#elif defined(__ppc__)  || defined(__powerpc__)
#define PCI_ARCH_PPC
#elif defined(__s390x__)
#define PCI_ARCH_S390X
#elif defined(__s390__)
#define PCI_ARCH_S390
#elif defined(__alpha__)
#define PCI_ARCH_ALPHA
#elif defined(__sparc__) && defined (__arch64__)
#define PCI_ARCH_SPARC64
#elif defined(__sparc__)
#define PCI_ARCH_SPARC
#elif defined(__sh__)
#define PCI_ARCH_SH
#elif defined(__arm__)
#define PCI_ARCH_ARM
#else
#error Unknown Arch
#endif
#define PCI_OS_LINUX
#define PCI_HAVE_PM_LINUX_SYSFS
#define PCI_HAVE_PM_LINUX_PROC
#define PCI_HAVE_LINUX_BYTEORDER_H
#define PCI_PATH_PROC_BUS_PCI "/proc/bus/pci"
#define PCI_PATH_SYS_BUS_PCI "/sys/bus/pci"
#define PCI_HAVE_64BIT_ADDRESS
#define PCI_HAVE_PM_DUMP
#define PCI_IDS "pci.ids"
#define PCI_PATH_IDS_DIR "/usr/share"
#define PCILIB_VERSION "3.1.10"
