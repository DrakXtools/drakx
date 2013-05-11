use Config;

print '
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <ctype.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <syslog.h>
#include <fcntl.h>
#include <resolv.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/ioctl.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <sys/mount.h>
#undef __USE_MISC
#include <linux/if.h>
#include <linux/wireless.h>
#include <linux/keyboard.h>
#include <linux/kd.h>
#include <linux/hdreg.h>
#include <linux/vt.h>
#include <linux/fd.h>
#include <linux/cdrom.h>
#include <linux/loop.h>
#include <linux/blkpg.h>
#include <linux/iso_fs.h>
#include <net/if.h>
#include <net/route.h>
#include <netinet/in.h>
#include <linux/sockios.h>
#include <linux/input.h>
#include <execinfo.h>

// for ethtool structs:
typedef unsigned long long u64;
typedef __uint32_t u32;
typedef __uint16_t u16;
typedef __uint8_t u8;

#include <linux/ethtool.h>

// for UPS on USB:
# define HID_MAX_USAGES 1024
#include <linux/hiddev.h>

#include <string.h>

#define SECTORSIZE 512

#include <parted/parted.h>
';

$Config{archname} =~ /i.86/ and print '
const char *pcmcia_probe(void);
';

print '

/* log_message and log_perror are used in stage1 pcmcia probe */
void log_message(const char * s, ...) {
   va_list args;
   va_list args_copy;
   FILE * logtty = fopen("/var/log/stage2.log", "a");
   if (!logtty)
      return;
   fprintf(logtty, "* ");
   va_copy(args_copy, args);
   va_start(args_copy, s);
   vfprintf(logtty, s, args_copy);
   fprintf(logtty, "\n");
   fclose(logtty);
   va_end(args_copy);
}
void log_perror(const char *msg) {
   log_message("%s: %s", msg, strerror(errno));
}


';

print '

