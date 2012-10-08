import os,perl
perl.require("URPM")

class IsoImage(object):
    def __init__(self, name, version, arch, media, includelist, excludelist, repopath = None):
        self.name = name
        self.version = version
        self.arch = arch
        self.media = media
        if (repopath):
            self.repopath = repopath

        includes = []
        for pkglf in includelist:
            f = open(pkglf)
            for line in f.readlines():
                line = line.strip()
                if line and line[0] != '#':
                    includes.append(line)
            f.close()
        for exclf in excludelist:
            f = open(exclf)
            for line in f.readlines():
                line = line.strip()
                if line and line[0] != '#':
                    self.excludes.append(line)
            f.close()

        db = perl.call("URPM::DB::open", "/tmp/rpmdb", 0)

        urpm = perl.callm("new", "URPM");
        for media in self.media:
            synthesis = "%s/%s/%s/%s" % (self.repopath, self.version, self.arch, media.getSynthesis())
            urpm.parse_synthesis(synthesis) 

        pattern = ""
        for pkg in includes:
            if pattern:
                pattern += "|"
            pattern += pkg

        cand_pkgs = urpm.find_candidate_packages(pattern)
        cand_pkgs_filtered = {}
        for key in cand_pkgs.keys():
            if self._shouldExclude(key):
                continue
            cand_pkgs_filtered[key] = cand_pkgs[key]

        allpkgs = urpm.resolve_requested__no_suggests_(db, None, cand_pkgs_filtered, __wantarray__ = 1)

        pkgs = {}
        os.system("rm -rf ut")
        for media in self.media:
            pkgs[media.name] = []
            os.system("mkdir -p ut/media/" + media.name)

            for pkg in allpkgs:
                if self._shouldExclude(pkg.name()):
                    continue

                source = "%s/%s/%s/media/%s/release/%s.rpm" % (self.repopath, self.version, self.arch, media.name, pkg.fullname())
                if os.path.exists(source):
                    target = "ut/media/%s/%s.rpm" % (media.name, pkg.fullname())
                    if not os.path.islink(target):
                        pkgs[media.name].append(source)
                        os.symlink(source, target)

            for pkg in pkgs[media.name]:
                media.pkgs.append(pkg)

            os.system("genhdlist2 ut/media/" + media.name)
            for (path, dirs, files) in os.walk("ut/media" + media.name):
                for f in files:
                    if f.endswith(".rpm"):
                        os.unlink("%s/%s" % (path,f))

    def _shouldExclude(self, pkgname):
        for exname in self.excludes:
            if len(exname) >= len(pkgname):
                if exname == pkgname[0:len(exname)]:
                    return True
        return False

    name = None
    version = None
    arch = None
    repopath = "/mnt/BIG/distrib/devel"
    media = []
    excludes = []

# vim:ts=4:sw=4:et
