import shutil,os,perl,string,fnmatch,re
from drakx.common import *
perl.require("URPM")
perl.require("urpm")
perl.require("urpm::select")

class Distribution(object):
    def __init__(self, config, arch, media, includelist, excludelist, rpmsrate, compssusers, filedeps, suggests = False, synthfilter = ".cz:gzip -9"):

        self.arch = arch
        self.media = {}
        for m in media:
            self.media[m.name] = m

        outdir = config.outdir+"/"+arch
        repopath = config.repopath+"/"+self.arch

        print color("Parsing lists of packages to include", GREEN)
        includes = []
        for pkglf in includelist:
            f = open(pkglf)
            for line in f.readlines():
                line = line.strip()
                if not line or line[0] == "#":
                    continue
                if line.startswith("CAT_"):
                    category, weight = line.split()
                    pkgs = self.get_list_from_CAT(rpmsrate, category, weight)
                    includes.extend(pkgs)
                else:
                    includes.append(line)
            f.close()

        print color("Parsing lists of packages to exclude", GREEN)
        excludepattern = ""
        excludes = []
        for exclf in excludelist:
            f = open(exclf)
            for line in f.readlines():
                line = line.strip()
                if line and line[0] != '#':
                    excludes.append(line)
                    if excludepattern:
                        excludepattern += '|'
                    if line[0] == '^' or line[-1] == '$':
                        excludepattern += line
                    else:
                        excludepattern += fnmatch.translate(line).replace("\\Z","")
            f.close()
        excludere = re.compile(excludepattern)

        empty_db = perl.callm("new", "URPM")
        urpm = perl.eval("""my $urpm = new URPM;
                $urpm->{error} = sub { printf "urpm error: %s\n", $_[0] };
                $urpm""");
        for m in self.media.keys():
            synthesis = repopath + "/" + self.media[m].getSynthesis()
            print color("Parsing synthesis for %s: %s" % (m, synthesis), GREEN)
            urpm.parse_synthesis(synthesis) 

        requested = perl.get_ref("%")

        perlexc = perl.eval("@excludes = ();")
        perlexc = perl.get_ref("@excludes")
        perlexc.extend(excludes)

        stop_on_choices = perl.eval("""$stop_on_choices = sub {
        my ($urpm, undef, $state_, $choices, $virtual_pkg_name, $preferred) = @_;

        my $dep;
        foreach my $pkg (@$choices) {
            if (grep { $_ eq $pkg->name() } @excludes) {
                next;
            }
            if (!$dep) {
                $dep = $pkg;
            } elsif (!$dep->compare_pkg($pkg)) {
                $dep = $pkg;
            }
        }

        $state_->{selected}{$dep->id} = 1;
        }""")

        def search_pkgs(deps):
            perl.call("urpm::select::search_packages", urpm, requested, deps, use_provides=1)

            state = perl.get_ref("%")

            urpm.resolve_requested(empty_db, state, requested, 
                    no_suggests = not suggests,
                    callback_choices = stop_on_choices, nodeps = 1)

            allpkgs = []
            for pid in state['selected'].keys():
                pids = pid.split('|')
            
                dep = None
                for pid in pids:
                    pid = int(pid)
                    pkg = urpm['depslist'][pid]
                    if excludere.match(pkg.name()):
                        #print "skipping1: %s" % pkg.fullname()
                        continue
                    pkg = urpm['depslist'][pid]

                    if not dep:
                        dep = pkg
                    else:
                        True
                if dep is None:
                    #print "ouch!"
                    continue
                else:
                    allpkgs.append(dep)
            return allpkgs

        print color("Resolving packages", GREEN)
        allpkgs = search_pkgs(includes)
        # lame, having difficulties figuring out how to properly recursively
        # resolve dependencies (potentially a bug in urpmi?), so just do it manually for now..
        includes = []
        for p in allpkgs:
            includes.append(p.name())
        allpkgs = search_pkgs(includes)

        print color("Initiating distribution tree", GREEN)
        smartopts = "channel -o sync-urpmi-medialist=no --data-dir smartdata"
        os.system("rm -rf " + outdir)
        os.system("rm -rf smartdata")
        os.mkdir("smartdata")
        os.system("mkdir -p %s/media/media_info/" % outdir) 
        shutil.copy(compssusers, "%s/media/media_info/compssUsers.pl" % outdir)
        shutil.copy(filedeps, "%s/media/media_info/file-deps" % outdir)
        rootfiles = ['COPYING', 'index.htm', 'install.htm', 'INSTALL.txt', 'LICENSE-APPS.txt', 'LICENSE.txt',
                'product.id', 'README.txt', 'release-notes.html', 'release-notes.txt', 'VERSION', 'doc', 'misc']
        for f in rootfiles:
            os.symlink("%s/%s" % (repopath, f), "%s/%s" % (outdir, f))

        for m in self.media.keys():
            print color("Generating media tree and metadata for " + m, GREEN)
            os.system("mkdir -p %s/media/%s" % (outdir, self.media[m].name))

            pkgs = []
            for pkg in allpkgs:
                if excludere.match(pkg.name()):
                    #print "skipping2: " + pkg.name()
                    continue

                source = "%s/media/%s/release/%s.rpm" % (repopath, self.media[m].name, pkg.fullname())
                if os.path.exists(source):
                    target = "%s/media/%s/%s.rpm" % (outdir, self.media[m].name, pkg.fullname())
                    if not os.path.islink(target):
                        pkgs.append(source)
                        os.symlink(source, target)
                        s = os.stat(source)
                        self.media[m].size += s.st_size
            self.media[m].pkgs = pkgs
            os.system("genhdlist2 --file-deps %s/media/media_info/file-deps --synthesis-filter '%s' %s/media/%s" % (outdir, synthfilter, outdir, self.media[m].name))
            ext = synthfilter.split(":")[0]
            # workaround for urpmi spaghetti code which hardcodes .cz
            if ext != ".cz":
                os.symlink("synthesis.hdlist%s" % ext, "%s/media/%s/media_info/synthesis.hdlist.cz" % (outdir, self.media[m].name))

            os.unlink("%s/media/%s/media_info/hdlist.cz" % (outdir, self.media[m].name))
            smartopts = "-o sync-urpmi-medialist=no --data-dir %s/smartdata" % os.getenv("PWD")
            os.system("smart channel --yes %s --add %s type=urpmi baseurl=%s/%s/media/%s/ hdlurl=media_info/synthesis.hdlist%s" %
                    (smartopts, m, os.getenv("PWD"), outdir, m, ext))

        print color("Writing %s/media/media_info/media.cfg" % outdir, GREEN)
        if not os.path.exists("%s/media/media_info" % outdir):
            os.mkdir("%s/media/media_info" % outdir)
        f = open("%s/media/media_info/media.cfg" % outdir, "w")
        f.write(self.getMediaCfg(config))
        f.close()

        print color("Checking packages", GREEN)
        medias = ""
        rpmdirs = []
        for m in self.media.keys():
            rpmdirs.append("%s/media/%s" % (outdir, m))
            if medias:
                medias += ","
            medias += m
        os.system("smart update %s" % smartopts)
        os.system("smart check %s --channels=%s" % (smartopts, medias))
        os.system("sleep 5");

        print color("Generating %s/media/media_info/rpmsrate" % outdir, GREEN)
        # TODO: reimplement clean-rpmsrate in python(?)
        #       can probably replace much of it's functionality with meta packages
        os.system("clean-rpmsrate -o %s/media/media_info/rpmsrate %s %s" % (outdir, rpmsrate, string.join(rpmdirs," ")))
        if not os.path.exists("%s/media/media_info/rpmsrate" % outdir):
            print "error in rpmsrate"
            exit(1)

        print color("Copying second stage installer: %s/install/stage2/mdkinst.cpio.xz" % outdir, GREEN)
        os.mkdir("%s/install" % outdir)
        os.mkdir("%s/install/stage2" % outdir)
        os.system("ln -sr ../mdkinst.cpio.xz %s/install/stage2/mdkinst.cpio.xz" % outdir)
        os.system("ln -sr ../VERSION %s/install/stage2/VERSION" % outdir)
        os.mkdir("%s/install/extra" % outdir)
        os.system("ln -sr ../../advertising %s/install/extra/advertising" % outdir)

        print color("Generating %s/media/media_info/MD5SUM" % outdir, GREEN)
        os.system("cd %s/media/media_info/; md5sum * > MD5SUM" % outdir)

        self.pkgs = []
        def get_pkgs(pkg):
            self.pkgs.append("%s-%s (%s)" % (pkg.name(), pkg.version(), pkg.arch()))

        urpm.traverse(get_pkgs)
        self.pkgs.sort()
        idxfile = open("%s/%s" % (outdir, "pkg-%s.idx" % config.version), "w")
        for pkg in self.pkgs:
            idxfile.write(pkg+"\n")

        idxfile.close()



    def getMediaCfg(self,config):
        mediaCfg = \
                "[media_info]\n" \
                "version=%s\n" \
                "branch=%s\n" \
                "arch=%s\n" % (config.version, config.branch, self.arch)
        # todo: sort keys in a list and iterate over it as keys
        for name in ['main', 'contrib', 'non-free']:
            if name in self.media.keys():
                mediaCfg += self.media[name].getCfgEntry()
        return mediaCfg

    """ This is an ugly attempt at rewriting the even uglier perl version which
    I have difficulties fully understanding, I also think I've fixed some bugs
    in it..."""
    def get_list_from_CAT(self, filename, category, threshold):
        f = open(filename)
        cat = None
    
        pkgs = []
        weight = None
        for line in f.readlines():
            if "META_CLASS" in line:
                continue
            line = line.strip()
            if line.startswith("#"):
                continue
            if not line:
               cat = None
               weight = None
               continue
            if line.startswith("CAT_"):
                if line == category:
                    cat = category
                else:
                    cat = None
            line = line.split()
            unsetCat = False
            if line[0].isdigit():
                weight, deps = (line[0], line[1:])
                if not cat:
                    for dep in deps:
                        if dep == category:
                            cat = category
                            unsetCat = True
            else:
                deps = line
    
            if not cat:
                continue
    
            for i in range(len(deps)-1,-1,-1):
                dep = deps[i]
                for patt in ("CAT_", "||", "HW", "3D", "HW_", "RADIO", "PHOTO", "LIGHT", "LIVE", "LOCALES"):
                    if patt in dep:
                        deps.pop(i)
    
            if deps:
                pkgs.extend(deps)
    
                if False:
                    if int(weight) >= int(threshold):
                        print "including: %s (%s >= %s)" % (deps,weight,threshold)
                    else:
                        print "excluding: %s (%s < %s)" % (deps, weight,threshold)
            if unsetCat:
                cat = None
        f.close()
        return pkgs

    def getOutdir(self):
        return self.outdir

    arch = None
    media = []

# vim:ts=4:sw=4:et
