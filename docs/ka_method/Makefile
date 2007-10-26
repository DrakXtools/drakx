#--------- HTML TARGET ---------
WWW_PATH=html/

#-------- PDF TARGET --------------
DSL=/usr/share/sgml/docbook/utils-0.6.??/docbook-utils.dsl
#CATALOG=/etc/sgml/xml-docbook-4.1.2.cat
CATALOG=/etc/sgml/catalog

#-------- ALL TARGETS --------------
XSL_FILE=oneduplication.xsl
BASE=doc-duplication
XML_FILE=${BASE}.xml

#----------- ----------------
DSSSL_JADETEX=/usr/share/sgml/docbook/dsssl-stylesheets/print/docbook.dsl
XSL_JADETEX=/usr/share/sgml/docbook/xsl-stylesheets/xhtml/docbook.xsl
JADE=openjade

#------------ MAIN ----------------
all:	clean prepare html_doc

prepare: 
	mkdir -p ${WWW_PATH}
	rm -rf ${WWW_PATH}*.html

clean:
	rm -rf *log
	rm -rf ${BASE}.pdf ${BASE}.tex ${BASE}.fot
	rm -rf *~
	rm -rf *.aux
	rm -rf *.out
	rm -rf *.pdf
pdf_doc:	
	db2pdf -c ${CATALOG} -d ${DSL} ${XML_FILE} 2>&1

html_doc:
	xsltproc ${XSL_FILE} ${XML_FILE}
	mv -f index.html ${WWW_PATH}/duplication.html
	cp -v styleguibo.css ${WWW_PATH}

%.tex:	%.xml $(DSSSL_JADETEX)
	$(JADE) -t tex -d $(DSSSL_JADETEX) -c /usr/share/sgml/openjade/catalog \
	-o $@ /usr/share/sgml/openjade/pubtext/xml.dcl $<

%.pdf %.out %.aux %.log: %.tex
	if [ -e prior.aux ]; then cp -pf prior.aux pprior.aux; fi
	f=$(shell basename $< .tex).aux; if [ -e $$f ]; then cp -pf $$f prior.aux; fi
	-pdfjadetex $< > pdfjadetex.log
	if ! cmp $(shell basename $< .tex).aux prior.aux > /dev/null 2>&1 && \
		! cmp $(shell basename $< .tex).aux pprior.aux > /dev/null 2>&1 && \
		expr $(MAKELEVEL) '<' 4 > /dev/null; then \
		rm -f $@; \
		echo "Found undefined references, compiling again..."; \
	$(MAKE) $@ DSSSL_JADETEX=docbook-jadetex.dsssl; \
	fi
