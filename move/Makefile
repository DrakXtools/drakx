DEST = /tmp
DEST_LIVETREE = $(DEST)/live_tree
DEST_STAGE2 = $(DEST_LIVETREE)/usr/lib/stage2

ISO = /tmp/mdkmove.iso

DATA_FILES = devices symlinks directories-to-create etcfiles all-etcfiles keyfiles \
             BOOT-800-MOVE.jpg BOOT-1024-MOVE.jpg BOOT-1280-MOVE.jpg BOOT-1600-MOVE.jpg

PROGRAM_FILES = etc-monitorer.pl tree/startkde_move tree/wait4x tree/netscape tree/alsa_default.pl
LANG_FILES = $(shell perl -ne 'print $$1 if /ALLOWED_LANGS = qw\((.*)\)/' move.pm)

STAGE1 = ../mdk-stage1
INSTALL = ../perl-install

INSTALL_FILES = install2.pm install_steps.pm install_any.pm install_interactive.pm install_steps_gtk.pm install_steps_interactive.pm install_messages.pm install_gtk.pm

ARCH := $(shell arch | egrep "(x86_64|sparc64|s390x)")
ifneq ("x$(ARCH)", "x")
LIB_NAME = lib64
else
LIB_NAME = lib
endif

.PHONY: iso 

default: install

get_dest_livetree:
	@echo -n $(DEST_LIVETREE)

iso: build install live_tree_boot big_clps only_iso


build: stage1 xwait runlevel_set
	$(MAKE) -C ../perl-install mo_files

data/isolinux-graphic.bmp.parameters: data/isolinux-graphic.bmp
	perl -I $(INSTALL) $(INSTALL)/standalone/draksplash2 --kernel isolinux/vmlinuz --initrd isolinux/all.rdz $<

data/i18n_en.list:
	cd data ; ./make_i18n_list $(DEST_LIVETREE)

install: un_live_tree_boot data/i18n_en.list
	sudo ./collect-directories-to-create.pl $(DEST_LIVETREE) > data/directories-to-create
	sudo find $(DEST_LIVETREE)/etc -type f | perl -pe 's|$(DEST_LIVETREE)||' > data/all-etcfiles

	sudo cp -f $(STAGE1)/init-move $(DEST_LIVETREE)/sbin/init

	$(MAKE) -C ../perl-install/share/po install NAME=libDrakX DATADIR=$(DEST_LIVETREE)/usr/share

	sudo cp -f xwait $(DEST_LIVETREE)/usr/bin
	sudo cp -f runlevel_set $(DEST_LIVETREE)/usr/bin
	sudo cp -f runstage2 $(DEST_LIVETREE)/usr/bin/runstage2.pl
	sudo rm -rf $(DEST_STAGE2)
	sudo mkdir -p $(DEST_STAGE2)
	sudo sh -c 'echo 1 > $(DEST_STAGE2)/help.pm'
	sudo cp -f *.pm $(DEST_STAGE2)
	sudo cp -f $(addprefix $(INSTALL)/, $(INSTALL_FILES)) $(DEST_STAGE2)
	sudo cp -f $(PROGRAM_FILES) $(DEST_LIVETREE)/usr/bin
	sudo rm -f $(DEST_LIVETREE)/usr/bin/{halt,reboot}  #- symlinks to consolehelper
	sudo cp -f tree/{halt,reboot} $(DEST_LIVETREE)/usr/bin
	sudo cp -f tree/X_move $(DEST_LIVETREE)/usr/X11R6/bin
	sudo cp -f tree/sound.initscript $(DEST_LIVETREE)/etc/init.d/sound

	sudo rm -rf $(DEST_LIVETREE)/usr/share/langs
	sudo mkdir -p $(DEST_LIVETREE)/usr/share/langs
	sudo cp -f $(INSTALL)/pixmaps/langs/lang-*.png $(DEST_LIVETREE)/usr/share/langs

	 #- overwrite /usr/lib/libDrakX files of the live tree with those in CVS
	(cd $(DEST_LIVETREE)/usr/lib/libDrakX ; find -name "*.pm") | egrep -v 'ctxhelp|drakfirsttime' | (cd $(INSTALL) ; sudo cpio -pLumd $(DEST_LIVETREE)/usr/lib/libDrakX/)

	 #- overwrite stuff.so of drakxtools because it doesn't contain C_DRAKX stuff
	sudo cp -f ../perl-install/c/blib/arch/auto/stuff/stuff.so $(DEST_LIVETREE)/usr/lib/libDrakX/auto/c/stuff

	 #- overwrite MDK-Common
