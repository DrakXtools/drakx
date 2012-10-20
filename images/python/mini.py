from drakx.isoimage import IsoImage
import os

outdir="ut"
os.system("rm -rf "+outdir)
from mini32 import distrib as i586
from mini64 import distrib as x86_64

name="moondrake"
version="2012"
arch="dual"
distrib=[i586,x86_64]
branch="devel"
distribution="moondrake-linux"

image = IsoImage(name, version, arch, distrib, branch, distribution, outdir, maxsize=800)