int length_of_space_padded(char *str, int len) {
  while (len >= 0 && str[len-1] == \' \')
    --len;
  return len;
}

MODULE = c::stuff		PACKAGE = c::stuff

';

$Config{archname} =~ /i.86/ and print '
const char *
pcmcia_probe()
';

print '
int
del_partition(hd, part_number)
  int hd
  int part_number
  CODE:
  {
    struct blkpg_partition p = { 0, 0, part_number, "", "" };
    struct blkpg_ioctl_arg s = { BLKPG_DEL_PARTITION, 0, sizeof(struct blkpg_partition), (void *) &p };
    RETVAL = ioctl(hd, BLKPG, &s) == 0;
  }
  OUTPUT:
  RETVAL

int
add_partition(hd, part_number, start_sector, size_sector)
  int hd
  int part_number
  unsigned long start_sector
  unsigned long size_sector
  CODE:
  {
    long long start = (long long) start_sector * 512;
    long long size = (long long) size_sector * 512;
    struct blkpg_partition p = { start, size, part_number, "", "" };
    struct blkpg_ioctl_arg s = { BLKPG_ADD_PARTITION, 0, sizeof(struct blkpg_partition), (void *) &p };
    RETVAL = ioctl(hd, BLKPG, &s) == 0;
  }
  OUTPUT:
  RETVAL

int
is_secure_file(filename)
  char * filename
  CODE:
  {
    int fd;
    unlink(filename); /* in case it exists and we manage to remove it */
    RETVAL = (fd = open(filename, O_RDWR | O_CREAT | O_EXCL, 0600)) != -1;
    if (RETVAL) close(fd);
  }
  OUTPUT:
  RETVAL

void
init_setlocale()
   CODE:
   setlocale(LC_ALL, "");
   setlocale(LC_NUMERIC, "C"); /* otherwise eval "1.5" returns 1 in fr_FR for example */

char *
setlocale(category, locale = 0) 
    int     category
    char *      locale

int
lseek_sector(fd, sector, offset)
  int fd
  unsigned long sector
  long offset
  CODE:
  RETVAL = lseek64(fd, (off64_t) sector * SECTORSIZE + offset, SEEK_SET) >= 0;
  OUTPUT:
  RETVAL

int
isBurner(fd)
  int fd
  CODE:
  RETVAL = ioctl(fd, CDROM_GET_CAPABILITY) & CDC_CD_RW;
  OUTPUT:
  RETVAL

int
isDvdDrive(fd)
  int fd
  CODE:
  RETVAL = ioctl(fd, CDROM_GET_CAPABILITY) & CDC_DVD;
  OUTPUT:
  RETVAL

char *
floppy_info(name)
  char * name
  CODE:
  int fd = open(name, O_RDONLY | O_NONBLOCK);
  RETVAL = NULL;
  if (fd != -1) {
     char drivtyp[17];
     if (ioctl(fd, FDGETDRVTYP, (void *)drivtyp) == 0) {
       struct floppy_drive_struct ds;
       if (ioctl(fd, FDPOLLDRVSTAT, &ds) == 0 && ds.track >= 0)
         RETVAL = drivtyp;
     }
     close(fd);
  }
  OUTPUT:
  RETVAL

NV
total_sectors(fd)
  int fd
  CODE:
  {
    unsigned long long ll;
    unsigned long l;
    RETVAL = ioctl(fd, BLKGETSIZE64, &ll) == 0 ? ll / 512 : 
             ioctl(fd, BLKGETSIZE, &l) == 0 ? l : 0;
  }
  OUTPUT:
  RETVAL

void
openlog(ident)
  char *ident
  CODE:
  openlog(ident, 0, 0);

void
closelog()

void
syslog(priority, mesg)
  int priority
  char *mesg
  CODE:
  syslog(priority, "%s", mesg);

void
setsid()

void
_exit(status)
  int status

void
usleep(microseconds)
  unsigned long microseconds


unsigned int
getpagesize()


char*
get_usb_ups_name(int fd)
  CODE:
        /* from nut/drivers/hidups.c::upsdrv_initups() : */
        char name[256];
        ioctl(fd, HIDIOCGNAME(sizeof(name)), name);
        RETVAL=name;
        ioctl(fd, HIDIOCINITREPORT, 0);
  OUTPUT:
  RETVAL


int
res_init()

int
isNetDeviceWirelessAware(device)
  char * device
  CODE:
    struct iwreq ifr;

    int s = socket(AF_INET, SOCK_DGRAM, 0);

    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, device, IFNAMSIZ);
    RETVAL = ioctl(s, SIOCGIWNAME, &ifr) != -1;
    close(s);
  OUTPUT:
  RETVAL


void
get_netdevices()
  PPCODE:
     struct ifconf ifc;
     struct ifreq *ifr;
     int i;
     int numreqs = 10;

     int s = socket(AF_INET, SOCK_DGRAM, 0);

     ifc.ifc_buf = NULL;
     for (;;) {
          ifc.ifc_len = sizeof(struct ifreq) * numreqs;
          ifc.ifc_buf = (char*)realloc(ifc.ifc_buf, ifc.ifc_len);

          if (ioctl(s, SIOCGIFCONF, &ifc) < 0) {
               perror("SIOCGIFCONF");
               close(s);
               return;
          }
          if (ifc.ifc_len == sizeof(struct ifreq) * numreqs) {
               /* assume it overflowed and try again */
               numreqs += 10;                                                                         
               continue;                                                                              
          }
          break;
     }
     if (ifc.ifc_len) {
          ifr = ifc.ifc_req;
          EXTEND(sp, ifc.ifc_len);
          for (i=0; i < ifc.ifc_len; i+= sizeof(struct ifreq)) {
               PUSHs(sv_2mortal(newSVpv(ifr->ifr_name, 0)));
               ifr++;
          }
     }

     close(s);


