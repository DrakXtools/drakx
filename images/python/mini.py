from drakx.isoimage import IsoImage
from drakx.releaseconfig import ReleaseConfig
from drakx.media import Media
from drakx.distribution import Distribution
import os

config = ReleaseConfig("2012", "OurDiva", "Non-Free", subversion="Alpha 2", medium="CD")
os.system("rm -rf "+config.outdir)

srcdir = "./"
rpmsrate = srcdir + "rpmsrate-mini"
compssusers = srcdir + "compssUsers-mini.pl"
filedeps = srcdir + "file-deps"


media = []
for m in "main", "contrib", "non-free":
    media.append(Media(m))

includelist = []
for l in ["basesystem_mini", "kernel32", "languages", "firmware_nonfree"]:
    includelist.append(srcdir + "lists/" + l)

includelist32 = includelist + [srcdir + "lists/" + "kernel32"]
includelist64 = includelist + [srcdir + "lists/" + "kernel64_mini"]

excludelist = []
for e in ["exclude", "exclude_mini", "exclude_ancient", "exclude_tofix", "exclude_nonfree"]:
    excludelist.append(srcdir + "lists/" + e)

i586 = Distribution(config, "i586", media, includelist32, excludelist, rpmsrate, compssusers, filedeps)
x86_64 = Distribution(config, "x86_64", media, includelist64, excludelist, rpmsrate, compssusers, filedeps)

distrib=[i586,x86_64]

image = IsoImage(config, distrib, maxsize=800)
