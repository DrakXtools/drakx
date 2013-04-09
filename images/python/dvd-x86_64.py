from drakx.isoimage import IsoImage
from drakx.releaseconfig import ReleaseConfig
from drakx.media import Media
from drakx.distribution import Distribution
import os

config = ReleaseConfig("2013", "Twelve Angry Penguins", "Non-Free", subversion="Beta", medium="DVD", outdir="/mnt/BIG/distrib/iso")

srcdir = "./"
rpmsrate = "../../perl-install/install/share/meta-task/rpmsrate-raw"
compssusers = "../../perl-install/install/share/meta-task/compssUsers.pl"
filedeps = srcdir + "file-deps"

media = []
for m in "moondrake", "main", "contrib", "non-free", "restricted", 'main.old', 'contrib.old', 'non-free.old':
    media.append(Media(m))

srcdir = "./"
includelist = []
for l in ["basesystem_mini", "input_cat", "theme-moondrake", "kernel64", "languages", "firmware_nonfree", "input_contrib", "input_nonfree", "dvd_pwp64"]:
    includelist.append(srcdir + "lists/" + l)
excludelist = []
for e in ["exclude", "exclude_free", "exclude_ancient", "exclude_tofix", "exclude_nonfree", "exclude_contrib64"]:
    excludelist.append(srcdir + "lists/" + e)

x86_64 = Distribution(config, "x86_64", media, includelist, excludelist, rpmsrate, compssusers, filedeps, suggests = True)
distrib=[x86_64]

image = IsoImage(config, distrib, maxsize=4700)
