from os import system
class ReleaseConfig(object):
    def __init__(self, version, codename, product, subversion = None, tmpdir="/tmp/drakx-iso-out", outdir="out", branch = "devel", repopath = None, medium = "DVD", vendor = "Moondrake", distribution = "Moondrake GNU/Linux"):
        self.version = version
        self.codename = codename
        self.product = product
        self.subversion = subversion
        self.medium = medium
        self.vendor = vendor
        self.distribution = distribution
        self.outdir = outdir
        self.tmpdir = tmpdir
        system("rm -rf " + tmpdir + "/*")
        self.branch = branch
        if (not repopath):
            self.repopath += "%s/%s" % (branch, version)
        else:
            self.repopath = repopath

    repopath = "/mnt/BIG/distrib/"

# vim:ts=4:sw=4:et
