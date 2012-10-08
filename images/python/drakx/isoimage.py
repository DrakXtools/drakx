import os,perl
perl.require("URPM")

class IsoImage(object):
    def __init__(self, name, version, branch, arch, media, includelist, excludelist, repopath = None):
        self.name = name
        self.version = version
        self.branch = branch
        self.arch = arch
        self.media = {}
        for m in media:
            self.media[m.name] = m

        if (repopath):
            self.repopath = repopath
        else:
            self.repopath = "/mnt/BIG/distrib/%s/%s/%s" % (self.branch, self.version, self.arch)

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
        for m in self.media.keys():
            synthesis = self.repopath + "/" + self.media[m].getSynthesis()
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

        os.system("rm -rf ut")
        for m in self.media.keys():
            os.system("mkdir -p ut/media/" + self.media[m].name)

            for pkg in allpkgs:
                if self._shouldExclude(pkg.name()):
                    continue

                source = "%s/media/%s/release/%s.rpm" % (self.repopath, self.media[m].name, pkg.fullname())
                if os.path.exists(source):
                    target = "ut/media/%s/%s.rpm" % (self.media[m].name, pkg.fullname())
                    if not os.path.islink(target):
                        self.media[m].pkgs.append(source)
                        os.symlink(source, target)
                        s = os.stat(source)
                        self.media[m].size += s.st_size

            os.system("genhdlist2 ut/media/" + self.media[m].name)
            for (path, dirs, files) in os.walk("ut/media" + self.media[m].name):
                for f in files:
                    if f.endswith(".rpm"):
                        os.unlink("%s/%s" % (path,f))

        os.mkdir("ut/media/media_info")
        f = open("ut/media/media_info/media.cfg", "w")
        f.write(self.getMediaCfg())
        f.close()

    def _shouldExclude(self, pkgname):
        for exname in self.excludes:
            if len(exname) >= len(pkgname):
                if exname == pkgname[0:len(exname)]:
                    return True
        return False

    def getMediaCfg(self):
        mediaCfg = \
                "[media_info]\n" \
                "version=%s\n" \
                "branch=%s\n" \
                "arch=%s\n" \
                "minor=%d\n" \
                "subversion=%d\n" % (self.version, self.branch, self.arch,1,1)
        # todo: sort keys in a list and iterate over it as keys
        for name in ['main', 'contrib', 'non-free']:
            if name in self.media.keys():
                mediaCfg += self.media[name].getCfgEntry()
        return mediaCfg

    name = None
    version = None
    arch = None
    repopath = None
    media = []
    excludes = []

# vim:ts=4:sw=4:et
