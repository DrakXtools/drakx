#
#
#        Project   : Projet  Libre
#        file      : pki.tex
#             Date : Thu Jun 21 19:26:19 CEST 2001
#   (o-       Id   : DUPONT Sebastien
#   /\        mail : <dupont_s@epita.fr>
#  Y_/___________________________________________
#

RM 	= 	@rm -f

CD	=	@cd

ECHO	=	@echo

PRINTF	=	@echo -n

FILE	=	drakfont

DVI	= 	@dvips -j0 -Pcmz -Pamz -o

PS	=	@ps2pdf

LATEX	=	@latex

normal	:
	$(ECHO) '[35m/*--LATEX--*/[0m'
	$(LATEX) $(FILE).tex

all	: 
	$(ECHO) '/*----------latex -> dvi -> ps -> pdf------------'
	$(ECHO) '[35m/*--LATEX--*/[0m'
	$(LATEX) $(FILE).tex
	$(ECHO) '[35m/*--DVI -> PS--*/[0m'
	$(DVI) $(FILE).ps $(FILE).dvi
	$(ECHO) '[35m/*--PS -> PDF--*/[0m'
	$(PS) $(FILE).ps
	$(ECHO) '[35m/*--That s all--*/[0m'


ps	: normal
	$(ECHO) '[35m/*--DVI -> PS--*/[0m'
	$(DVI) $(FILE).ps $(FILE).dvi
	$(ECHO) '[35m/*--That s all--*/[0m'

pdf	: ps
	$(ECHO) '[35m/*--PS -> PDF--*/[0m'
	$(PS) $(FILE).ps
	$(ECHO) '[35m/*--That s all--*/[0m'

clean	:
	$(RM) $(FILE).toc $(FILE).log $(FILE).aux *~

fclean	:
	make clean
	$(RM) $(FILE).ps $(FILE).pdf  $(FILE).dvi  
