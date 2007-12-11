package install::media; # $Id$

use strict;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(getFile_ getAndSaveFile_ getAndSaveFile_media_info packageMedium);

use common;
use fs::type;


#- list of fields for {phys_medium} :
#-	device
#-	finalpath
#-	from_iso
#-	fs_type
#-	is_suppl (is a supplementary media)
#-	isMounted
#-	loopback_device
#-	loopback_file
#-	method
#-	mntpoint
#-	name (text description, same as first medium {name})
#-	real_mntpoint
#-	rel_path (for isofiles and cdrom)
#-	url

#- list of fields for {media} :
#-	end (last rpm id, undefined iff not selected)
#-	fakemedium ("$name ($rpmsdir)", used locally by urpmi)
#-	rel_hdlist
#-	hdlist_size
#-	key_ids (hashref, values are key ids)
#-	name (text description)
#-	pubkey (array containing all the keys to import)
#-	phys_medium
#-	rpmsdir
#-	selected
#-	size (in MB)
#-	start (first rpm id, undefined iff not selected)
#-	synthesis_hdlist_size
#-	update (for install_urpmi)


our $postinstall_rpms = '';
my %mounted_media;

sub free_medium_id {
    my ($media) = @_;
    int(@$media);
}

sub allMediums {
    my ($packages) = @_;

    @{$packages->{media}};
}

sub phys_media {
    my ($packages) = @_;

    uniq(map { $_->{phys_medium} } @{$packages->{media}});
}

sub pkg2media {
   my ($media, $p) = @_; 
   $p or internal_error("invalid package");

   find {
       $_->{selected} &&
	 $p->id >= $_->{start} && $p->id <= $_->{end};
   } @$media;
}

sub packageMedium {
   my ($packages, $p) = @_;

   pkg2media($packages->{media}, $p) || {};
}
sub packagesOfMedium {
    my ($packages, $medium) = @_;

    @{$packages->{depslist}}[$medium->{start} .. $medium->{end}];
}

sub first_medium {
    my ($packages) = @_;
    $packages->{media}[0];
}

sub path {
    my ($phys_m, $f) = @_;

    ($phys_m->{real_mntpoint} || fs::get::mntpoint_prefixed($phys_m)) . $phys_m->{rel_path} . '/' . $f;
}

sub rel_rpm_file {
    my ($medium, $f) = @_;
    if (my ($arch) = $f =~ m|\.([^\.]*)\.rpm$|) {
	$f = "$medium->{rpmsdir}/$f";
	$f =~ s/%{ARCH}/$arch/g;
	$f =~ s,^/+,,g;
    }
    $f;
}

sub umount_phys_medium {
    my ($phys_m) = @_;

    my $ok = eval { 
	fs::mount::umount_part($phys_m); 
	delete $phys_m->{real_mntpoint}; #- next time, we can mount it in the dest dir
	1;
    };
    if ($@) {
	log::l("umount phys_medium $phys_m->{url} failed ($@)");
	log::l("files still open: ", readlink($_)) foreach map { glob_("$_/fd/*") } glob_("/proc/*");
    }
    $ok;
}
sub mount_phys_medium {
    my ($phys_m, $o_rel_file, $b_force_change) = @_;

    if (!$b_force_change) {
	eval { fs::mount::part($phys_m) };
	return if $@;
    }
    my $ok = !$o_rel_file || -e path($phys_m, $o_rel_file);

    if ($phys_m->{method} eq 'cdrom' && ($b_force_change || !$ok)) {
	$ok = $::o->ask_change_cd($phys_m, $o_rel_file);
    }
    $ok;
}

sub umount_media {
    my ($packages) = @_;

    #- we don't bother umounting first phys medium if clp is not on disk
    #- (this is mainly for nfs installs using install/stage2/live)
    my @l = phys_media($packages);
    shift @l if !$install::any::compressed_image_on_disk && $l[0]{is_stage2_phys_medium};

    umount_phys_medium($_) foreach @l;
    umount_phys_medium($_) foreach grep { $_ } map { $_->{loopback_device} } @l;
}

sub url_respect_privacy {
    my ($url) = @_;

    $url =~ s!ftp://.*?\@!ftp://xxx@!;
    $url;
}
sub phys_medium_to_string {
    my ($phys_m) = @_;
    url_respect_privacy($phys_m->{url}) . ($phys_m->{name} ? " ($phys_m->{name})" : '');
}

sub stage2_mounted_medium {
    my ($method, $rel_path) = @_;

    my ($device, $real_mntpoint, $fs_type, $url);
    if ($method eq 'nfs') {
	(my $server, my $nfs_path, $real_mntpoint, $fs_type) = cat_("/proc/mounts") =~ m!(\S+):(\S+)\s+(/tmp/media)\s+(\S+)!;
	$device = "$server:$nfs_path";
	$url = "nfs://$server$nfs_path$rel_path";
    } elsif ($method eq 'disk') {
	($device, $real_mntpoint, $fs_type) = cat_("/proc/mounts") =~ m!/dev/(\S+)\s+(/tmp/media)\s+(\S+)!;
	$url = "disk://$device$rel_path";
    } elsif ($method eq 'cdrom') {
	($device, $real_mntpoint, $fs_type) = cat_("/proc/mounts") =~ m!/dev/(\S+)\s+(/tmp/media)\s+(\S+)!;
	$url = "cdrom:/" . ($rel_path || '/');
    } else {
	($device, $real_mntpoint, $fs_type) = cat_("/proc/mounts") =~ m!(?:/dev/)?(\S+)\s+(/tmp/media)\s+(\S+)!;
	$url = "file:/" . ($rel_path || '/');
    }
    $real_mntpoint or internal_error("no real_mntpoint");
    +{ 
	method => $method, rel_path => $rel_path, isMounted => 1,
	device => $device, url => $url,
	real_mntpoint => $real_mntpoint, fs_type => $fs_type,
    };
}

