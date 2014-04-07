import shutil,os,perl,string,fnmatch,re,time
from drakx.common import *
perl.require("URPM")
perl.require("urpm")
perl.require("urpm::select")

class Distribution(object):
    def __init__(self, config, arch, media, includelist, excludelist, rpmsrate, compssusers, filedeps, suggests = False, synthfilter = ".cz:gzip -9", root="/usr/lib64/drakx-installer/root", stage1=None, stage2=None, advertising=None, gpgName=None, gpgPass=None):
        volumeid = ("%s-%s-%s-%s" % (config.vendor, config.product, config.version, arch)).upper()
        if len(volumeid) > 32:
            print "length of volumeid '%s' (%d) > 32" % (volumeid, len(volumeid))
            exit(1)
        self.arch = arch
        self.media = {}
        for m in media:
            self.media[m.name] = m

        tmpdir = config.tmpdir+"/"+arch
        repopath = config.repopath+"/"+self.arch
        config.rootdir = root

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
        urpm = perl.eval("""my $urpm = urpm->new();"""
                """$urpm->{error} = sub { printf "urpm error: %s\n", $_[0] };"""
                """$urpm->{fatal} = sub { printf "urpm fatal %s\n", $_[0]; };"""
                # enable for urpm debug output
                #"""$urpm->{log} = sub { printf "urpm log: %s\n", $_[0] };"""
                #"""$urpm->{debug} = sub { printf "urpm debug: %s\n", $_[0] };"""
                #"""$urpm->{debug_URPM} = sub { printf "URPM debug: %s\n", $_[0] };"""
                "$urpm;")

        for m in self.media.keys():
            synthesis = repopath + "/" + self.media[m].getSynthesis()
            print color("Parsing synthesis for %s: %s" % (m, synthesis), GREEN)
            urpm.parse_synthesis(synthesis) 
            updates = repopath + "/" + self.media[m].getSynthesis("updates")
            if os.path.exists(updates):
                print color("Parsing updates synthesis for %s: %s" % (m, synthesis), GREEN)
                urpm.parse_synthesis(updates) 


        perlexc = perl.eval("@excludes = ();")
        perlexc = perl.get_ref("@excludes")
        perlexc.extend(excludes)

        stop_on_choices = perl.eval("""$stop_on_choices = sub {
        my ($urpm, undef, $state_, $choices, $virtual_pkg_name, $preferred) = @_;

        my $dep;
        foreach my $pkg (@$choices) {
            print "\033[0mchoice($virtual_pkg_name): " . $pkg->fullname();
            if (grep { $_ eq $pkg->name() } @excludes) {
                print ": \033[33m\033[49m\033[2mexcluded\n";
                next;
            }

            if (!$dep) {
                print ": \033[33m\033[49m\033[1mincluding\n";
                $dep = $pkg;
            } elsif (!$dep->compare_pkg($pkg)) {
                print ": \033[33m\033[49m\033[1mpreferred over " . $dep->fullname() . "\n";
                $dep = $pkg;
            } else {
                print ": \033[33m\033[49m\033[2mskipped in favour of " . $dep->fullname() . "\n";
            }
        }
        print "\033[0m";

        if (defined($dep)) {
            $state_->{selected}{$dep->id} = 1;
        } else {
                 print "choice($virtual_pkg_name): \033[33m\033[49m\033[2mnone chosen!\n";
        }
        }""")

        def search_pkgs(deps):
            requested = dict()
            state = perl.get_ref("%")

            perl.call("urpm::select::search_packages", urpm, requested, deps, use_provides=1)

            # create a dictionary of URPM::Package objects, indexed by fullname
            # for us to easier lookup packages in
            pkgdict = dict()
            for key in requested.keys():
                if not key:
                    requested.pop(key)
                    continue
                pkgids = key.split("|")
                if not pkgids:
                    continue

                dep = None
                for pkgid in pkgids:
                    pkg = urpm['depslist'][int(pkgid)]
                    if excludere.match(pkg.name()):
                        requested.pop(key)
                        print color("skipping candidate for requested packages: %s" % pkg.fullname(), YELLOW)
                        break
                    if not dep:
                        dep = pkg
                    elif dep.compare_pkg(pkg) < 0:
                        dep = pkg
                if dep:
                    if len(pkgids) > 1:
                        # XXX
                        if key in requested:
                            requested.pop(key)
                            requested[str(dep.id())] = 1
                    pkgdict[pkg.fullname()] = dep

            urpm.resolve_requested(empty_db, state, requested, 
                    no_suggests = not suggests,
                    callback_choices = stop_on_choices, nodeps = 1)

            allpkgs = []

            # As we try resolving all packages we'd like to include in the distribution
            # release at once, there's a fair chance of there being some requested
            # packages conflicting with eachother, resulting in requested packages
            # getting rejected. To workaround this, we'll try resolve these packages
            # separately to still include them and their dependencies.
            rejects = []
            for key in state['rejected'].keys():
                reject = state['rejected'][key]
                #print color("rejected: %s" % key, RED, RESET, DIM)
                if reject.has_key('backtrack'):
                    backtrack = reject['backtrack']
                    if backtrack.has_key('conflicts'):
                        if key in pkgdict:
                            pkg = pkgdict[key]

                            print color("conflicts: %s with %s" % (key, list(backtrack['conflicts'])), RED, RESET, DIM)
                            if pkg.name() in deps and pkg.name() not in rejects:
                                conflicts = backtrack['conflicts']
                                skip = False
                                for c in conflicts:
                                    # XXX
                                    if c in pkgdict:
                                        cpkg = pkgdict[c]
                                        # if it's a package rejected due to conflict with a package of same name,
                                        # it's most likely some leftover package in repos that haven't been
                                        # removed yet and that we can safely ignore
                                        if cpkg.name() == pkg.name():
                                            skip = True
                                    else:
                                        skip = True
                                if not skip:
                                    print color("The requested package %s has been rejected due to conflicts with: %s" %
                                            (pkg.fullname(), string.join(conflicts)), RED, RESET, BRIGHT)
                                    rejects.append(pkg.name())
            if rejects:
                print color("Trying to resolve the following requested packages rejected due to conflicts: %s" %
                        string.join(rejects, " "), BLUE, RESET, BRIGHT)
                res = search_pkgs(rejects)
                for pkg in res:
                    pkgid = str(pkg.id())
                    if not pkgid in state['selected'].keys():
                        print color("adding %s" % pkg.fullname(), BLUE)
                        state['selected'][pkgid] = 1

            for pkgid in state['selected'].keys():
                pkgids = pkgid.split('|')
            
                dep = None
                for pkgid in pkgids:
                    pkgid = int(pkgid)
                    pkg = urpm['depslist'][pkgid]
                    if excludere.match(pkg.name()):
                        print color("skipping1: %s" % pkg.fullname(), YELLOW, RESET, DIM)
                        continue
                    #else:
                    #    print color("including1: %s" % pkg.fullname(), YELLOW, RESET, BRIGHT)

                    if not dep:
                        dep = pkg
                    else:
                        print color("hum: %s" % pkg.fullname(), YELLOW, RESET, DIM)
                        True
                if dep is None:
                    print color("dep is none: %s" % pkg.fullname(), YELLOW, RESET, DIM)
                    continue
                else:
                    #print color("including: %s" % pkg.fullname(), YELLOW, RESET, BRIGHT)
                    allpkgs.append(dep)
            return allpkgs

        print color("Resolving packages", GREEN)
        allpkgs = search_pkgs(includes)
        # we allow to search through all matches regardless of being able to satisfy
        # dependencies, for in which case urpmi doesn't check which to prefer in case
        # several versions of same package is found, urpmi just picks first returned,
        # so we need to do a second run to make sure that we actually get the right ones
        includes = []
        for p in allpkgs:
            includes.append(p.name())
        allpkgs = search_pkgs(includes)

        print color("Initiating distribution tree", GREEN)
        smartopts = "channel -o sync-urpmi-medialist=no --data-dir smartdata"
        os.system("rm -rf " + tmpdir)
        os.system("rm -rf smartdata")
        os.mkdir("smartdata")
        os.system("mkdir -p %s/media/media_info/" % tmpdir) 
        shutil.copy(compssusers, "%s/media/media_info/compssUsers.pl" % tmpdir)
        shutil.copy(filedeps, "%s/media/media_info/file-deps" % tmpdir)
        rootfiles = ['COPYING', 'index.htm', 'install.htm', 'INSTALL.txt', 'LICENSE-APPS.txt', 'LICENSE.txt',
                'README.txt', 'release-notes.html', 'release-notes.txt', 'doc', 'misc']
        for f in rootfiles:
            os.symlink("%s/%s" % (repopath, f), "%s/%s" % (tmpdir, f))

        f = open(tmpdir+"/product.id", "w")
        # unsure about relevance of all these fields, will just hardcode those seeming irrelevant for now..
        f.write("vendor=%s,distribution=%s,type=basic,version=%s,branch=%s,release=1,arch=%s,product=%s\n" % (config.vendor,config.distribution,config.version,config.branch,arch,config.product))
        f.close()
      
        ext = synthfilter.split(":")[0]
        for m in media:
            print color("Generating media tree for " + m.name, GREEN)
            os.system("mkdir -p %s/media/%s" % (tmpdir, m.name))

            pkgs = []
            for pkg in allpkgs:
                if excludere.match(pkg.name()):
                    print color("skipping2: " + pkg.name(), YELLOW, RESET, DIM)
                    continue
                for rep in "release", "updates":
                    source = "%s/media/%s/%s/%s.rpm" % (repopath, m.name, rep, pkg.fullname())
                    if os.path.exists(source):
                        target = "%s/media/%s/%s.rpm" % (tmpdir, m.name, pkg.fullname())
                        if not os.path.islink(target):
                            pkgs.append(source)
                            os.symlink(source, target)
                            s = os.stat(source)
                            m.size += s.st_size
            self.media[m.name].pkgs = pkgs
            if not os.path.exists("%s/media/%s/media_info" % (tmpdir, m.name)):
                os.mkdir("%s/media/%s/media_info" % (tmpdir, m.name))
            if gpgName:
                #signPackage(gpgName, gpgPass, " ".join(pkgs))
                os.system("gpg --export --armor %s > %s/media/%s/media_info/pubkey" % (gpgName, tmpdir, m.name))

        print color("Writing %s/media/media_info/media.cfg" % tmpdir, GREEN)
        if not os.path.exists("%s/media/media_info" % tmpdir):
            os.mkdir("%s/media/media_info" % tmpdir)
        mediaCfg = \
                "[media_info]\n" \
                "mediacfg_version=2\n" \
                "version=%s\n" \
                "branch=%s\n" \
                "product=%s\n" \
                "arch=%s\n" \
                "synthesis-filter=%s\n" \
                "xml-info=1\n" \
                "xml-info-filter=.lzma:lzma --text\n" % (config.version, config.branch, config.product, self.arch, synthfilter)

        for m in media:
            mediaCfg += m.getCfgEntry(ext=ext)

        f = open("%s/media/media_info/media.cfg" % tmpdir, "w")
        f.write(mediaCfg)
        f.close()
        os.system("gendistrib "+tmpdir)
        os.system("rm %s/media/media_info/{MD5SUM,*.cz}" % tmpdir)

        for m in media:
            # workaround for urpmi spaghetti code which hardcodes .cz
            if ext != ".cz":
                os.symlink("synthesis.hdlist%s" % ext, "%s/media/%s/media_info/synthesis.hdlist.cz" % (tmpdir, m.name))

            os.unlink("%s/media/%s/media_info/hdlist.cz" % (tmpdir, m.name))
            os.system("cd %s/media/%s/media_info/; md5sum * > MD5SUM" % (tmpdir, m.name))

            smartopts = "-o sync-urpmi-medialist=no --data-dir %s/smartdata" % os.getenv("PWD")
            os.system("smart channel --yes %s --add %s type=urpmi baseurl=%s/media/%s/ hdlurl=media_info/synthesis.hdlist%s" %
                    (smartopts, m.name, tmpdir, m.name, ext))

        print color("Checking packages", GREEN)
        rpmdirs = []
        for m in self.media.keys():
            rpmdirs.append("%s/media/%s" % (tmpdir, m))
        os.system("smart update %s" % smartopts)
        os.system("smart check %s --channels=%s" % (smartopts, string.join(self.media.keys(),",")))
        os.system("sleep 5");

        print color("Generating %s/media/media_info/rpmsrate" % tmpdir, GREEN)
        # TODO: reimplement clean-rpmsrate in python(?)
        #       can probably replace much of it's functionality with meta packages
        os.system("clean-rpmsrate -o %s/media/media_info/rpmsrate %s %s" % (tmpdir, rpmsrate, string.join(rpmdirs," ")))
        if not os.path.exists("%s/media/media_info/rpmsrate" % tmpdir):
            print "error in rpmsrate"
            exit(1)

        # if none specified, rely on it's presence in grub target tree...
        if not stage1:
            stage1 = "%s/grub/%s/install/images/all.cpio.xz" % (config.rootdir, self.arch)
        print color("Copying first stage installer: %s -> %s/install/images/all.cpio.xz" % (stage1, tmpdir), GREEN)
        os.mkdir("%s/install" % tmpdir)
        os.mkdir("%s/install/images" % tmpdir)
        os.system("ln -sr %s %s/install/images/all.cpio.xz" % (stage1, tmpdir))

        if not stage2:
            stage2 = "%s/install/stage2/mdkinst.cpio.xz" % config.rootdir
        print color("Copying second stage installer: %s -> %s/install/stage2/mdkinst.cpio.xz" % (stage2, tmpdir), GREEN)
        os.mkdir("%s/install/stage2" % tmpdir)
        os.system("ln -sr %s %s/install/stage2/mdkinst.cpio.xz" % (stage2, tmpdir))
        os.system("ln -sr ../VERSION %s/install/stage2/VERSION" % tmpdir)

        if not advertising:
            advertising="%s/install/extra/advertising" % config.rootdir
        print color("Copying advertising: %s -> %s/install/extra/advertising" % (advertising, tmpdir), GREEN)
        os.mkdir("%s/install/extra" % tmpdir)
        os.system("ln -sr %s %s/install/extra/advertising" % (advertising, tmpdir))

        print color("Generating %s/media/media_info/MD5SUM" % tmpdir, GREEN)
        os.system("cd %s/media/media_info/; md5sum * > MD5SUM" % tmpdir)

        self.pkgs = []
        def get_pkgs(pkg):
            self.pkgs.append("%s-%s (%s)" % (pkg.name(), pkg.version(), pkg.arch()))

        urpm.traverse(get_pkgs)
        self.pkgs.sort()
        idxfile = open("%s/pkg-%s-%s-%s.idx" % (tmpdir, config.version, config.subversion.replace(" ","").lower(),config.codename.replace(" ","-").lower()), "w")
        for pkg in self.pkgs:
            idxfile.write(pkg+"\n")

        idxfile.close()



    """ This is an ugly attempt at rewriting the even uglier perl version which
    I have difficulties fully understanding, I also think I've fixed some bugs
    in it..."""
    def get_list_from_CAT(self, filename, category, threshold):
        f = open(filename)
        cat = None
    
        pkgs = []
        weight = None
        # XXX
        breaknext = False
        for line in f.readlines():
            if "META_CLASS" in line:
                continue
            line = line.strip()
            if line.startswith("#"):
                continue
            if not line:
                if breaknext:
                    cat = None
                    weight = None
                    breaknext = False
                else:
                    breaknext = True
                continue
            if breaknext:
               breaknext = False
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
                if int(weight) >= int(threshold):
                    print color("rpmsrate including: %s (%s >= %s)" % (deps,weight,threshold), YELLOW, RESET, BRIGHT)
                    pkgs.extend(deps)
                else:
                    print color("rpmsrate excluding: %s (%s < %s)" % (deps, weight,threshold), YELLOW, RESET, DIM)
            if unsetCat:
                cat = None
        f.close()
        return pkgs

    def getOutdir(self):
        return self.tmpdir

    arch = None
    media = []

# vim:ts=4:sw=4:et
