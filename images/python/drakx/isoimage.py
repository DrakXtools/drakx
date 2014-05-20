import os,subprocess
from drakx.common import *

class IsoImage(object):
    def __init__(self, config, distrib, maxsize = 4700):

        destdir = config.tmpdir + "/boot"
        grubdir = destdir + "/grub"
        repopath = config.repopath + "/" + distrib[0].arch

        os.system("rm -rf "+destdir)
        #os.mkdir(config.tmpdir)
        os.mkdir(destdir)
        os.system("ln -s %s/grub/boot/alt* %s/" % (os.path.realpath(config.rootdir), destdir))
        os.symlink("/boot/memtest.bin", destdir+"/memtest")
        os.mkdir(grubdir)
        os.system("ln -s %s/grub/boot/grub/* %s/" % (os.path.realpath(config.rootdir),grubdir))
        for f in ['autorun.inf', 'dosutils']:
            os.symlink("%s/%s" % (repopath, f), "%s/%s" % (os.path.realpath(config.tmpdir), f))

        if len(distrib) > 1:
            arch = "dual"
        else:
            arch = distrib[0].arch
        if config.subversion:
            subversion = "-"+config.subversion.replace(" ","").lower()

        release = "%s-%s%s-%s-%s-%s" % (config.distribution.lower().replace(" ", "-").replace("/","-"), config.version, subversion, config.codename.replace(" ", "-").lower(), arch, config.medium.lower())
        

        pkgs = []
        for dist in distrib:
            pkgs.extend(dist.pkgs)
        pkgs.sort()

        idxfile = open("%s/%s.idx" % (config.tmpdir, release), "w")
        for pkg in pkgs:
            idxfile.write(pkg+"\n")

        idxfile.close()

        iso = "%s/%s.iso" % (config.outdir, release)
        applicationid = "%s - %s %s (%s)" % (config.distribution, config.version, config.subversion, config.product)
        volumesetid = applicationid + " - %s %s" % (arch, config.medium)
        datapreparer = "DrakX"
        volumeid = ("%s-%s-%s-%s" % (config.vendor, config.product, config.version, arch)).upper()
        systemid = config.distribution
        publisher = config.vendor

        cmd = "grub2-mkrescue -o '%s' '%s' -- -f --stdio_sync off -c boot/grub/i386-pc/boot.catalog -input-charset utf-8 -R -r" % (iso, config.tmpdir)
        print cmd
        # cmd prints size in number of sectors of 2048 bytes, so multiply with 2048 to get the number of bytes
        size = int(subprocess.Popen(cmd + " -print-size", shell=True, stdout=subprocess.PIPE, close_fds=True).stdout.readlines()[-1].strip()) * 2048
        print color("Estimated iso size will be %d bytes, %d MB" % (size, size/1000/1000), GREEN)
        if size > (maxsize*1000*1000):
            print color("Size is bigger than maximum size of %dMB" % maxsize, RED, WHITE, BRIGHT)
            raise Exception
        os.system("/usr/bin/time " + cmd)

        print color("Applying metadata to iso image written", GREEN)
        cmd = "xorriso -dev '%s' -boot_image grub patch -boot_image grub bin_path=boot/grub/i386-pc/eltorito.img -boot_image any boot_info_table=on -boot_image any show_status -boot_image grub grub2_boot_info=off -publisher '%s'  -volset_id '%s' -volid '%s' -preparer_id '%s' -system_id '%s' -application_id '%s' -commit" % \
                (iso, publisher, volumesetid, volumeid, datapreparer, systemid, applicationid)
        print cmd
        os.system(cmd)

# vim:ts=4:sw=4:et
