NAME=libDrakX
FNAME=$(NAME)/drakxtools_http
PREFIX=
DATADIR=$(PREFIX)/usr/share

all: index.html

index.html: index.html.pl
	perl $^ > $@

install:	
	install -D miniserv.init $(PREFIX)/etc/init.d/drakxtools_http
	install -D -m 644 authorised_progs $(PREFIX)/etc/drakxtools_http/authorised_progs
	install -D -m 644 miniserv.conf $(PREFIX)/etc/drakxtools_http/conf
	install -D -m 644 miniserv.pam $(PREFIX)/etc/pam.d/miniserv
	install -D -m 644 miniserv.logrotate $(PREFIX)/etc/logrotate.d/drakxtools-http

	install -d $(DATADIR)/$(FNAME)/www
	install -m 644 miniserv.pl miniserv.pem miniserv.users $(DATADIR)/$(FNAME)
	install -m 644 index.html $(DATADIR)/$(FNAME)/www
	install interactive_http.cgi $(DATADIR)/$(FNAME)/www
