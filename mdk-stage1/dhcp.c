/*
 * Guillaume Cottenceau (gc@mandrakesoft.com)
 *
 * Copyright 2000 MandrakeSoft
 *
 * View the homepage: http://us.mandrakesoft.com/~gc/html/stage1.html
 *
 *
 * This software may be freely redistributed under the terms of the GNU
 * public license.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

/*
 *  Portions from GRUB  --  GRand Unified Bootloader
 *  Copyright (C) 2000  Free Software Foundation, Inc.
 *
 *  Itself based on etherboot-4.6.4 by Martin Renters.
 *
 */

#include <stdlib.h>
#include <unistd.h>
#include <sys/time.h>
#include "stage1.h"

#include "dhcp.h"


static int currticks (void)
{
  struct timeval tv;
  long csecs;
  int ticks_per_csec, ticks_per_usec;

  /* Note: 18.2 ticks/sec.  */

  /* Get current time.  */
  gettimeofday (&tv, 0);

  /* Compute centiseconds.  */
  csecs = tv.tv_sec / 10;

  /* Ticks per centisecond.  */
  ticks_per_csec = csecs * 182;

  /* Ticks per microsecond.  */
  ticks_per_usec = (((tv.tv_sec - csecs * 10) * 1000000 + tv.tv_usec)
		    * 182 / 10000000);

  /* Sum them.  */
  return ticks_per_csec + ticks_per_usec;
}


static char rfc1533_cookie[] = { RFC1533_COOKIE };
static char rfc1533_end[] = { RFC1533_END };

static const char dhcpdiscover[] =
{
  RFC2132_MSG_TYPE, 1, DHCPDISCOVER,	
  RFC2132_MAX_SIZE,2,	/* request as much as we can */
  sizeof(struct bootpd_t) / 256, sizeof(struct bootpd_t) % 256,
  RFC2132_PARAM_LIST, 4, RFC1533_NETMASK, RFC1533_GATEWAY,
  RFC1533_HOSTNAME, RFC1533_EXTENSIONPATH
};

static const char dhcprequest[] =
{
  RFC2132_MSG_TYPE, 1, DHCPREQUEST,
  RFC2132_SRV_ID, 4, 0, 0, 0, 0,
  RFC2132_REQ_ADDR, 4, 0, 0, 0, 0,
  RFC2132_MAX_SIZE,2,	/* request as much as we can */
  sizeof(struct bootpd_t) / 256, sizeof(struct bootpd_t) % 256,
  /* request parameters */
  RFC2132_PARAM_LIST,
  4 + 2,
  /* Standard parameters */
  RFC1533_NETMASK, RFC1533_GATEWAY,
  RFC1533_HOSTNAME, RFC1533_EXTENSIONPATH,
  /* Etherboot vendortags */
  RFC1533_VENDOR_MAGIC,
  RFC1533_VENDOR_CONFIGFILE,
};


static unsigned long xid;
static int sock;

