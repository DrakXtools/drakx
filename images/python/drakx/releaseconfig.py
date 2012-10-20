class ReleaseConfig(object):
    def __init__(self, version, codename, flavour, subversion = None, outdir="out", branch = "devel", repopath = None, medium = "DVD", vendor = "Moondrake", distribution = "Moondrake GNU/Linux"):
        self.version = version
        self.codename = codename
        self.subversion = subversion
        self.flavour = flavour
        self.medium = medium
        self.vendor = vendor
        self.distribution = distribution
        self.outdir = outdir
        self.branch = branch
        if (not repopath):
            self.repopath += "%s/%s" % (branch, version)
        else:
            self.repopath = repopath

    repopath = "/mnt/BIG/distrib/"

# vim:ts=4:sw=4:et
