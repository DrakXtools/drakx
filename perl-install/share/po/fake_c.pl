#!/usr/bin/perl -lp

s|_\(\[(.*),\s*(.*),\s*(.*)\]| ngettext($2,$3,$1)|; # special plural form handling

s|^(__?\()| $1|;		# add a blank at the beginning (?!)
s,\Qs/#.*//,,;			# ugly special case
s|//|/""/|g;			# ensure // or not understood as comments

s,(^|[^\$])#([^+].*),\1/*\2*/,; # rewrite comments to C format except for:
                                # - ``#+ xxx'' comments which are kept
                                # - ``$#xxx'' which are not comments

s|$|\\n\\|;			# multi-line strings not handled in C

