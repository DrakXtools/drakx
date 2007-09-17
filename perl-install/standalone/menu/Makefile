mcc_dir = $(PREFIX)/usr/share/applications

DIRECTORY_IN := $(wildcard *.directory.in)
DIRECTORY = $(DIRECTORY_IN:.directory.in=.directory)

DESKTOP_IN := $(wildcard *.desktop.in)
DESKTOP = $(DESKTOP_IN:.desktop.in=.desktop)

all: $(DIRECTORY) $(DESKTOP)

clean:
	rm -f $(DIRECTORY) $(DESKTOP)

install: all
	install -d $(mcc_dir)/desktop
	install -m644 $(DESKTOP) $(DIRECTORY) $(mcc_dir)/desktop
	install -d $(PREFIX)/etc/gnome-vfs-2.0/vfolders

%.desktop:   %.desktop.in
	intltool-merge --utf8 ../po $< $@ -d -u -c ../po/.intltool-merge-cache
%.directory: %.directory.in
	intltool-merge --utf8 ../po $< $@ -d -u -c ../po/.intltool-merge-cache