#- used once at beginning of install
sub stage2_phys_medium {
    my ($method) = @_;

    if ($method eq 'ftp' && !$ENV{URLPREFIX}) {
	my $user = $ENV{LOGIN} && ($ENV{LOGIN} . ($ENV{PASSWORD} && ":$ENV{PASSWORD}") . '@');
	$ENV{URLPREFIX} = "ftp://$user$ENV{HOST}/$ENV{PREFIX}";
    }
    if ($method eq 'http' || $method eq 'ftp') {
	{ method => $method, url => $ENV{URLPREFIX} };
    } elsif ($method =~ /(.*)-iso$/) {
	my $dir_method = $1;
	my $rel_path = readlink('/tmp/image') =~ m!loop/*(/.*)! ? $1 : '';

	my $rel_iso = $ENV{ISOPATH} =~ m!media/*(/.*)! ? $1 : '';
	my ($dir_url, $iso) = (dirname($rel_iso), basename($rel_iso));

	my $dir_medium = stage2_mounted_medium($dir_method, $dir_url eq '/' ? '' : $dir_url);
	my $phys_m = iso_phys_media($dir_medium, $iso, '');
	$phys_m->{real_mntpoint} = '/tmp/loop';
	$phys_m->{real_device} = cat_("/proc/mounts") =~ m!(/dev/\S+)\s+/tmp/loop\s! && $1;
	$phys_m->{isMounted} = 1;
	$phys_m->{rel_path} = $rel_path;
	$phys_m;
    } else {
	my $rel_path = readlink('/tmp/image') =~ m!media/*(/.*)! ? $1 : '';
	stage2_mounted_medium($method, $rel_path);
    }
}

#- return true if the medium is available
#- ($o_rel_file is only used for removable media)
sub change_phys_medium {
    my ($phys_m, $o_rel_file, $o_packages) = @_;

    undef $o_rel_file if $phys_m->{unknown_CD}; #- don't take into account the wanted file

    log::l("change_phys_medium " . phys_medium_to_string($phys_m) .
	     ($o_rel_file ? " for file $o_rel_file" : ''));

    !$phys_m->{isMounted} && $phys_m->{mntpoint} or return 1; #- nothing to do in such case.

    #- if a cdrom was mounted and we want another one, do not try to mount cdrom just after umounting it
    my $force_change = $phys_m->{method} eq 'cdrom' && $mounted_media{cdrom};

    if (my $current = $mounted_media{$phys_m->{method}}) {
	setup_postinstall_rpms($::o, $o_packages, $current) if $o_packages && $phys_m->{method} eq 'cdrom' && $::o->isa('interactive');
	umount_phys_medium($current) or return;
	delete $mounted_media{$phys_m->{method}};
    }
    mount_phys_medium($phys_m, $o_rel_file, $force_change) or return;
    phys_medium_is_mounted($phys_m);
    1;
}

sub phys_medium_is_mounted {
    my ($phys_m) = @_;
    if (member($phys_m->{method}, 'cdrom', 'iso')) {
	#- we can't have more than one cdrom mounted at once
	#- we limit the number of iso files mounted at once
	$mounted_media{$phys_m->{method}} = $phys_m;
    }
}

sub associate_phys_media {
    my ($all_hds, $main_phys_medium, $hdlists) = @_;

    my ($main_name, @other_names) = uniq(map { $_->{name} } @$hdlists);

    my @other_phys_media = 
      $main_phys_medium->{method} eq 'iso' ?
	get_phys_media_iso($all_hds, $main_phys_medium, \@other_names) :
      $main_phys_medium->{method} eq 'cdrom' ?
	(map { get_phys_media_cdrom($main_phys_medium, $_) } @other_names) :
	  ();

    if (@other_phys_media) {
	$main_phys_medium->{name} = $main_name;

	my @phys_media = ($main_phys_medium, @other_phys_media);

	foreach my $medium (@$hdlists) {
	    if (my $phys_m = find { $_->{name} eq $medium->{name} } @phys_media) {
		$medium->{phys_medium} and log::l("$medium->{name} has already phys_medium $medium->{phys_medium}{url}");
		log::l("setting medium $medium->{name} phys_medium to $phys_m->{url}");
		$medium->{phys_medium} = $phys_m;
	    } else {
		$medium->{selected} = 0;
		log::l("deselecting missing medium $medium->{rpmsdir}");
	    }
	}
    } else {
	foreach my $medium (@$hdlists) {
	    $medium->{phys_medium} = $main_phys_medium;
	}
    }
}

sub get_phys_media_cdrom {
    my ($main_phys_m, $name) = @_;

    #- exactly the same as $main_phys_m, but for {name}, {isMounted} and {real_mntpoint}
    +{ %$main_phys_m, name => $name, isMounted => 0, real_mntpoint => undef };
}

sub iso_phys_media {
    my ($dir_medium, $iso, $rel_path) = @_;

    my $mntpoint = "/mnt/$iso";
    $mntpoint =~ s/\.iso$//; #- make the mount point a little nicer

    my $rel_file = $dir_medium->{rel_path} . "/$iso";

    +{ 
	url => $dir_medium->{url} . "/$iso", #- only used for printing
	method => 'iso', 
	fs_type => 'iso9660', options => 'noauto,loop',
	loopback_device => $dir_medium, loopback_file => $rel_file, 
	device => ($dir_medium->{real_mntpoint} || $::prefix . $dir_medium->{mntpoint}) . $rel_file,
	mntpoint => $mntpoint, rel_path => $rel_path,
    };
}
sub get_phys_media_iso {
    my ($all_hds, $main_phys_m, $names) = @_;

    my @ISOs = grep { member($_->{app_id}, @$names) } look_for_ISO_images($main_phys_m->{device});

    map {
	my $m = iso_phys_media($main_phys_m->{loopback_device}, $_->{file}, $main_phys_m->{rel_path});
	$m->{name} = $_->{app_id};
	push @{$all_hds->{loopbacks}}, $m;
	$m;
    } @ISOs;
}
sub look_for_ISO_images {
    my ($main_iso) = @_;

    my $iso_dir = dirname($main_iso);

    my @media = map {
	if (sysopen(my $F, "$iso_dir/$_", 0)) {
	    my ($vol_id, $app_id) = c::get_iso_volume_ids(fileno $F);
	    #- the ISO volume names must end in -CD\d+ if they belong (!) to a set
	    #- otherwise use the full volume name as CD set identifier
	    my $cd_set = $vol_id =~ /^(.*)-(disc|cd|dvd)\d+$/i ? $1 : $vol_id;

	    log::l("found ISO: file=$_ cd_set=$cd_set app_id=$app_id");
	    { cd_set => $cd_set, app_id => $app_id, file => $_ };
	} else {
	    ();
	}
    } grep { /\.iso$/ } all($iso_dir);

    my $main = find { basename($main_iso) eq $_->{file} } @media or return;

    grep { $_->{cd_set} eq $main->{cd_set} } @media;
}


sub getFile_media_info {
    my ($packages, $f) = @_;
    getFile_(first_medium($packages)->{phys_medium}, $f);
}

sub open_file_and_size {
    my ($f) = @_;
    my $size = -s $f;
    my $fh = common::open_file($f) or return;
    $size, $fh;
}
sub getFile_ {
    my ($phys_m, $f) = @_;
    log::l("getFile $f on " . phys_medium_to_string($phys_m) . "");

    my ($_size, $fh) = get_file_and_size($phys_m, $f) or return;
    $fh;
}
sub get_file_and_size {
    my ($phys_m, $f) = @_;

    if ($f =~ m|^http://|) {
	require install::http;
	install::http::get_file_and_size($f);
    } elsif ($phys_m->{method} eq "ftp") {
	require install::ftp;
	install::ftp::get_file_and_size($f, $phys_m->{url});
    } elsif ($phys_m->{method} eq "http") {
	require install::http;
	install::http::get_file_and_size_($f, $phys_m->{url});
    } elsif ($f =~ m!^/!) {
	open_file_and_size($f);
    } elsif ($postinstall_rpms && -e "$postinstall_rpms/$f") {
	open_file_and_size("$postinstall_rpms/$f");
    } else {
	my $f2 = path($phys_m, $f);

	if (! -f $f2) {
	    change_phys_medium($phys_m, $f, $::o->{packages});
	}
	open_file_and_size($f2);
    }
}

sub getAndSaveFile_ {
    my ($phys_m, $file, $local) = @_;
    my $fh = getFile_($phys_m, $file) or return;
    getAndSaveFile_raw($fh, $local);
}
sub getAndSaveFile_progress {
    my ($in_wait, $msg, $phys_m, $file, $local) = @_;
    my ($size, $fh) = get_file_and_size($phys_m, $file) or return;
    if ($size) {
	getAndSaveFile_progress_raw($in_wait, $msg, $size, $fh, $local);
    } else {
	getAndSaveFile_raw($fh, $local);
    }
}
sub getAndSaveFile_raw {
    my ($fh, $local) = @_;

    local $/ = \ (16 * 1024);
    unlink $local;
    open(my $F, ">$local") or log::l("getAndSaveFile(opening $local): $!"), return;
    local $_;
    while (<$fh>) { syswrite($F, $_) or unlink($local), die("getAndSaveFile($local): $!") }
    1;
}
sub getAndSaveFile_progress_raw {
    my ($in_wait, $msg, $size, $fh, $local) = @_;

    unlink $local;
    open(my $out, ">$local") or log::l("getAndSaveFile(opening $local): $!"), return;
    print_with_progress($in_wait, $msg, $size, $fh, $out) or unlink($local), die("getAndSaveFile($local): $!");
}
sub print_with_progress {
    my ($in_wait, $msg, $size, $in, $out) = @_;

    my ($_wait, $wait_message) = $in_wait->wait_message_with_progress_bar(N("Please wait"));
    $wait_message->($msg);

    my $current = 0;

    require Time::HiRes;
    my $time = Time::HiRes::time();

    local $/ = \ (64 * 1024);
    while (my $s = <$in>) { 
	syswrite($out, $s) or return;

	$current += length($s);
	if (Time::HiRes::time() > $time + 0.1) {
	    $wait_message->('', $current, $size);
	    $time = Time::HiRes::time();
	}
    }
    1;
}


sub urpmidir() {
    my $v = "$::prefix/var/lib/urpmi";
    -l $v && !-e $v and unlink $v and mkdir $v, 0755; #- dangling symlink
    -w $v ? $v : '/tmp';
}

sub hdlist_on_disk {
    my ($m) = @_;

    urpmidir() . "/hdlist.$m->{fakemedium}.cz";
}

sub allow_copy_rpms_on_disk {
    my ($medium, $hdlists) = @_;

    $medium->{device} && $medium->{method} ne 'iso' or return;

    #- check available size for copying rpms from infos in media.cfg file
    my $totalsize = sum(map { $_->{size} } @$hdlists) || -1; #- don't check size, total medium size unknown

    if ($totalsize >= 0) {
	my $availvar = install::any::getAvailableSpace_mounted("$::prefix/var");
	$availvar /= 1024 * 1024; #- Mo
	log::l("totalsize=$totalsize, avail on $::prefix/var=$availvar");
	$totalsize < $availvar * 0.6;
    } else {
	#- we hope it will fit...
	1;
    }
}

sub parse_media_cfg {
    my ($cfg) = @_;

    require MDV::Distribconf;
    my $d = MDV::Distribconf->new('', undef);
    $d->parse_mediacfg($cfg);

    my $distribconf = { map { $_ => $d->getvalue(undef, $_) } 'suppl', 'askmedia' };
    my @hdlists = map { 
	my ($size) = $d->getvalue($_, 'size') =~ /(\d+)MB?/i;
	my $name = $d->getvalue($_, 'name'); 
	$name =~ s/^"(.*)"$/$1/;
	{ 
	    rpmsdir => $_,
	    rel_hdlist => 'media_info/' . $d->getvalue($_, 'hdlist'),
	    name => $name,
	    size => $size,
	    selected => !$d->getvalue($_, 'noauto'),
	    update => $d->getvalue($_, 'updates_for') ? 1 : undef,
	};
    } $d->listmedia;

    $distribconf, \@hdlists;
}

sub parse_hdlists {
    my ($cfg) = @_;

    my (%main_options, @hdlists);
    foreach (cat_($cfg)) {
        chomp;
        s/\s*#.*$//;
        /^\s*$/ and next;
        #- we'll ask afterwards for supplementary CDs, if the hdlists file contains
        #- a line that begins with "suppl"
        if (/^suppl/) { $main_options{suppl} = 1; next }
        #- if the hdlists contains a line "askmedia", deletion of media found
        #- in this hdlist is allowed
        if (/^askmedia/) { $main_options{askmedia} = 1; next }
        my ($noauto, $hdlist, $rpmsdir, $name, $size) = m!^\s*(noauto:)?(hdlist\S*\.cz)\s+[^/]*/(\S+)\s*([^(]*)(?:\((.+)\))?$!
            or die qq(invalid hdlist description "$_" in hdlists file);
        $name =~ s/\s+$//;
        $size =~ s/MB?$//i;
        push @hdlists, { rel_hdlist => "media_info/$hdlist", rpmsdir => $rpmsdir, name => $name, selected => !$noauto, size => $size };
    }
    (\%main_options, \@hdlists);
}

sub get_media {
    my ($o, $media, $packages) = @_;

    my ($suppl_CDs, $copy_rpms_on_disk);
    foreach (@$media) {
	if ($_->{type} eq 'media_cfg') {
	    my $phys_m = url2mounted_phys_medium($o, $_->{url}, 'media_info');
	    ($suppl_CDs, $copy_rpms_on_disk) = get_media_cfg($o, $phys_m, $packages, $_->{selected_names}, $_->{force_rpmsrate});
	} elsif ($_->{type} eq 'media') {
	    my $phys_m = url2mounted_phys_medium($o, $_->{url});
	    get_standalone_medium($o, $phys_m, $packages, { name => $_->{id} =~ /media=(.*)/ && $1 });
	} elsif ($_->{type} eq 'media_cfg_isos') {
	    my ($dir_url, $iso, $rel_path) = $_->{url} =~ m!(.*)/(.*\.iso):(/.*)! or die "bad media_cfg_isos url $_->{url}";
	    my $dir_medium = url2mounted_phys_medium($o, $dir_url);
	    $dir_medium->{options} =~ s/\bnoauto\b,?//;
	    my $phys_m = iso_phys_media($dir_medium, $iso, $rel_path);
	    push @{$o->{all_hds}{loopbacks}}, $phys_m;
	    ($suppl_CDs, $copy_rpms_on_disk) = get_media_cfg($o, $phys_m, $packages, $_->{selected_names}, $_->{force_rpmsrate});
	} else {
	    log::l("unknown media type $_->{type}, skipping");
	}
    }
    log::l("suppl_CDs=$suppl_CDs copy_rpms_on_disk=$copy_rpms_on_disk");
    $suppl_CDs, $copy_rpms_on_disk;
}

sub remove_from_fstab {
    my ($all_hds, $phys_m) = @_;

    @{$all_hds->{nfss}} = grep { $_ != $phys_m } @{$all_hds->{nfss}} if $phys_m->{method} eq 'nfs';
}

sub find_and_add_to_fstab {
    my ($all_hds, $phys_m, $b_force_mount) = @_;

    if (my $existant = find { $_->{device} eq $phys_m->{device} } fs::get::really_all_fstab($all_hds)) {
	add2hash($existant, $phys_m);
	$phys_m = $existant;
    } else {
	push @{$all_hds->{nfss}}, $phys_m if $phys_m->{method} eq 'nfs';
	push @{$all_hds->{loopbacks}}, $phys_m if isLoopback($phys_m);
    }

    if (!$phys_m->{mntpoint}) {
	my @suggestions = $phys_m->{method} eq 'nfs' ? do {
	    my ($server) = $phys_m->{device} =~ /(.*?):/;
	    $phys_m->{options} = ($b_force_mount ? '' : 'noauto,') . 'ro,nosuid,soft,rsize=8192,wsize=8192';
	    '/mnt/nfs', "/mnt/nfs_$server";
	} : $phys_m->{method} eq 'cdrom' ?
	  ('/media/cdrom', "/media/$phys_m->{device}") :
	  ('/mnt/hd', "/mnt/$phys_m->{device}");

	my $last = $suggestions[-1];
	push @suggestions, map { "$last$_" } 2 .. 30;
	$phys_m->{mntpoint} = find { !fs::get::has_mntpoint($_, $all_hds) } @suggestions or internal_error("no free dir available");
    }
    $phys_m;
}

sub url2mounted_phys_medium {
    my ($o, $url, $o_rel_file, $o_name) = @_;

    my $phys_m = url2phys_medium($o, $url);
    $phys_m->{name} = $o_name if $o_name; #- useful for CDs which prompts a name in change_phys_medium
    change_phys_medium($phys_m, $o_rel_file, $o->{packages}) or return;
    $phys_m;
}

sub url2phys_medium {
    my ($o, $url) = @_;
    my ($method, $path) = $url =~ m!([^:]*)://(.*)! or internal_error("bad url $url");
    if ($method eq 'drakx') {
	my $m = { %{$o->{stage2_phys_medium}}, is_stage2_phys_medium => 1 };
	if ($m->{loopback_device}) {
	    $m->{loopback_device} = find_and_add_to_fstab($o->{all_hds}, $m->{loopback_device}, 'force_mount');
	}
	$m->{url} .= "/$path";
	$m->{rel_path} .= "/$path" if $m->{device};
	$m = find_and_add_to_fstab($o->{all_hds}, $m) if $m->{device};
	phys_medium_is_mounted($m);
	$m;
    } elsif ($method eq 'cdrom') {
	my $cdrom = first(detect_devices::cdroms());
	my $m = { 
	    url => $url, method => $method, fs_type => 'iso9660', device => $cdrom->{device}, 
	    rel_path => "/$path",
	};
	my $m_ = find_and_add_to_fstab($o->{all_hds}, $m);
	if ($m_->{name}) {
	    #- we need a new phys medium, different from current CD
	    $m_ = get_phys_media_cdrom($m_, '');
	    #- we also need to enforce what we want, especially rel_path
	    put_in_hash($m_, $m);
	}
	$m_;
    } elsif ($method eq 'nfs') {
	my ($server, $nfs_dir) = $path =~ m!(.*?)(/.*)!;

	my $m = { 
	    url => $url, method => $method,
	    fs_type => 'nfs', device => "$server:$nfs_dir", faked_device => 1,
	};
	find_and_add_to_fstab($o->{all_hds}, $m);
    } else {
	{ url => $url, method => $method };
    }
}

sub get_media_cfg {
    my ($o, $phys_medium, $packages, $selected_names, $force_rpmsrate) = @_;

    my ($distribconf, $hdlists);
    if (getAndSaveFile_($phys_medium, 'media_info/media.cfg', '/tmp/media.cfg')) {
	($distribconf, $hdlists) = parse_media_cfg('/tmp/media.cfg');
    } else {
	getAndSaveFile_($phys_medium, 'media_info/hdlists', '/tmp/hdlists')
	  or die "media.cfg not found";
	($distribconf, $hdlists) = parse_hdlists('/tmp/hdlists');
    }

    if (defined $selected_names) {
        my @names = split ',', $selected_names;
        foreach my $h (@$hdlists) {
            $h->{selected} = member($h->{name}, @names);
        }
    }

    my $suppl_CDs = $distribconf->{suppl} || $o->{supplmedia} || 0;
    my $deselectionAllowed = $distribconf->{askmedia} || $o->{askmedia} || 0;

    associate_phys_media($o->{all_hds}, $phys_medium, $hdlists);

    if ($deselectionAllowed && !@{$packages->{media}}) {
	my $allow = allow_copy_rpms_on_disk($phys_medium, $hdlists);
	$o->ask_deselect_media__copy_on_disk($hdlists, $allow && \$o->{copy_rpms_on_disk}) if $allow || @$hdlists > 1;
    }

    foreach my $h (@$hdlists) {
	get_medium($o, $phys_medium, $packages, $h);
    }

    log::l("get_media_cfg read " . int(@{$packages->{depslist}}) . " headers");


    #- copy latest compssUsers.pl and rpmsrate somewhere locally
    if ($force_rpmsrate || ! -e '/tmp/rpmsrate') {
	getAndSaveFile_($phys_medium, "media_info/compssUsers.pl", "/tmp/compssUsers.pl");
	getAndSaveFile_($phys_medium, "media_info/rpmsrate", "/tmp/rpmsrate");
    }


    $suppl_CDs, $o->{copy_rpms_on_disk};
}

sub get_standalone_medium {
    my ($in, $phys_m, $packages, $m) = @_;

    add2hash($m, { phys_medium => $phys_m, selected => 1, rel_hdlist => 'media_info/hdlist.cz' });
    get_medium($in, $phys_m, $packages, $m);
}

sub get_medium {
    my ($in_wait, $phys_m, $packages, $m) = @_;

    $m->{selected} or log::l("ignoring packages in $m->{rel_hdlist}"), return;

    my $medium_id = int @{$packages->{media}};
    $m->{fakemedium} = $m->{name} || $phys_m->{method};
    $m->{fakemedium} =~ s!/!_!g; #- remove "/" from name
    if (find { $m->{fakemedium} eq $_->{fakemedium} } allMediums($packages)) {
	$m->{fakemedium} .= " (" . ($m->{rpmsdir} || $medium_id) . ")";
	$m->{fakemedium} =~ s!/!_!g; #- remove "/" from rpmsdir
    }

    log::l("trying to read $m->{rel_hdlist} for medium '$m->{fakemedium}'");
    
    #- copy hdlist file directly to urpmi directory, this will be used
    #- for getting header of package during installation or after by urpmi.
    my $hdlist = hdlist_on_disk($m);
    {
	getAndSaveFile_progress($in_wait, N("Downloading file %s...", $m->{rel_hdlist}),
				$phys_m, $m->{rel_hdlist}, $hdlist) or die "no $m->{rel_hdlist} found";

	$m->{hdlist_size} = -s $hdlist; #- keep track of size for post-check.
    }

    my $synthesis = urpmidir() . "/synthesis.hdlist.$m->{fakemedium}.cz";
    {
	my $rel_synthesis = $m->{rel_hdlist};
	$rel_synthesis =~ s!/hdlist!/synthesis.hdlist! or internal_error("bad {rel_hdlist} $m->{rel_hdlist}");
	#- copy existing synthesis file too.
	getAndSaveFile_progress($in_wait, N("Downloading file %s...", $rel_synthesis),
				$phys_m, $rel_synthesis, $synthesis);
	$m->{synthesis_hdlist_size} = -s $synthesis; #- keep track of size for post-check.
    }

    #- get all keys corresponding in the right pubkey file,
    #- they will be added in rpmdb later if not found.
    if (!$m->{pubkey}) {
	my $rel_pubkey = $m->{rel_hdlist};
	$rel_pubkey =~ s!/hdlist(.*)\.cz!/pubkey$1! or internal_error("bad {rel_hdlist} $m->{rel_hdlist}");
	$m->{pubkey} = urpmidir() . "/pubkey_$m->{fakemedium}";
	getAndSaveFile_($phys_m, $rel_pubkey, $m->{pubkey});
    }

    #- for standalone medium not using media.cfg
    $phys_m->{name} ||= $m->{name};

    #- integrate medium in media list, only here to avoid download error (update) to be propagated.
    push @{$packages->{media}}, $m;

    #- parse synthesis (if available) of directly hdlist (with packing).
    {
	my $nb_suppl_pkg_skipped = 0;
	my $callback = sub {
	    my (undef, $p) = @_;
	    my $uniq_pkg_seen = $packages->{uniq_pkg_seen} ||= {};
	    if ($uniq_pkg_seen->{$p->fullname}++) {
		log::l("skipping " . scalar $p->fullname);
		++$nb_suppl_pkg_skipped;
		return 0;
	    } else {
		return 1;
	    }
	};
	my $error;
	if (-s $synthesis) {
	    ($m->{start}, $m->{end}) = $packages->parse_synthesis($synthesis, callback => $callback)
	      or $error = "bad synthesis $synthesis for $m->{fakemedium}";
	} elsif (-s $hdlist) {
	    ($m->{start}, $m->{end}) = $packages->parse_hdlist($hdlist, callback => $callback)
	      or $error = "bad hdlist $hdlist for $m->{fakemedium}";
	} else {
	    $error = "fatal: no hdlist nor synthesis to read for $m->{fakemedium}";
	}

	if ($error) {
	    pop @{$packages->{media}};
	    unlink $hdlist, $synthesis;
	    die $error;
	} else {
	    log::l("medium " . phys_medium_to_string($phys_m) . ", read " . ($m->{end} - $m->{start} + 1) . " packages in $m->{rel_hdlist}, $nb_suppl_pkg_skipped skipped");
	}
    }
}



#-######################################################################################
#- Post installation RPMS from cdrom only, functions
#-######################################################################################
sub setup_postinstall_rpms {
    my ($in, $packages, $current_phys_m) = @_;

    $postinstall_rpms and return;
    $postinstall_rpms = "$::prefix/usr/postinstall-rpm";

    log::l("postinstall rpms directory set to $postinstall_rpms");
    clean_postinstall_rpms(); #- make sure in case of previous upgrade problem.

    my @toCopy;
    {
	#- compute closure of package that may be copied, use INSTALL category
	#- in rpmsrate.
	@toCopy = install::pkgs::select_by_package_names($packages, $packages->{needToCopy} || []);
	log::l("needToCopy the following packages: " . join(' ', map { $_->name } @toCopy));
	$packages->disable_selected($packages->{rpmdb}, $packages->{state}, @toCopy);
	delete $packages->{rpmdb};
    }

    my $medium = find { $_->{phys_medium} == $current_phys_m } allMediums($packages);

    my @l = map { path($current_phys_m, "$medium->{rpmsdir}/" . $_->filename) } @toCopy;

    my ($l, $missing) = partition { -r $_ } @l;

    @$missing and log::l("rpms not available: " . join(' ', @$missing));

    #- copy the package files in the postinstall RPMS directory.
    #- cp_af does not handle correctly a missing file.
    mkdir_p("$postinstall_rpms/$medium->{rpmsdir}");
    eval { 
	my ($_w, $wait_message) = $in->wait_message_with_progress_bar;
	$wait_message->(N("Copying some packages on disks for future use"));
	install::any::cp_with_progress($wait_message, 0, int(@$l), @$l, "$postinstall_rpms/$medium->{rpmsdir}");
    };
    !$@ or log::l("copying to postinstall dir failed: $@");

    log::l("copying Auto Install Floppy");
    getAndSaveInstallFloppies($::o, $postinstall_rpms, 'auto_install');
}

sub getAndSaveInstallFloppies {
    my ($o, $dest_dir, $name) = @_;    

    if ($postinstall_rpms && -d $postinstall_rpms && -r "$postinstall_rpms/auto_install.img") {
	log::l("getAndSaveInstallFloppies: using file saved as $postinstall_rpms/auto_install.img");
	cp_af("$postinstall_rpms/auto_install.img", "$dest_dir/$name.img");
	"$dest_dir/$name.img";
    } else {
	my $image = 'hd_grub';

	getAndSaveFile_($o->{stage2_phys_medium}, "install/images/$image.img", "$dest_dir/$name.img") 
	  or log::l("failed to write Install Floppy ($image.img) to $dest_dir/$name.img"), return;

	"$dest_dir/$name.img";
    }
}

sub clean_postinstall_rpms() {
    if ($postinstall_rpms && -d $postinstall_rpms) {
	rm_rf($postinstall_rpms);
    }
}

sub copy_rpms_on_disk {
    my ($o) = @_;

    my $dest_dir = '/var/ftp/pub/Mandrivalinux/media';
    #- don't be afraid, cleanup old RPMs if upgrade
    eval { rm_rf("$::prefix$dest_dir") if $o->{isUpgrade} };
    mkdir_p("$::prefix$dest_dir");

    my $dest_phys_medium = do {
	my ($part, $rel_path) = fs::get::file2part($o->{fstab}, $dest_dir);
	$part->{method} = 'disk';
	$part->{rel_path} = $rel_path;
	$part->{url} = "disk://$part->{device}$rel_path";
	$part;
    };

    my ($wait, $wait_message) = $o->wait_message_with_progress_bar;

    foreach my $m (allMediums($o->{packages})) {
	#- don't copy rpms of supplementary media
	next if $m->{phys_medium}{is_suppl};
	$wait_message->(N("Copying in progress") . "\n($m->{name})"); #- XXX to be translated
	my $rpmsdir = path($m->{phys_medium}, $m->{rpmsdir});
	if (! -d $rpmsdir) {
	    if (!change_phys_medium($m->{phys_medium}, $m->{rpmsdir})) {
		#- keep in mind the asked medium has been refused.
		#- this means it is no longer selected.
		#- (but do not unselect supplementary CDs.)
		$m->{selected} = 0;
	    }
	}
	my $dest_medium_dir = $dest_dir . '/'. basename($rpmsdir);
	#- handle rpmsdir being ../../i586/media/main: we flatten it
	-e "$::prefix$dest_medium_dir" and $dest_medium_dir .= '32';
	-e "$::prefix$dest_medium_dir" and next;

	my $total = install::any::count_files($rpmsdir);
	log::l("copying $rpmsdir to $::prefix$dest_medium_dir ($total files)");
	eval {
	    install::any::cp_with_progress_({}, $wait_message, $total, [$rpmsdir], "$::prefix$dest_medium_dir");
	};
	log::l($@) if $@;

	$m->{rpmsdir} = basename($dest_medium_dir);
	$m->{phys_medium} = $dest_phys_medium;
    }
    undef $wait;

    our $copied_rpms_on_disk = 1;
}

sub install_urpmi__generate_names {
    my ($packages, $medium) = @_;

    #- build a names file
    output("$::prefix/var/lib/urpmi/names.$medium->{fakemedium}",
	   map { $packages->{depslist}[$_]->name . "\n" } $medium->{start} .. $medium->{end});
}
sub install_urpmi__generate_synthesis {
    my ($packages, $medium) = @_;

    my $synthesis = "/var/lib/urpmi/synthesis.hdlist.$medium->{fakemedium}.cz";

    #- build synthesis file if there are still not existing (ie not copied from mirror).
    -s "$::prefix$synthesis" <= 32 or return;

    log::l("building $synthesis");

    eval { $packages->build_synthesis(
	start     => $medium->{start},
	end       => $medium->{end},
	synthesis => "$::prefix$synthesis",
    ) };
    $@ and log::l("build_synthesis failed: $@");
}

#- copied from urpm/media.pm
sub parse_url_with_login {
    my ($url) = @_;
    $url =~ m!([^:]*)://([^/:\@]*)(:([^/:\@]*))?\@([^/]*)(.*)! &&
      { proto => $1, login => $2, password => $4, machine => $5, dir => $6 };
}

sub install_urpmi {
    my ($stage2_method, $packages) = @_;

    my @media = @{$packages->{media}};

    log::l("install_urpmi $stage2_method");
    #- clean to avoid opening twice the rpm db.
    delete $packages->{rpmdb};

    #- import pubkey in rpmdb.
    my $db = install::pkgs::open_rpm_db_rw();
    foreach my $medium (@media) {
	URPM::import_needed_pubkeys_from_file($db, $medium->{pubkey}, sub {
					     my ($id, $imported) = @_;
					     if ($id) {
						 log::l(($imported ? "imported" : "found") . " key=$id for medium $medium->{name}");
						 $medium->{key_ids}{$id} = undef;
					     }
					 });
	unlink $medium->{pubkey};
    }

    my (@cfg, @netrc);
    foreach my $medium (@media) {
	if ($medium->{selected}) {
            my ($dir, $removable_device, $static);

	    my $phys_m = $medium->{phys_medium};
            if ($phys_m->{method} eq 'ftp' || $phys_m->{method} eq 'http') {
		$dir = $phys_m->{url};
	    } else {
		#- for cdrom, removable://... is best since it mounts *and* umounts cdrom
		#- for iso files, removable://... doesn't work correctly
		my $urpmi_method = $phys_m->{method} eq 'cdrom' ? 'removable' : 'file';
		$dir = "$urpmi_method:/$phys_m->{mntpoint}$phys_m->{rel_path}";
		if ($phys_m->{method} eq 'iso') {
		    $removable_device = $phys_m->{loopback_device}{mntpoint} . $phys_m->{loopback_file};
		} elsif ($phys_m->{method} eq 'cdrom') {
		    $removable_device = devices::make($phys_m->{device});
		    $static = 1;
		}
	    }

	    $dir = MDK::Common::File::concat_symlink($dir, $medium->{rpmsdir});

	    install_urpmi__generate_names($packages, $medium);
	    install_urpmi__generate_synthesis($packages, $medium);

	    my ($qname, $qdir) = ($medium->{fakemedium}, $dir);

	    if (my $u = parse_url_with_login($qdir)) {
		$qdir = sprintf('%s://%s@%s%s', $u->{proto}, $u->{login}, $u->{machine}, $u->{dir});
		push @netrc, sprintf("machine %s login %s password %s\n", $u->{machine}, $u->{login}, $u->{password});
	    }

	    s/(\s)/\\$1/g foreach $qname, $qdir;

	    #- output new urpmi.cfg format here.
	    push @cfg, map { "$_\n" } 
	      "$qname $qdir {", 
	      "  media_info_dir: media_info",
		if_(keys(%{$medium->{key_ids}}), 
	      "  key-ids: " . join(',', keys %{$medium->{key_ids}})),
		if_($removable_device, 
	      "  removable: $removable_device"),
		if_($medium->{update},
	      "  update"), 
		if_($static,
	      "  static"),
	      "}";
	} else {
	    #- remove deselected media by removing copied hdlist and synthesis files
	    log::l("removing media $medium->{fakemedium}");
	    unlink "$::prefix/var/lib/urpmi/hdlist.$medium->{fakemedium}.cz";
	    unlink "$::prefix/var/lib/urpmi/synthesis.hdlist.$medium->{fakemedium}.cz";
	}
    }
    eval { output("$::prefix/etc/urpmi/netrc", @netrc) };
    #- touch a MD5SUM file and write config file
    eval { output("$::prefix/var/lib/urpmi/MD5SUM", '') };
    eval { output "$::prefix/etc/urpmi/urpmi.cfg", @cfg };
}


sub openCdromTray {
    my ($cdrom) = @_;
    log::l("ejecting cdrom $cdrom");
    eval { ioctl(detect_devices::tryOpen($cdrom), c::CDROMEJECT(), 1) };
    $@ and log::l("ejection failed: $@");
}

sub log_sizes() {
    my @df = MDK::Common::System::df($::prefix);
    log::l(sprintf "Installed: %dMB(df), %dMB(rpm)",
	   ($df[0] - $df[1]) / 1024,
	   sum(run_program::rooted_get_stdout($::prefix, 'rpm', '-qa', '--queryformat', '%{size}\n')) / 1024 / 1024) if -x "$::prefix/bin/rpm";
    install::pkgs::clean_rpmdb_shared_regions();
}

1;
