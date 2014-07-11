from drakx.isoimage import IsoImage
from drakx.releaseconfig import ReleaseConfig
from drakx.media import Media
from drakx.distribution import Distribution
import os

config = ReleaseConfig("2014.5", "Sporadic Erratic", "Non-Free", subversion="Beta", medium="DVD", outdir="/home/peroyvind/isos")

srcdir = "./"
rpmsrate = "/usr/share/meta-task/rpmsrate-raw"
compssusers = "/usr/share/meta-task/compssUsers.pl"
filedeps = srcdir + "file-deps"

media = []
for m in "moondrake", "main", "contrib", "non-free", "restricted":
    media.append(Media(m))

srcdir = "./"
includelist = []
for l in ["basesystem_mini", "input_cat", "theme-moondrake", "kernel64", "languages", "firmware_nonfree", "input_main", "input_contrib", "input_nonfree", "dvd_pwp64"]:
    includelist.append(srcdir + "lists/" + l)
excludelist = []
for e in ["exclude", "exclude_free", "exclude_ancient", "exclude_tofix", "exclude_nonfree", "exclude_contrib64", "exclude_broken"]:
    excludelist.append(srcdir + "lists/" + e)

x86_64 = Distribution(config, "x86_64", media, includelist, excludelist, rpmsrate, compssusers, filedeps, suggests = True)#, gpgName="26752624")
distrib=[x86_64]

image = IsoImage(config, distrib, maxsize=4700)