char*
getNetDriver(char* device)
  ALIAS:
    getHwIDs = 1
  CODE:
    struct ifreq ifr;
    struct ethtool_drvinfo drvinfo;
    int s = socket(AF_INET, SOCK_DGRAM, 0);

    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, device, IFNAMSIZ);

    drvinfo.cmd = ETHTOOL_GDRVINFO;
    ifr.ifr_data = (caddr_t) &drvinfo;

    if (ioctl(s, SIOCETHTOOL, &ifr) != -1) {
        switch (ix) {
            case 0:
                RETVAL = strdup(drvinfo.driver);
                break;
            case 1:
                RETVAL = strdup(drvinfo.bus_info);
                break;
        }
    } else { perror("SIOCETHTOOL"); RETVAL = strdup(""); }
    close(s);
  OUTPUT:
  RETVAL


int
addDefaultRoute(gateway)
  char *gateway
  CODE:
    struct rtentry route;
    struct sockaddr_in addr;
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s == -1) { RETVAL = 0; return; }

    memset(&route, 0, sizeof(route));

    addr.sin_family = AF_INET;
    addr.sin_port = 0;
    inet_aton(gateway, &addr.sin_addr);
    memcpy(&route.rt_gateway, &addr, sizeof(addr));

    addr.sin_addr.s_addr = INADDR_ANY;
    memcpy(&route.rt_dst, &addr, sizeof(addr));
    memcpy(&route.rt_genmask, &addr, sizeof(addr));

    route.rt_flags = RTF_UP | RTF_GATEWAY;
    route.rt_metric = 0;

    RETVAL = !ioctl(s, SIOCADDRT, &route);
  OUTPUT:
  RETVAL


char*
get_hw_address(const char* ifname)
  CODE:
    int s;
    struct ifreq ifr;
    unsigned char *a;
    char *res;
    s = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP);
    if (s < 0) {
        perror("socket");
        RETVAL = NULL;
        return;
    }
    strncpy((char*) &ifr.ifr_name, ifname, IFNAMSIZ);
    if (ioctl(s, SIOCGIFHWADDR, &ifr) < 0) {
        perror("ioctl(SIOCGIFHWADDR)");
        RETVAL = NULL;
        return;
    }
    a = (unsigned char*)ifr.ifr_hwaddr.sa_data;
    asprintf(&res, "%02x:%02x:%02x:%02x:%02x:%02x", a[0],a[1],a[2],a[3],a[4],a[5]);
    RETVAL= res;
  OUTPUT:
  RETVAL


void
strftime(fmt, sec, min, hour, mday, mon, year, wday = -1, yday = -1, isdst = -1)
    char *      fmt
    int     sec
    int     min
    int     hour
    int     mday
    int     mon
    int     year
    int     wday
    int     yday
    int     isdst
    CODE:
    {   
        char *buf = my_strftime(fmt, sec, min, hour, mday, mon, year, wday, yday, isdst);
        if (buf) {
        ST(0) = sv_2mortal(newSVpv(buf, 0));
        Safefree(buf);
        }
    }

#define BITS_PER_LONG (sizeof(long) * 8)
#define NBITS(x) ((((x)-1)/BITS_PER_LONG)+1)
#define OFF(x)  ((x)%BITS_PER_LONG)
#define BIT(x)  (1UL<<OFF(x))
#define LONG(x) ((x)/BITS_PER_LONG)
#define test_bit(bit, array)    ((array[LONG(bit)] >> OFF(bit)) & 1)

void
EVIocGBitKey (char *file)
	PPCODE:
		int fd;
		int i;
		long bitmask[NBITS(KEY_MAX)];

		fd = open (file, O_RDONLY);
		if (fd < 0) {
			perror("Cannot open /dev/input/eventX");
			return;
		}

		if (ioctl (fd, EVIOCGBIT(EV_KEY, sizeof (bitmask)), bitmask) < 0) {
			perror ("ioctl EVIOCGBIT failed");
			close (fd);
			return;
		}

		close (fd);
        	for (i = NBITS(KEY_MAX) - 1; i > 0; i--)
			if (bitmask[i])
				break;

		for (; i >= 0; i--) {
			EXTEND(sp, 1);
			PUSHs(sv_2mortal(newSViv(bitmask[i])));
		}

