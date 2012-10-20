from drakx.isoimage import IsoImage
from drakx.releaseconfig import ReleaseConfig
from drakx.media import Media
from drakx.distribution import Distribution
import os

config = ReleaseConfig("2012", "OurDiva", "Non-Free", subversion="Alpha 2", medium="DVD")
os.system("rm -rf "+config.outdir)

srcdir = "./"
rpmsrate = srcdir + "rpmsrate"
compssusers = srcdir + "compssUsers.pl"
filedeps = srcdir + "file-deps"

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

x86_64 = Distribution(config, "x86_64", media, includelist, excludelist, rpmsrate, compssusers, filedeps, suggests = True)
distrib=[x86_64]

image = IsoImage(config, distrib, maxsize=4700)
