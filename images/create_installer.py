#!/usr/bin/env python

import sys,os
import perl

iso=sys.argv[1]
listfile=sys.argv[2]
excludefile=sys.argv[3]
repo = "/mnt/BIG/distrib/devel/2012/x86_64"

excludes = []
f = open(excludefile)
for line in f.readlines():
    excludes.append(line.strip())
f.close()
f = open(listfile)
pattern = f.readline().strip()
for line in f.readlines():
	pkg = line.strip()
	if len(pkg) == 0 or pkg[0] == '#':
		continue

	pattern += "|"+ line.strip()
f.close()

def shouldExclude(pkgname):
    for exname in excludes:
	if len(exname) >= len(pkgname):
	    if exname == pkgname[0:len(exname)]:
		return True
    return False

perl.require("URPM");

if 1:
    db = perl.call("URPM::DB::open", "/tmp/rpmdb", 0)

    urpm = perl.callm("new", "URPM");
    urpm.parse_synthesis(repo + "/media/main/release/media_info/synthesis.hdlist.cz")
    urpm.parse_synthesis(repo + "/media/contrib/release/media_info/synthesis.hdlist.cz")

    cand_pkgs = urpm.find_candidate_packages(pattern)
    cand_pkgs_filtered = {}
    for key in cand_pkgs.keys():
	if shouldExclude(key):
	    continue
	cand_pkgs_filtered[key] = cand_pkgs[key]

    pkgs = urpm.resolve_requested__no_suggests_(db, None, cand_pkgs_filtered, __wantarray__ = 1)

    main = []
    contrib = []
    os.system("rm -rf ut; mkdir -p ut/media/{main,contrib}")

    for pkg in pkgs:
	if shouldExclude(pkg.name()):
	    continue

	source = repo + "/media/main/release/" + pkg.fullname() + ".rpm"
	if os.path.exists(source):
	    target = "ut/media/main/" + pkg.fullname() + ".rpm"
	    if not os.path.islink(target):
		main.append(source)
		os.symlink(source, target)
	else:
	    source = repo + "/media/contrib/release/" + pkg.fullname() + ".rpm"
	    if os.path.exists(source):
		target = "ut/media/contrib/" + pkg.fullname() + ".rpm"
		if not os.path.islink(target):
		    contrib.append(source)
		    os.symlink(source, target)

    os.system("genhdlist2 ut/media/main/")
    os.system("genhdlist2 ut/media/contrib/")

    for (path, dirs, files) in os.walk("ut/media/main"):
	for f in files:
	    if f.endswith(".rpm"):
		os.unlink("%s/%s" % (path,f))

    for (path, dirs, files) in os.walk("ut/media/contrib"):
	for f in files:
	    if f.endswith(".rpm"):
		os.unlink("%s/%s" % (path,f))

    os.system("cp -f images/boot.iso installer.iso")

    filemap = ""
    for f in main:
	filemap += "-map %s /media/main/%s " % (f, os.path.basename(f))
    for f in contrib:
	filemap += "-map %s /media/contrib/%s " % (f, os.path.basename(f))

    os.system("xorriso -dev installer.iso "
	    "-map ut/media /media "
	    "%s"
    	    "-boot_image grub patch "
	    "-boot_image grub bin_path=boot/grub/i386-pc/eltorito.img "
	    "-boot_image any boot_info_table=on "
	    "-boot_image any show_status "
	    "-commit"
	    "" % filemap)

