
DEST_LIVETREE = /tmp/live_tree
DEST_STAGE2 = $(DEST_LIVETREE)/usr/bin/stage2

ISO = /BIG/mdkmove.iso

DATA_FILES = devices symlinks directories-to-create etcfiles all-etcfiles keyfiles README.adding.more.files
LANG_FILES = $(shell perl -ne 'print $$1 if /ALLOWED_LANGS = qw\((.*)\)/' move.pm)

STAGE1 = ../mdk-stage1
INSTALL = ../perl-install

INSTALL_FILES = install2.pm install_steps.pm install_any.pm install_interactive.pm install_steps_gtk.pm install_steps_interactive.pm install_messages.pm install_gtk.pm help.pm

ARCH := $(shell arch | egrep "(x86_64|sparc64|s390x)")
ifneq ("x$(ARCH)", "x")
LIB_NAME = lib64
else
LIB_NAME = lib
endif

.PHONY: iso 

all: install

build: xwait
	cd $(STAGE1) && ADDITIONAL_DEFS="-DMANDRAKE_MOVE" MOVE=1 make init stage1-network stage1-cdrom init-move
	sudo ./collect-directories-to-create.pl $(DEST_LIVETREE) > data/directories-to-create
	sudo find $(DEST_LIVETREE)/etc -type f | perl -pe 's|$(DEST_LIVETREE)||' > data/all-etcfiles

install: build
	 #- todo: make_boot_img alike to create boot volume from ../mdk-stage1/stage1-cdrom (isolinux mandatory since stock kernel is so big)
	sudo cp -f $(STAGE1)/init-move $(DEST_LIVETREE)/sbin/init

	sudo cp -f xwait $(DEST_LIVETREE)/usr/bin
	sudo cp -f runstage2 $(DEST_LIVETREE)/usr/bin/runstage2.pl
	sudo rm -rf $(DEST_STAGE2)
	sudo mkdir -p $(DEST_STAGE2)
	sudo cp -f *.pm $(DEST_STAGE2)
	sudo cp -f $(addprefix $(INSTALL)/, $(INSTALL_FILES)) $(DEST_STAGE2)

	sudo rm -rf $(DEST_LIVETREE)/usr/share/langs
	sudo mkdir -p $(DEST_LIVETREE)/usr/share/langs
	sudo cp -f $(patsubst %, $(INSTALL)/pixmaps/langs/lang-%.png, $(LANG_FILES)) $(DEST_LIVETREE)/usr/share/langs

	 #- overwrite /usr/lib/libDrakX files of the live tree with those in CVS
	(cd $(DEST_LIVETREE)/usr/lib/libDrakX ; find -name "*.pm") | egrep -v 'ctxhelp|drakfirsttime|network.pm' | (cd $(INSTALL) ; sudo cpio -pLumd $(DEST_LIVETREE)/usr/lib/libDrakX/)

	 #- overwrite stuff.so of drakxtools because it doesn't contain C_DRAKX stuff
	sudo cp -f ../perl-install/c/blib/arch/auto/stuff/stuff.so $(DEST_LIVETREE)/usr/lib/libDrakX/auto/c/stuff

	 #- duplicated :(
	sudo perl -pi -e 's/#[-+].*//; $$_ = "\n" if (/^=(head|begin)/ .. /^=cut/) || /use (diagnostics|vars|strict)/' $(DEST_STAGE2)/*.pm `find $(DEST_LIVETREE)/usr/lib/libDrakX -name "*.pm"`

	sudo mkdir -p $(DEST_LIVETREE)/move
	sudo cp -f $(addprefix data/, $(DATA_FILES)) $(DEST_LIVETREE)/move

	sudo install -m 440 tree/sudoers $(DEST_LIVETREE)/etc
	sudo install -m 644 tree/mdk_move_boot_loop.desktop $(DEST_LIVETREE)/usr/share/autostart
	sudo install tree/{mdk_move_loop,mdk_totem,mdk_behind_totem} $(DEST_LIVETREE)/usr/bin
	sudo install -m 644 -D tree/mdk_totem.desktop $(DEST_LIVETREE)/etc/skel/Desktop/mdk_totem.desktop
	sudo install -m 644 tree/kdedrc $(DEST_LIVETREE)/usr/share/config

	grep ChangeLog $(INSTALL)/CVS/Entries > /tmp/version
	sudo cp -f /tmp/version $(DEST_LIVETREE)/usr/share/VERSION

live_tree_boot:
	rm -f /tmp/live_tree*.clp
	./make_live_tree_boot
	$(MAKE) /tmp/live_tree_always.clp
	$(MAKE) /tmp/live_tree_boot.clp
	$(MAKE) /tmp/live_tree_totem.clp
	$(MAKE) $(patsubst %, /tmp/live_tree_always_i18n_%.clp, $(LANG_FILES))

un_live_tree_boot:
	./make_live_tree_boot -u

iso: un_live_tree_boot install live_tree_boot
	rm -rf /tmp/iso /tmp/live_tree.clp
	mkdir /tmp/iso
	cp -a isolinux /tmp/iso
	$(MAKE) /tmp/live_tree.clp
	mv /tmp/*.clp /tmp/iso

	touch /tmp/iso/isolinux/boot.cat
	find /tmp/iso/isolinux -type f -printf '%p 100\n' > r.sort ; echo '/tmp/iso/live_tree_boot.clp 5' >> r.sort
	mkisofs -r -J -hide-rr-moved -nobak -cache-inodes -V 'Mandrake Move' -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o $(ISO) /tmp/iso
	mv /tmp/iso/*.clp /tmp
#	cdrecord -v -eject dev=0,0,0 blank=fast gracetime=2 speed=99 $(ISO)
#	ftp://a:a@leia//BIG/mdkmove.iso

xwait: %: %.c
	$(CC) $(CFLAGS) $< -L/usr/X11R6/$(LIB_NAME) -lX11 -o $@

clean:
	rm -f xwait

%.clp: %
	if [ -e $<.sort ]; then \
	mkisofs -R -sort $<.sort $< | create_compressed_fs - 65536 $@ 2000 2>/dev/null ; \
	else \
	mkisofs -R $< | create_compressed_fs - 65536 $@ 2000 2>/dev/null ; \
	fi

check_dirs:
	for i in `cat data/*.dirs`; do grep /tmp/live_tree$$i/ data/*.list; done ||:

# perl tools/busy-files-accesses --no-link --no-dir --full-dirs 'data/always.dirs data/boot.dirs data/totem.dirs' --already-have data/always.list