static int await_reply (int type, int ival, void *ptr, int timeout)
{
	unsigned long time;
	struct iphdr *ip;
	struct udphdr *udp;
	struct arprequest *arpreply;
	struct bootp_t *bootpreply;
	unsigned short ptype;
	unsigned int protohdrlen = (ETHER_HDR_SIZE + sizeof (struct iphdr) + sizeof (struct udphdr));
	
	/* Clear the abort flag.  */
	ip_abort = 0;
	
	time = currticks () + TIMEOUT;
	/* The timeout check is done below.  The timeout is only checked if
	 * there is no packet in the Rx queue.  This assumes that eth_poll()
	 * needs a negligible amount of time.  */
	for (;;)
	{
		if (eth_poll ())
	{
	  /* We have something!  */
	  
	  /* Check for ARP - No IP hdr.  */
	  if (nic.packetlen >= ETHER_HDR_SIZE)
	    {
	      ptype = (((unsigned short) nic.packet[12]) << 8
		       | ((unsigned short) nic.packet[13]));
	    }
	  else
	    /* What else could we do with it?  */
	    continue;
	  
	  if (nic.packetlen >= ETHER_HDR_SIZE + sizeof (struct arprequest)
	      && ptype == ARP)
	    {
	      unsigned long tmp;

	      arpreply = (struct arprequest *) &nic.packet[ETHER_HDR_SIZE];
	      
	      if (arpreply->opcode == ntohs (ARP_REPLY)
		  && ! grub_memcmp (arpreply->sipaddr, ptr, sizeof (in_addr))
		  && type == AWAIT_ARP)
		{
		  grub_memmove ((char *) arptable[ival].node,
				arpreply->shwaddr,
				ETHER_ADDR_SIZE);
		  return 1;
		}
	      
	      grub_memmove ((char *) &tmp, arpreply->tipaddr,
			    sizeof (in_addr));
	      
	      if (arpreply->opcode == ntohs (ARP_REQUEST)
		  && tmp == arptable[ARP_CLIENT].ipaddr.s_addr)
		{
		  arpreply->opcode = htons (ARP_REPLY);
		  grub_memmove (arpreply->tipaddr, arpreply->sipaddr,
				sizeof (in_addr));
		  grub_memmove (arpreply->thwaddr, (char *) arpreply->shwaddr,
				ETHER_ADDR_SIZE);
		  grub_memmove (arpreply->sipaddr,
				(char *) &arptable[ARP_CLIENT].ipaddr,
				sizeof (in_addr));
		  grub_memmove (arpreply->shwaddr,
				arptable[ARP_CLIENT].node,
				ETHER_ADDR_SIZE);
		  eth_transmit (arpreply->thwaddr, ARP,
				sizeof (struct arprequest),
				arpreply);
#ifdef MDEBUG
		  grub_memmove (&tmp, arpreply->tipaddr, sizeof (in_addr));
		  grub_printf ("Sent ARP reply to: %x\n", tmp);
#endif	/* MDEBUG */
		}
	      
	      continue;
	    }

	  if (type == AWAIT_QDRAIN)
	    {
	      continue;
	    }
	  
	  /* Check for RARP - No IP hdr.  */
	  if (type == AWAIT_RARP
	      && nic.packetlen >= ETHER_HDR_SIZE + sizeof (struct arprequest)
	      && ptype == RARP)
	    {
	      arpreply = (struct arprequest *) &nic.packet[ETHER_HDR_SIZE];
	      
	      if (arpreply->opcode == ntohs (RARP_REPLY)
		  && ! grub_memcmp (arpreply->thwaddr, ptr, ETHER_ADDR_SIZE))
		{
		  grub_memmove ((char *) arptable[ARP_SERVER].node,
				arpreply->shwaddr, ETHER_ADDR_SIZE);
		  grub_memmove ((char *) &arptable[ARP_SERVER].ipaddr,
				arpreply->sipaddr, sizeof (in_addr));
		  grub_memmove ((char *) &arptable[ARP_CLIENT].ipaddr,
				arpreply->tipaddr, sizeof (in_addr));
		  return 1;
		}
	      
	      continue;
	    }

	  /* Anything else has IP header.  */
	  if (nic.packetlen < protohdrlen || ptype != IP)
	    continue;
	  
	  ip = (struct iphdr *) &nic.packet[ETHER_HDR_SIZE];
	  if (ip->verhdrlen != 0x45
	      || ipchksum ((unsigned short *) ip, sizeof (struct iphdr))
	      || ip->protocol != IP_UDP)
	    continue;
	  
	  udp = (struct udphdr *)
	    &nic.packet[ETHER_HDR_SIZE + sizeof (struct iphdr)];
	  
	  /* BOOTP ?  */
	  bootpreply = (struct bootp_t *) &nic.packet[ETHER_HDR_SIZE];
	  if (type == AWAIT_BOOTP
#ifdef NO_DHCP_SUPPORT
	      && (nic.packetlen
		  >= (ETHER_HDR_SIZE + sizeof (struct bootp_t)))
#else
	      && (nic.packetlen
		  >= (ETHER_HDR_SIZE + sizeof (struct bootp_t)) - DHCP_OPT_LEN)
#endif /* ! NO_DHCP_SUPPORT */
	      && ntohs (udp->dest) == BOOTP_CLIENT
	      && bootpreply->bp_op == BOOTP_REPLY
	      && bootpreply->bp_xid == xid)
	    {
	      arptable[ARP_CLIENT].ipaddr.s_addr
		= bootpreply->bp_yiaddr.s_addr;
#ifndef	NO_DHCP_SUPPORT
	      dhcp_addr.s_addr = bootpreply->bp_yiaddr.s_addr;
#endif /* ! NO_DHCP_SUPPORT */
	      netmask = default_netmask ();
	      arptable[ARP_SERVER].ipaddr.s_addr
		= bootpreply->bp_siaddr.s_addr;
	      /* Kill arp.  */
	      grub_memset (arptable[ARP_SERVER].node, 0, ETHER_ADDR_SIZE);
	      arptable[ARP_GATEWAY].ipaddr.s_addr
		= bootpreply->bp_giaddr.s_addr;
	      /* Kill arp.  */
	      grub_memset (arptable[ARP_GATEWAY].node, 0, ETHER_ADDR_SIZE);

	      /* GRUB doesn't autoload any kernel image.  */
#ifndef GRUB
	      if (bootpreply->bp_file[0])
		{
		  grub_memmove (kernel_buf, bootpreply->bp_file, 128);
		  kernel = kernel_buf;
		}
#endif /* ! GRUB */
	      
	      grub_memmove ((char *) BOOTP_DATA_ADDR, (char *) bootpreply,
			    sizeof (struct bootpd_t));
#ifdef NO_DHCP_SUPPORT
	      decode_rfc1533 (BOOTP_DATA_ADDR->bootp_reply.bp_vend,
			      0, BOOTP_VENDOR_LEN + MAX_BOOTP_EXTLEN, 1);
#else
	      decode_rfc1533 (BOOTP_DATA_ADDR->bootp_reply.bp_vend,
			      0, DHCP_OPT_LEN, 1);
#endif /* ! NO_DHCP_SUPPORT */
	      
	      return 1;
	    }
	  
	  /* TFTP ? */
	  if (type == AWAIT_TFTP && ntohs (udp->dest) == ival)
	    return 1;
	}
      else
	{
	  /* Check for abort key only if the Rx queue is empty -
	   * as long as we have something to process, don't
	   * assume that something failed.  It is unlikely that
	   * we have no processing time left between packets.  */
	  if (checkkey () != -1 && ASCII_CHAR (getkey ()) == CTRL_C)
	    {
	      ip_abort = 1;
	      return 0;
	    }
	  
	  /* Do the timeout after at least a full queue walk.  */
	  if ((timeout == 0) || (currticks() > time))
	    {
	      break;
	    }
	}
    }
  
  return 0;
}


