help:
	@if [ ! -d doc ]; then \
		echo "Checking out doc stuff now ..."; \
		cvs -d :ext:cvs.mandriva.com:/cooker co doc/manualB/{entities,manuals,modules}; \
	else \
		echo "Updating doc stuff now ..."; \
		cd doc ; cvs update manualB/{entities,manuals,modules}; \
	fi
	./help_xml2pm.pl
