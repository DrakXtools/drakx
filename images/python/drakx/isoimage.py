import shutil,os,perl
perl.require("URPM")

class IsoImage(object):
    def __init__(self, name, version, branch, arch, media, includelist, excludelist, rpmsrate, compssusers, filedeps, repopath = None, distribution = "mandriva-linux"):
        self.distribution = distribution
        self.name = name
        self.version = version
        self.branch = branch
        self.arch = arch
        self.media = {}
        for m in media:
            self.media[m.name] = m

        self.rpmsrate = rpmsrate
        self.compssusers = compssusers
        self.filedeps = filedeps
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
                print "skipping1: " + key
                continue
            cand_pkgs_filtered[key] = cand_pkgs[key]

        allpkgs = urpm.resolve_requested__no_suggests_(db, None, cand_pkgs_filtered, __wantarray__ = 1)

        os.system("rm -rf ut")
        for m in self.media.keys():
            os.system("mkdir -p ut/media/" + self.media[m].name)

            pkgs = []
            for pkg in allpkgs:
                if self._shouldExclude(pkg.name()):
                    print "skipping2: " + pkg.name()
                    continue

                source = "%s/media/%s/release/%s.rpm" % (self.repopath, self.media[m].name, pkg.fullname())
                if os.path.exists(source):
                    target = "ut/media/%s/%s.rpm" % (self.media[m].name, pkg.fullname())
                    if not os.path.islink(target):
                        pkgs.append(source)
                        os.symlink(source, target)
                        s = os.stat(source)
                        self.media[m].size += s.st_size
            self.media[m].pkgs = pkgs
            os.system("genhdlist2 ut/media/" + self.media[m].name)

        os.mkdir("ut/media/media_info")
        f = open("ut/media/media_info/media.cfg", "w")
        f.write(self.getMediaCfg())
        f.close()

        # TODO: reimplement clean-rpmsrate in python(?)
        os.system("clean-rpmsrate %s -o ut/media/media_info/rpmsrate" % self.rpmsrate)
        # something is broken somewhere..?
        if not os.path.exists("ut/media/media_info/rpmsrate"):
            shutil.copy(self.rpmsrate, "ut/media/media_info/rpmsrate")
        shutil.copy(self.compssusers, "ut/media/media_info/compssUsers.pl")
        shutil.copy(self.filedeps, "ut/media/media_info/file-deps")
        os.system("cd ut/media/media_info/; md5sum * > MD5SUM")

        for (path, dirs, files) in os.walk("ut/media"):
            for f in files:
                if f.endswith(".rpm"):
                    os.unlink("%s/%s" % (path,f))

        filemap = "-map ut/media /%s/media " \
                "-map ../mdkinst.cpio.xz /%s/install/stage2/mdkinst.cpio.xz " \
                "-map ../VERSION /%s/install/stage2/VERSION " % \
                (self.arch, self.arch, self.arch)

        for m in self.media.keys():
            for f in self.media[m].pkgs:
                if os.path.exists(f):
                    filemap += "-map %s /%s/media/%s/%s " % (f, self.arch, m, os.path.basename(f))

        iso = "%s-%s-%s.%s.iso" % (self.distribution, self.version, self.name, self.arch)
        os.system("cp -f ../images/boot.iso " + iso)

        cmd = "xorriso -dev %s " \
	    "%s" \
    	"-boot_image grub patch " \
	    "-boot_image grub bin_path=boot/grub/i386-pc/eltorito.img "\
	    "-boot_image any boot_info_table=on "\
	    "-boot_image any show_status "\
	    "-commit"\
	    "" % (iso, filemap)
        os.system(cmd)

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
                "arch=%s\n" % (self.version, self.branch, self.arch)
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