static int bootp(struct interface_info * intf)
{
	int retry;
	int retry1;
	struct bootp_t bp;
	unsigned long starttime;
	struct ifreq req;
	int s;

	strcpy(req.ifr_name, intf->name);
	if (ioctl(sock, SIOCGIFHWADDR, &req)) {
		log_perror("SIOCSIFHWADDR");
		return -1;
	}

	memset (&bp, 0, sizeof (struct bootp_t));
	bp.bp_op = BOOTP_REQUEST;
	bp.bp_htype = 1;
	bp.bp_hlen = ETHER_ADDR_SIZE;
	bp.bp_xid = xid = starttime = currticks ();


	memmove(bp.bp_hwaddr, req.ifr_hwaddr.sa_data, ETHER_ADDR_SIZE);

	/* Request RFC-style options.  */
	memmove(bp.bp_vend, rfc1533_cookie, sizeof rfc1533_cookie);
	memmove(bp.bp_vend + sizeof rfc1533_cookie, dhcpdiscover, sizeof dhcpdiscover);
	memmove(bp.bp_vend + sizeof rfc1533_cookie + sizeof dhcpdiscover, rfc1533_end, sizeof rfc1533_end);

	for (retry = 0; retry < MAX_BOOTP_RETRIES;)
	{
		/* Clear out the Rx queue first.  It contains nothing of
		 * interest, except possibly ARP requests from the DHCP/TFTP
		 * server.  We use polling throughout Etherboot, so some time
		 * may have passed since we last polled the receive queue,
		 * which may now be filled with broadcast packets.  This will
		 * cause the reply to the packets we are about to send to be
		 * lost immediately.  Not very clever.  */
		await_reply (AWAIT_QDRAIN, 0, NULL, 0);
		
		udp_transmit (IP_BROADCAST, BOOTP_CLIENT, BOOTP_SERVER,
			      sizeof (struct bootp_t), &bp);
		
		if (await_reply (AWAIT_BOOTP, 0, NULL, TIMEOUT))
		{
			if (dhcp_reply == DHCPOFFER)
			{
				dhcp_reply = 0;
				grub_memmove (bp.bp_vend, rfc1533_cookie, sizeof rfc1533_cookie);
				grub_memmove (bp.bp_vend + sizeof rfc1533_cookie,
					      dhcprequest, sizeof dhcprequest);
				grub_memmove (bp.bp_vend + sizeof rfc1533_cookie
					      + sizeof dhcprequest,
					      rfc1533_end, sizeof rfc1533_end);
				grub_memmove (bp.bp_vend + 9, (char *) &dhcp_server,
					      sizeof (in_addr));
				grub_memmove (bp.bp_vend + 15, (char *) &dhcp_addr,
					      sizeof (in_addr));
				for (retry1 = 0; retry1 < MAX_BOOTP_RETRIES;)
				{
					udp_transmit (IP_BROADCAST, 0, BOOTP_SERVER,
						      sizeof (struct bootp_t), &bp);
					dhcp_reply = 0;
					if (await_reply (AWAIT_BOOTP, 0, NULL, TIMEOUT))
						if (dhcp_reply == DHCPACK)
						{
							network_ready = 1;
							return 1;
						}
					
					if (ip_abort)
						return 0;
					
					rfc951_sleep (++retry1);
				}
				
				/* Timeout.  */
				return 0;
			}
			else
			{
				network_ready = 1;
				return 1;
			}
		}
      
		if (ip_abort)
			return 0;
		
		rfc951_sleep (++retry);
		bp.bp_secs = htons ((currticks () - starttime) / 20);
	}
	
	/* Timeout.  */
	return 0;
}


enum return_type setup_network_intf_as_dhcp(struct interface_info * intf)
{
	sock = socket(AF_INET, SOCK_DGRAM, 0);
	if (sock < 0) {
		return log_perror("socket");
		return -1;
	}

	return RETURN_ERROR;
}
