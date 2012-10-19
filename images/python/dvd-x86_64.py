from drakx.distribution import Distribution
from drakx.isoimage import IsoImage
from drakx.media import Media
import os

media = []

for m in "main", "contrib", "non-free":
    media.append(Media(m))

srcdir = "./"
includelist = []
for l in ["basesystem_mini", "input_cat", "theme-free", "kernel64", "languages", "firmware_nonfree", "input_contrib", "input_nonfree"]:
    includelist.append(srcdir + "lists/" + l)
excludelist = []
for e in ["exclude", "exclude_free", "exclude_ancient", "exclude_tofix", "exclude_nonfree", "exclude_contrib64"]:
    excludelist.append(srcdir + "lists/" + e)

rpmsrate = srcdir + "rpmsrate"
compssusers = srcdir + "compssUsers.pl"
filedeps = srcdir + "file-deps"

version = "2012"
branch = "devel"

arch = "x86_64"

outdir="ut"
os.system("rm -rf "+outdir)

x86_64 = Distribution(version, branch, arch, media, includelist, excludelist, rpmsrate, compssusers, filedeps, outdir, suggests = True)
name="moondrake"
distrib=[x86_64]
distribution="mandriva-linux"

image = IsoImage(name, version, arch, x86_64, distribution, branch, outdir)
