class ReleaseConfig(object):
    def __init__(self, version, codename, product, subversion = None, outdir="out", branch = "devel", repopath = None, medium = "DVD", vendor = "Moondrake", distribution = "Moondrake GNU/Linux"):
        self.version = version
        self.codename = codename
        if len(product) > 32:
            print "length of product name '%s' (%d) > 32" % (product, len(product))
            exit 1
        self.product = product
        self.subversion = subversion
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
