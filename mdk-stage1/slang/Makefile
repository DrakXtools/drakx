 #******************************************************************************
 #
 # Guillaume Cottenceau (gc@mandrakesoft.com)
 #
 # Copyright 2000 Mandrakesoft
 #
 # This software may be freely redistributed under the terms of the GNU
 # public license.
 #
 # You should have received a copy of the GNU General Public License
 # along with this program; if not, write to the Free Software
 # Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 #
 #*****************************************************************************

top_dir = ..

include $(top_dir)/Makefile.common


LIBNAME = libslang

OBJS = sltermin.o sldisply.o slutty.o slang.o slarray.o slclass.o slcmd.o slerr.o slgetkey.o slkeymap.o slmalloc.o slmath.o slmemchr.o slmemcmp.o slmemcpy.o slmemset.o slmisc.o slparse.o slprepr.o slregexp.o slrline.o slsearch.o slsmg.o slstd.o sltoken.o sltypes.o slxstrng.o slcurses.o slscroll.o slsignal.o slkeypad.o slerrno.o slstring.o slstruct.o slcmplex.o slarrfun.o slimport.o slpath.o slarith.o slassoc.o slcompat.o slposdir.o slstdio.o slproc.o sltime.o slstrops.o slbstr.o slpack.o slintall.o slistruc.o slposio.o slnspace.o slarrmis.o slospath.o slscanf.o

DEFS = -Dunix -DSLANG

INCS = 


TARGETS = $(LIBNAME).a

all: $(TARGETS)

clean:
	rm -f *.o *.a

$(LIBNAME).a: $(OBJS)
	ar -cru $@ $^
	ranlib $@

$(OBJS): %.o: %.c
	$(DIET) gcc $(CFLAGS) $(DEFS) $(INCS) $(INCLUDES) -c $< -o $@
