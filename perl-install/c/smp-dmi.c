/*
 *	CPU detetion based on DMI decode rev 1.2
 *
 *	(C) 2003 Nicolas Planel <nplanel@mandrakesoft.com>
 *      
 *	Licensed under the GNU Public license. If you want to use it in with
 *	another license just ask.
 */

#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <stdlib.h>

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;

static void
dump_raw_data(void *data, unsigned int length)
{
	unsigned char buffer1[80], buffer2[80], *b1, *b2, c;
	unsigned char *p = data;
	unsigned long column=0;
	unsigned int length_printed = 0;
	const unsigned char maxcolumn = 16;
	while (length_printed < length) {
		b1 = buffer1;
		b2 = buffer2;
		for (column = 0;
		     column < maxcolumn && length_printed < length; 
		     column ++) {
			b1 += sprintf(b1, "%02x ",(unsigned int) *p);
			if (*p < 32 || *p > 126) c = '.';
			else c = *p;
			b2 += sprintf(b2, "%c", c);
			p++;
			length_printed++;
		}
		/* pad out the line */
		for (; column < maxcolumn; column++)
		{
			b1 += sprintf(b1, "   ");
			b2 += sprintf(b2, " ");
		}
		
		printf("%s\t%s\n", buffer1, buffer2);
	}
}



struct dmi_header
{
	u8	type;
	u8	length;
	u16	handle;
};

static char *dmi_string(struct dmi_header *dm, u8 s)
{
	u8 *bp=(u8 *)dm;
	if (!s) return "";
	
	bp+=dm->length;
	while(s>1)
	{
		bp+=strlen(bp);
		bp++;
		s--;
	}
	return bp;
}

static char *dmi_processor_type(u8 code)
{
	static char *processor_type[]={
		"",
		"Other",
		"Unknown",
		"Central Processor",
		"Math Processor",
		"DSP Processor",
		"Video Processor"
	};
	
	if(code == 0xFF)
		return "Other";
	
	if (code > 0xA1)
		return "";
	return processor_type[code];
}

static char *dmi_processor_family(u8 code)
{
	static char *processor_family[]={
		"",
		"Other",
		"Unknown",
		"8086",
		"80286",
		"Intel386 processor",
		"Intel486 processor",
		"8087",
		"80287",
		"80387",
		"80487",
		"Pentium processor Family",
		"Pentium Pro processor",
		"Pentium II processor",
		"Pentium processor with MMX technology",
		"Celeron processor",
		"Pentium II Xeon processor",
		"Pentium III processor",
		"M1 Family",
		"M1","M1","M1","M1","M1","M1", /* 13h - 18h */
		"K5 Family",
		"K5","K5","K5","K5","K5","K5", /* 1Ah - 1Fh */
		"Power PC Family",
		"Power PC 601",
		"Power PC 603",
		"Power PC 603+",
		"Power PC 604",
	};
	
	if(code == 0xFF)
		return "Other";
	
	if (code > 0x24)
		return "";
	return processor_family[code];
}

typedef int (*dmi_decode)(u8 * data);

static int decode_handle(int fd, u32 base, int len, int num, dmi_decode decode)
{
	u8 *buf = malloc(len);
	struct dmi_header *dm;
	u8 *data;
	int i = 0;
	int ret = 0;
	
	if (lseek(fd, (long)base, 0) == -1) {
		perror("dmi: lseek");
		return;
	}
	if (read(fd, buf, len)!=len) {
		perror("dmi: read");
		return;
	}
	data = buf;
	while(i<num && data+sizeof(struct dmi_header)<=buf+len)
	{
		u8 *next;
		struct dmi_header *dm = (struct dmi_header *)data;

		/* look for the next handle */
		next=data+dm->length;
		while(next-buf+1<len && (next[0]!=0 || next[1]!=0))
			next++;
		next+=2;
		if(next-buf<=len)
			ret += decode(data);
		else {
			ret = 0; /* TRUNCATED */
			break;
		}
		data=next;
		i++;
	}
	free(buf);
	return ret;
}

static int dmi_detect(dmi_decode decode) {
  	unsigned char buf[20];
	int fd = open("/dev/mem", O_RDONLY);
	long fp = 0xE0000L;
	int ret = 0;

	if (fd == -1) {
		perror("/dev/mem");
		exit(1);
	}
	if (lseek(fd, fp, 0) == -1) {
		perror("seek");
		exit(1);
	}
	
	while (fp < 0xFFFFF)
	{
		if (read(fd, buf, 16) != 16)
			perror("read");
		
		if (memcmp(buf, "_DMI_", 5) == 0) {
			u16 num = buf[13]<<8|buf[12];
			u16 len = buf[7]<<8|buf[6];
			u32 base = buf[11]<<24|buf[10]<<16|buf[9]<<8|buf[8];
			
			ret = decode_handle(fd, base, len, num, decode);
			break;
		}
		fp += 16;
	}
	close(fd);
	return ret;
}

static int processor(u8 *data) {
	struct dmi_header *dm = (struct dmi_header *)data;

	if((dm->type == 4) && /*"Central Processor"*/(data[5] == 3)) {
		if(/*Processor Manufacturer*/data[7] != 0) 
			return 1;
	}
	return 0;
}

static int memory_in_MB(u8 *data)
{
	struct dmi_header *dm;
	
	int form_factor_check(u8 code) {
		/* 3.3.18.1 */
		static const char form_factor[]={
			0, /* "Other", */ /* 0x01 */
			0, /* "Unknown", */
			1, /* "SIMM", */
			1, /* "SIP", */
			0, /* "Chip", */
			1, /* "DIP", */
			0, /* "ZIP", */
			0, /* "Proprietary Card", */
			1, /* "DIMM", */
			0, /* "TSOP", */
			0, /* "Row Of Chips", */
			1, /* "RIMM", */
			1, /* "SODIMM", */
			1, /* "SRIMM" *//* 0x0E */
		};

		if(code>=0x01 && code<=0x0E)
			return form_factor[code-0x01];
		return 0; /* out of spec */
	}
	int dmi_memory_device_size(u16 code) {
		int mult = 1;

		if (code == 0 || code == 0xFFFF)
			return 0;
		if (code & 0x8000) /* code is in KB */
			mult = 1024;
		return (code & 0x7FFF) * mult;
	}

	dm = (struct dmi_header *)data;
		
	if ((dm->type == 17) && (dm->length >= 0x15)) {
		if (form_factor_check(data[0x0E]))
			return dmi_memory_device_size((data[0x0D] << 8) + data[0x0C]);
	}
	
	return 0;
}

int intelDetectSMP(void) {
	return dmi_detect(processor) > 1;
}

int dmiDetectMemory(void) {
	return dmi_detect(memory_in_MB);
}
