from drakx.distribution import Distribution
from drakx.media import Media

media = []

for m in "main", "contrib", "non-free":
    media.append(Media(m))

srcdir = "./"
includelist = []
for l in ["basesystem_mini", "kernel64_mini", "languages", "firmware_nonfree"]:
    includelist.append(srcdir + "lists/" + l)
excludelist = []
for e in ["exclude", "exclude_mini", "exclude_ancient", "exclude_tofix", "exclude_nonfree"]:
    excludelist.append(srcdir + "lists/" + e)

rpmsrate = srcdir + "rpmsrate-mini"
compssusers = srcdir + "compssUsers-mini.pl"
filedeps = srcdir + "file-deps"

version = "2012"
branch = "devel"

arch = "x86_64"
distrib = Distribution(version, branch, arch, media, includelist, excludelist, rpmsrate, compssusers, filedeps, "ut)
