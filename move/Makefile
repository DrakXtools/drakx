
DEST_LIVETREE = /tmp/live_tree
DEST_STAGE2 = $(DEST_LIVETREE)/usr/bin/stage2

DATA_FILES = devices symlinks

STAGE1 = ../mdk-stage1
INSTALL = ../perl-install

INSTALL_FILES = install2.pm install_steps.pm install_any.pm install_interactive.pm install_steps_gtk.pm install_steps_interactive.pm install_messages.pm install_gtk.pm help.pm

all: install

build:
	cd $(STAGE1) && ADDITIONAL_DEFS="-DMANDRAKE_MOVE" make init stage1-network stage1-cdrom init-move

install: build
	 #- todo: make_boot_img alike to create boot volume from ../mdk-stage1/stage1-cdrom (isolinux mandatory since stock kernel is so big)
	sudo cp -f $(STAGE1)/init-move $(DEST_LIVETREE)/sbin/init

	sudo cp -f runstage2 $(DEST_LIVETREE)/usr/bin
	sudo rm -rf $(DEST_STAGE2)
	sudo mkdir -p $(DEST_STAGE2)
	sudo cp -f *.pm $(DEST_STAGE2)
	sudo cp -f $(addprefix $(INSTALL)/, $(INSTALL_FILES)) $(DEST_STAGE2)

	 #- overwrite /usr/lib/libDrakX files of the live tree with those in CVS
	sudo cp -f $(addprefix $(INSTALL)/, $(patsubst /usr/lib/libDrakX/%.pm, %.pm, $(shell ls /usr/lib/libDrakX/*.pm))) $(DEST_LIVETREE)/usr/lib/libDrakX || :

	 #- overwrite stuff.so of drakxtools because it doesn't contain C_DRAKX stuff
	sudo cp -f ../perl-install/c/blib/arch/auto/stuff/stuff.so `find $(DEST_LIVETREE)/usr/lib* | grep stuff/stuff.so`

	 #- duplicated :(
	sudo perl -pi -e 's/#[-+].*//; $$_ = "\n" if (/^=(head|begin)/ .. /^=cut/) || /use (diagnostics|vars|strict)/' $(DEST_STAGE2)/*.pm $(DEST_LIVETREE)/usr/lib/libDrakX/*.pm

	sudo mkdir -p $(DEST_LIVETREE)/move
	sudo cp -f $(addprefix data/, $(DATA_FILES)) $(DEST_LIVETREE)/move

	grep ChangeLog $(INSTALL)/CVS/Entries > /tmp/version
	sudo cp -f /tmp/version $(DEST_LIVETREE)/usr/share/VERSION