char *
kernel_version()
  CODE:
  struct utsname u;
  if (uname(&u) == 0) RETVAL = u.release; else RETVAL = NULL;
  OUTPUT:
  RETVAL

void
set_tagged_utf8(s)
   SV *s
   CODE:
   SvUTF8_on(s);

void
get_iso_volume_ids(int fd)
  INIT:
  struct iso_primary_descriptor voldesc;
  PPCODE:
  lseek(fd, 16 * ISOFS_BLOCK_SIZE, SEEK_SET);
  if (read(fd, &voldesc, sizeof(struct iso_primary_descriptor)) == sizeof(struct iso_primary_descriptor)) {
    if (voldesc.type[0] == ISO_VD_PRIMARY && !strncmp(voldesc.id, ISO_STANDARD_ID, sizeof(voldesc.id))) {
      size_t vol_id_len = length_of_space_padded(voldesc.volume_id, sizeof(voldesc.volume_id));
      size_t app_id_len = length_of_space_padded(voldesc.application_id, sizeof(voldesc.application_id));
      XPUSHs(vol_id_len != -1 ? sv_2mortal(newSVpv(voldesc.volume_id, vol_id_len)) : newSVpvs(""));
      XPUSHs(app_id_len != -1 ? sv_2mortal(newSVpv(voldesc.application_id, app_id_len)) : newSVpvs(""));
    }
  }

';

print '

const char *
get_disk_type(char * device_path)
  CODE:
  PedDevice *dev = ped_device_get(device_path);
  RETVAL = NULL;
  if(dev) {
    PedDisk* disk = ped_disk_new(dev);
    if(disk) {
      RETVAL = disk->type->name;
      ped_disk_destroy(disk);
    } 
  }
  OUTPUT:
  RETVAL

void
get_disk_partitions(char * device_path)
  PPCODE:
  PedDevice *dev = ped_device_get(device_path);
  if(dev) {
    PedDisk* disk = ped_disk_new(dev);
    PedPartition *part = NULL;
    if(disk)
      part = ped_disk_next_partition(disk, NULL);
    while(part) {
      if(part->num != -1) {
        char desc[4196];
        char *path = ped_partition_get_path(part);
        sprintf(desc, "%d ", part->num);
        sprintf(desc+strlen(desc), "%s ", path);
        free(path);
        if(part->fs_type)
          strcat(desc, part->fs_type->name);
        if(part->type == 0x0)
          strcat(desc, " normal");
        else {
          if(part->type & PED_PARTITION_LOGICAL)
              strcat(desc, " logical");
          if(part->type & PED_PARTITION_EXTENDED)
              strcat(desc, " extended");
          if(part->type & PED_PARTITION_FREESPACE)
              strcat(desc, " freespace");
          if(part->type & PED_PARTITION_METADATA)
              strcat(desc, " metadata");
          if(part->type & PED_PARTITION_PROTECTED)
              strcat(desc, " protected");
        }
        sprintf(desc+strlen(desc), " (%lld,%lld,%lld)", part->geom.start, part->geom.end, part->geom.length);
        XPUSHs(sv_2mortal(newSVpv(desc, 0)));
      }
      part = ped_disk_next_partition(disk, part);
    }
    if(disk)
      ped_disk_destroy(disk);
  }

int
set_disk_type(char * device_path, const char * type_name)
  CODE:
  PedDevice *dev = ped_device_get(device_path);
  RETVAL = 0;
  if(dev) {
    PedDiskType* type = ped_disk_type_get(type_name);
    if(type) {
      PedDisk* disk = ped_disk_new_fresh(dev, type);
      if(disk) {
        RETVAL = ped_disk_commit(disk);
        ped_disk_destroy(disk);
      }
    }
  }
  OUTPUT:
  RETVAL

