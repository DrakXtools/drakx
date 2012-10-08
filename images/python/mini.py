from drakx.isoimage import IsoImage
from drakx.media import Media

media = []

for m in "main", "contrib", "non-free":
    media.append(Media(m))

includelist = []
for l in ["basesystem_mini", "kernel64", "languages", "firmware_nonfree"]:
    includelist.append("/home/peroyvind/Dokumenter/mandriva/bcd/lists/" + l)
excludelist = []
for e in ["exclude", "exclude_mini", "exclude_ancient", "exclude_tofix", "exclude_nonfree"]:
    excludelist.append("/home/peroyvind/Dokumenter/mandriva/bcd/lists/" + e)

image = IsoImage("test", "2012", "x86_64", media, includelist, excludelist)
