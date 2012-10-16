from drakx.media import Media
from drakx.distribution import Distribution

media = []

for m in "main", "contrib", "non-free":
    media.append(Media(m))

srcdir = "./"
includelist = []
for l in ["basesystem_mini", "kernel32", "languages", "firmware_nonfree"]:
    includelist.append(srcdir + "lists/" + l)
excludelist = []
for e in ["exclude", "exclude_mini", "exclude_ancient", "exclude_tofix", "exclude_nonfree"]:
    excludelist.append(srcdir + "lists/" + e)

rpmsrate = srcdir + "rpmsrate-mini"
compssusers = srcdir + "compssUsers-mini.pl"
filedeps = srcdir + "file-deps"

version = "2012"
branch = "devel"

arch = "i586"
distrib = Distribution(version, branch, arch, media, includelist, excludelist, rpmsrate, compssusers, filedeps, "ut")