int
disk_delete_all(char * device_path)
  CODE:
  PedDevice *dev = ped_device_get(device_path);
  RETVAL = 0;
  if(dev) {
    PedDisk* disk = ped_disk_new(dev);
    if(disk) { 
      RETVAL = ped_disk_delete_all(disk);
      if(RETVAL)
        RETVAL = ped_disk_commit(disk);
      ped_disk_destroy(disk);
    }
  }
  OUTPUT:
  RETVAL

int
disk_del_partition(char * device_path, int part_number)
  CODE:
  PedDevice *dev = ped_device_get(device_path);
  RETVAL = 0;
  if(dev) {
    PedDisk* disk = ped_disk_new(dev);
    if(disk) {
      PedPartition* part = ped_disk_get_partition(disk, part_number);
      if(!part) {
        printf("disk_del_partition: failed to find partition\n");
      } else {
        RETVAL=ped_disk_delete_partition(disk, part);
        if(RETVAL) {
          RETVAL = ped_disk_commit(disk);
        } else {
          printf("del_partition failed\n");
        }
      }
      ped_disk_destroy(disk);
    }
  }
  OUTPUT:
  RETVAL

int
disk_add_partition(char * device_path, double start, double length, const char * fs_type)
  CODE:
  PedDevice *dev = ped_device_get(device_path);
  RETVAL=0;
  if(dev) {
    PedDisk* disk = ped_disk_new(dev);
    if(disk) {
      PedGeometry* geom = ped_geometry_new(dev, (long long)start, (long long)length);
      PedPartition* part = ped_partition_new (disk, PED_PARTITION_NORMAL, ped_file_system_type_get(fs_type), (long long)start, (long long)start+length-1);
      PedConstraint* constraint = ped_constraint_new_from_max(geom);
      if(!part) {
        printf("ped_partition_new failed\n");
      } else
        RETVAL = ped_disk_add_partition (disk, part, constraint);
      if(RETVAL) {
        RETVAL = ped_disk_commit(disk);
      } else {
        printf("add_partition failed\n");
      }
      ped_geometry_destroy(geom);
      ped_constraint_destroy(constraint);
      ped_disk_destroy(disk);
    }
  }
  OUTPUT:
  RETVAL

#define BACKTRACE_DEPTH				20
 

char*
C_backtrace()
  CODE:
  static char buf[1024];
  int nAddresses, i;
  unsigned long idx = 0;
  void * addresses[BACKTRACE_DEPTH];
  char ** symbols = NULL;
  nAddresses = backtrace(addresses, BACKTRACE_DEPTH);
  symbols = backtrace_symbols(addresses, nAddresses);
  if (symbols == NULL) {
      idx += sprintf(buf+idx, "ERROR: Retrieving symbols failed.\n");
  } else {
      /* dump stack trace */
      for (i = 0; i < nAddresses; ++i)
          idx += sprintf(buf+idx, "%d: %s\n", i, symbols[i]);
  }
  RETVAL = strdup(buf);
  OUTPUT:
  RETVAL




';

@macros = (
  [ qw(int S_IFCHR S_IFBLK S_IFIFO S_IFMT KDSKBENT K_NOSUCHMAP NR_KEYS MAX_NR_KEYMAPS BLKRRPART TIOCSCTTY
       HDIO_GETGEO LOOP_GET_STATUS
       MS_MGC_VAL O_WRONLY O_RDWR O_CREAT O_NONBLOCK F_SETFL F_GETFL WNOHANG
       VT_ACTIVATE VT_WAITACTIVE VT_GETSTATE
       CDROMEJECT CDROMCLOSETRAY CDROM_LOCKDOOR
       LOG_WARNING LOG_INFO LOG_LOCAL1
       LC_COLLATE
       ) ],
);

$\= "\n";
print;

foreach (@macros) {
    my ($type, @l) = @$_;
    foreach (@l) {
	print<< "END"
$type
$_()
  CODE:
  RETVAL = $_;

  OUTPUT:
  RETVAL

END

    }
}
print '

PROTOTYPES: DISABLE
';