#	sudo cp -f ../../soft/perl-MDK-Common/MDK/Common/*.pm $(DEST_LIVETREE)/usr/$(LIB_NAME)/perl5/vendor_perl/*/MDK/Common

	 #- duplicated :(
	sudo perl -pi -e 's/#[-+].*//; $$_ = "\n" if (/^=(head|begin)/ .. /^=cut/) || /use (diagnostics|vars|strict)/' $(DEST_STAGE2)/*.pm `find $(DEST_LIVETREE)/usr/lib/libDrakX -name "*.pm"`

	sudo mkdir -p $(DEST_LIVETREE)/move
	sudo cp -f $(addprefix data/, $(DATA_FILES)) $(DEST_LIVETREE)/move

	sudo install -m 440 tree/sudoers $(DEST_LIVETREE)/etc
	sudo install -m 644 tree/mdk_move_boot_loop.desktop $(DEST_LIVETREE)/usr/share/autostart
	sudo install tree/{mdk_move_loop,mdk_totem,mdk_behind_totem} $(DEST_LIVETREE)/usr/bin
	sudo install -m 644 -D tree/mdk_totem.desktop $(DEST_LIVETREE)/usr/share/apps/kdesktop/DesktopLinks/mdk_totem.desktop
	sudo install -m 644 tree/{kdedrc,konsolerc} $(DEST_LIVETREE)/usr/share/config
	sudo install -m 644 img/Mandrake.png $(DEST_LIVETREE)/usr/share/mdk/backgrounds
	sudo install -m 644 img/FE* $(DEST_LIVETREE)/usr/share/wallpapers

	grep ChangeLog $(INSTALL)/CVS/Entries > /tmp/version
	sudo cp -f /tmp/version $(DEST_LIVETREE)/usr/share/VERSION

un_live_tree_boot:
	sudo ./make_live_tree_boot -u $(DEST_LIVETREE)
	sudo tools/fix-fc-cache.pl $(DEST_LIVETREE)

live_tree_boot:
	rm -f $(DEST)/live_tree*.clp
	sudo ./make_live_tree_boot $(DEST_LIVETREE)
	sudo tools/fix-fc-cache.pl $(DEST_LIVETREE)
	$(MAKE) clps

clps:
	$(MAKE) $(DEST)/live_tree_always.clp
	$(MAKE) $(DEST)/live_tree_boot.clp
	$(MAKE) $(DEST)/live_tree_totem.clp
	-$(MAKE) $(DEST)/live_tree_nvidia.clp
	for i in en fr de it es; do $(MAKE) $(DEST)/live_tree_i18n_$$i.clp $(DEST)/live_tree_always_i18n_$$i.clp; done

big_clps:
	$(MAKE) $(DEST)/live_tree.clp


only_iso:
	rm -rf $(DEST)/iso
	mkdir $(DEST)/iso
	cp -a isolinux $(DEST)/iso
	rm -rf $(DEST)/iso/isolinux/CVS

	mv $(DEST)/*.clp $(DEST)/iso

	touch $(DEST)/iso/isolinux/boot.cat
	find $(DEST)/iso/isolinux -type f -printf '%p 100\n' > $(DEST)/iso.sort ; echo '$(DEST)/iso/live_tree_boot.clp 5' >> $(DEST)/iso.sort
#	download version: MOVE10DO
#	complete version: MOVE10IN
	mkisofs -r -J -hide-rr-moved -nobak -cache-inodes -publisher Mandrakesoft -V 'Move' -volset MOVE10IN -b isolinux/isolinux.bin -c isolinux/boot.cat -sort $(DEST)/iso.sort -no-emul-boot -boot-load-size 4 -boot-info-table -o $(ISO) $(DEST)/iso
	mv $(DEST)/iso/*.clp $(DEST)
	mkcd --addmd5 $(ISO)
#	cdrecord -v -eject dev=0,0,0 blank=fast gracetime=2 speed=99 $(ISO)
#	ftp://a:a@leia//BIG/mdkmove.iso


stage1:
	cd $(STAGE1) && ADDITIONAL_DEFS="-DMANDRAKE_MOVE" MOVE=1 make dirs init stage1-full init-move
	cd .. ; ./make_boot_img move

xwait: %: %.c
	$(CC) $(CFLAGS) $< -L/usr/X11R6/$(LIB_NAME) -lX11 -o $@

runlevel_set: %: %.c
	$(CC) $(CFLAGS) $< -o $@

clean:
	rm -f xwait

%.clp: %
	if [ -e $<.sort ]; then \
	sudo mkisofs -R -sort $<.sort $< | create_compressed_fs - 65536 $@ 2000 2>/dev/null ; \
	else \
	sudo mkisofs -R $< | create_compressed_fs - 65536 $@ 2000 2>/dev/null ; \
	fi

check_dirs:
	for i in `cat data/*.dirs`; do grep "^$$i/" data/*.list && echo "$$i"; done ||:

# perl tools/busy-files-accesses --no-link --no-dir --full-dirs 'data/always.dirs data/boot.dirs data/totem.dirs' --already-have data/always.list
