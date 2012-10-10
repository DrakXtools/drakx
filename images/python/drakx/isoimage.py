import shutil,os,perl,string
perl.require("URPM")
perl.require("urpm")
perl.require("urpm::select")

class IsoImage(object):
    def __init__(self, name, version, arch, distrib, distribution = "mandriva-linux", outdir = "ut"):

        destdir = outdir + "/boot"
        grubdir = destdir + "/grub"
        self.distribution = distribution
        self.name = name
        self.version = version
        self.arch = arch
        self.distrib = distrib

        os.system("rm -rf "+destdir)
        os.mkdir(destdir)
        os.system("ln -sr ../grub/boot/{all.rdz,alt*,memtest} %s/" % destdir)
        os.mkdir(grubdir)
        os.system("ln -sr ../grub/boot/grub/* %s/" % grubdir)

        iso = "%s-%s-%s.%s.iso" % (self.distribution, self.version, self.name, self.arch)

        os.system("/usr/bin/time grub2-mkrescue -o %s -f --stdio_sync off  -c boot/grub/i386-pc/boot.catalog -R -r %s" % (iso, outdir))


# vim:ts=4:sw=4:et
