import os,subprocess
from drakx.common import *

class IsoImage(object):
    def __init__(self, name, version, arch, distrib, branch, distribution = "mandriva-linux", outdir = "ut", repopath = None, maxsize = 4700):

        destdir = outdir + "/boot"
        grubdir = destdir + "/grub"
        self.distribution = distribution
        self.name = name
        self.version = version
        self.arch = arch
        self.distrib = distrib
        if (not repopath):
            repopath = "/mnt/BIG/distrib/%s/%s/i586" % (branch, version)


        os.system("rm -rf "+destdir)
        os.mkdir(destdir)
        os.system("ln -sr ../grub/boot/{all.rdz,alt*} %s/" % destdir)
        os.symlink("/boot/memtest.bin", destdir+"/memtest")
        os.mkdir(grubdir)
        os.system("ln -sr ../grub/boot/grub/* %s/" % grubdir)
        for f in ['autorun.inf', 'dosutils']:
            os.symlink("%s/%s" % (repopath, f), "%s/%s" % (outdir, f))

        release = "%s-%s-%s.%s" % (self.distribution, self.version, self.name, self.arch)

        pkgs = []
        for dist in distrib:
            pkgs.extend(dist.pkgs)
        pkgs.sort()

        idxfile = open("%s/%s.idx" % (outdir, release), "w")
        for pkg in pkgs:
            idxfile.write(pkg+"\n")

        idxfile.close()


        iso = release+".iso"

        cmd = "grub2-mkrescue -o %s -f --stdio_sync off  -c boot/grub/i386-pc/boot.catalog -input-charset utf-8 -R -r %s" % (iso, outdir)
        # cmd prints size in number of sectors of 2048 bytes, so multiply with 2048 to get the number of bytes
        size = int(subprocess.Popen(cmd + " -print-size", shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, close_fds=True).stdout.readlines()[-1].strip()) * 2048
        print color("Estimated iso size will be %d bytes, %d MB" % (size, size/1000/1000), GREEN)
        if size > (maxsize*1000*1000):
            print color("Size is bigger than maximum size of %dMB" % maxsize, RED, WHITE, BRIGHT)
            raise Exception
        os.system("/usr/bin/time " + cmd)


# vim:ts=4:sw=4:et
