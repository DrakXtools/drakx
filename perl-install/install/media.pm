package install::media;

use strict;

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(getFile_ getAndSaveFile_ getAndSaveFile_media_info packageMedium);

use common;
use Data::Dumper;
# Make sure report.bug are more easily comparable:
$Data::Dumper::Sortkeys = 1;
use fs::type;
use urpm::download;
use urpm::media;

#- list of fields for {phys_medium} :
#-	device
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
#-	end (last rpm id, undefined if not selected)
#-	fakemedium ("$name ($rpmsdir)", used locally by urpmi)
#-	rel_hdlist
#-	key-ids
#-	name (text description)
#-	pubkey (array containing all the keys to import)
#-	phys_medium
#-	rpmsdir
#-	ignore
#-	size (in MB)
#-	start (first rpm id, undefined if ignored)
#-	update (for install_urpmi)


our $postinstall_rpms = '';
my %mounted_media;

sub allMediums {
    my ($packages) = @_;

    @{$packages->{media}};
}

sub _phys_media {
    my ($packages) = @_;

    uniq(map { $_->{phys_medium} } @{$packages->{media}});
}

sub packageMedium {
   my ($packages, $p) = @_;
   URPM::pkg2media($packages->{media}, $p) || {};
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

sub _mount_phys_medium {
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
    my @l = _phys_media($packages);
    shift @l if !$install::any::compressed_image_on_disk && $l[0]{is_stage2_phys_medium};

    umount_phys_medium($_) foreach @l;
    umount_phys_medium($_) foreach grep { $_ } map { $_->{loopback_device} } @l;
}

sub phys_medium_to_string {
    my ($phys_m) = @_;
    urpm::download::url_obscuring_password($phys_m->{url}) . ($phys_m->{name} ? " ($phys_m->{name})" : '');
}

sub _stage2_mounted_medium {
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
    if (member($method, qw(http ftp))) {
	{ method => $method, url => $ENV{URLPREFIX} };
    } elsif ($method =~ /(.*)-iso$/) {
	my $dir_method = $1;
	my $rel_path = readlink('/tmp/image') =~ m!loop/*(/.*)! ? $1 : '';

	my $rel_iso = $ENV{ISOPATH} =~ m!media/*(/.*)! ? $1 : '';
	my ($dir_url, $iso) = (dirname($rel_iso), basename($rel_iso));

	my $dir_medium = _stage2_mounted_medium($dir_method, $dir_url eq '/' ? '' : $dir_url);
	my $phys_m = _iso_phys_media($dir_medium, $iso, '');
	$phys_m->{real_mntpoint} = '/tmp/loop';
	$phys_m->{real_device} = cat_("/proc/mounts") =~ m!(/dev/\S+)\s+/tmp/loop\s! && $1;
	$phys_m->{isMounted} = 1;
	$phys_m->{rel_path} = $rel_path;
	$phys_m;
    } else {
	my $rel_path = readlink('/tmp/image') =~ m!media/*(/.*)! ? $1 : '';
	_stage2_mounted_medium($method, $rel_path);
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
	_setup_postinstall_rpms($::o, $o_packages, $current) if $o_packages && $phys_m->{method} eq 'cdrom' && $::o->isa('interactive');
	umount_phys_medium($current) or return;
	delete $mounted_media{$phys_m->{method}};
    }
    _mount_phys_medium($phys_m, $o_rel_file, $force_change) or return;
    _phys_medium_is_mounted($phys_m);
    1;
}

sub _phys_medium_is_mounted {
    my ($phys_m) = @_;
    if (member($phys_m->{method}, 'cdrom', 'iso')) {
	#- we can't have more than one cdrom mounted at once
	#- we limit the number of iso files mounted at once
	$mounted_media{$phys_m->{method}} = $phys_m;
    }
}

sub _associate_phys_media {
    my ($all_hds, $main_phys_medium, $hdlists) = @_;

    my ($main_name, @other_names) = uniq(map { $_->{name} } @$hdlists);

    my @other_phys_media = 
      $main_phys_medium->{method} eq 'iso' ?
	_get_phys_media_iso($all_hds, $main_phys_medium, \@other_names) :
      $main_phys_medium->{method} eq 'cdrom' ?
	(map { _get_phys_media_cdrom($main_phys_medium, $_) } @other_names) :
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
		$medium->{ignore} = 1;
		log::l("deselecting missing medium $medium->{rpmsdir}");
	    }
	}
    } else {
	foreach my $medium (@$hdlists) {
	    $medium->{phys_medium} = $main_phys_medium;
	}
    }
}

sub _get_phys_media_cdrom {
    my ($main_phys_m, $name) = @_;

    #- exactly the same as $main_phys_m, but for {name}, {isMounted} and {real_mntpoint}
    +{ %$main_phys_m, name => $name, isMounted => 0, real_mntpoint => undef };
}

sub _iso_phys_media {
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

sub _get_phys_media_iso {
    my ($all_hds, $main_phys_m, $names) = @_;

    my @ISOs = grep { member($_->{app_id}, @$names) } _look_for_ISO_images($main_phys_m->{device});

    map {
	my $m = _iso_phys_media($main_phys_m->{loopback_device}, $_->{file}, $main_phys_m->{rel_path});
	$m->{name} = $_->{app_id};
	push @{$all_hds->{loopbacks}}, $m;
	$m;
    } @ISOs;
}

sub _look_for_ISO_images {
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


sub _getFile_media_info {
    my ($packages, $f) = @_;
    getFile_(first_medium($packages)->{phys_medium}, $f);
}

sub _open_file_and_size {
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
    } elsif (member($phys_m->{method}, qw(ftp http))) {
	require install::http;
	install::http::get_file_and_size_($f, $phys_m->{url});
    } elsif ($f =~ m!^/!) {
	_open_file_and_size($f);
    } elsif ($postinstall_rpms && -e "$postinstall_rpms/$f") {
	_open_file_and_size("$postinstall_rpms/$f");
    } else {
	my $f2 = path($phys_m, $f);

	if (! -f $f2) {
	    change_phys_medium($phys_m, $f, $::o->{packages});
	}
	_open_file_and_size($f2);
    }
}

sub getAndSaveFile_ {
    my ($phys_m, $file, $local) = @_;
    my $fh = getFile_($phys_m, $file) or return;
    _getAndSaveFile_raw($fh, $local);
}

sub _getAndSaveFile_progress {
    my ($in_wait, $msg, $phys_m, $file, $local) = @_;
    my ($size, $fh) = get_file_and_size($phys_m, $file) or return;
    if ($size) {
	_getAndSaveFile_progress_raw($in_wait, $msg, $size, $fh, $local);
    } else {
	_getAndSaveFile_raw($fh, $local);
    }
}

sub _getAndSaveFile_raw {
    my ($fh, $local) = @_;

    local $/ = \ (16 * 1024);
    unlink $local;
    open(my $F, ">$local") or log::l("getAndSaveFile(opening $local): $!"), return;
    local $_;
    while (<$fh>) { syswrite($F, $_) or unlink($local), die("getAndSaveFile($local): $!") }
    1;
}

sub _getAndSaveFile_progress_raw {
    my ($in_wait, $msg, $size, $fh, $local) = @_;

    unlink $local;
    open(my $out, ">$local") or log::l("getAndSaveFile(opening $local): $!"), return;
    _print_with_progress($in_wait, $msg, $size, $fh, $out) or unlink($local), die("getAndSaveFile($local): $!");
}

sub _print_with_progress {
    my ($in_wait, $msg, $size, $in, $out) = @_;

    my ($_wait, $wait_message) = $in_wait->wait_message_with_progress_bar(N("Please wait, retrieving file"));
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

sub _allow_copy_rpms_on_disk {
    my ($medium, $hdlists) = @_;

    $medium->{device} && $medium->{method} ne 'iso' or return;

    #- check available size for copying rpms from infos in media.cfg file
    my $totalsize = sum(map { $_->{size} } @$hdlists) || -1; #- don't check size, total medium size unknown

    if ($totalsize >= 0) {
	my $availvar = fs::any::getAvailableSpace_mounted("$::prefix/var");
	$availvar /= 1024 * 1024; #- Mo
	log::l("totalsize=$totalsize, avail on $::prefix/var=$availvar");
	$totalsize < $availvar * 0.6;
    } else {
	#- we hope it will fit...
	1;
    }
}

sub _parse_media_cfg {
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

sub select_only_some_media {
    my ($media_list, $selected_names) = @_;
    my @names = split(',', $selected_names);
    foreach my $m (@$media_list) {
        my $bool = !member($m->{name}, @names);
        # workaround urpmi transforming "ignore => ''" or "ignore => 0" into "ignore => 1":
        undef $bool if !$bool;
        log::l("disabling '$m->{name}' medium: " . to_bool($bool));
        urpm::media::_tempignore($m, $bool);
        # make sure we update un-ignored media (eg: */Testing and the like):
        $m->{modified} = 1 if !$bool;
    }
}

sub update_media {
    my ($packages) = @_;
    urpm::media::update_media($packages, distrib => 1, callback => \&urpm::download::sync_logger) or
        log::l('updating media failed');
}

sub get_media {
    my ($o, $media, $packages) = @_;

    my ($suppl_CDs, $copy_rpms_on_disk, $phys_m);
    foreach (@$media) {
	if ($_->{type} eq 'media_cfg') {
	    $phys_m = url2mounted_phys_medium($o, $_->{url}, 'media_info');
            local $phys_m->{is_suppl} = $_->{url} ne "drakx://media"; # so that _get_media_url() works
            ($suppl_CDs, $copy_rpms_on_disk) = get_media_cfg($o, $phys_m, $packages, $_->{selected_names}, $_->{force_rpmsrate});
	} elsif ($_->{type} eq 'media') {
	    $phys_m = url2mounted_phys_medium($o, $_->{url});
	    get_standalone_medium($o, $phys_m, $packages, { name => $_->{id} =~ /media=(.*)/ && $1 });
	} elsif ($_->{type} eq 'media_cfg_isos') {
	    my ($dir_url, $iso, $rel_path) = $_->{url} =~ m!(.*)/(.*\.iso):(/.*)! or die "bad media_cfg_isos url $_->{url}";
	    my $dir_medium = url2mounted_phys_medium($o, $dir_url);
	    $dir_medium->{options} =~ s/\bnoauto\b,?//;
	    $phys_m = _iso_phys_media($dir_medium, $iso, $rel_path);
	    push @{$o->{all_hds}{loopbacks}}, $phys_m;
	    ($suppl_CDs, $copy_rpms_on_disk) = get_media_cfg($o, $phys_m, $packages, $_->{selected_names}, $_->{force_rpmsrate});
	} else {
	    log::l("unknown media type $_->{type}, skipping");
	}
    }

    log::l("suppl_CDs=$suppl_CDs copy_rpms_on_disk=$copy_rpms_on_disk");
    $suppl_CDs, $copy_rpms_on_disk;
}

sub adjust_paths_in_urpmi_cfg {
    my ($urpm) = @_;

    require Clone;
    local $urpm->{media} = Clone::clone($urpm->{media});
    foreach my $medium (@{$urpm->{media}}) {
        my $phys_m = $medium->{phys_medium};
        if ($phys_m->{method} eq 'cdrom') {
            $medium->{url} =~ s!^.*?/media/!$phys_m->{url}/!;
        } elsif (member($phys_m->{method}, qw(disk nfs))) {
            # use the real mount point:
            if ($medium->{url} =~ m!/tmp/image(/media)?!) {
                $medium->{url} =~ s!/tmp/image(/media)?!$phys_m->{mntpoint}$phys_m->{rel_path}!;
            } else {
                # just remove $::prefix and we already have the real mount point:
                $medium->{url} =~ s!^$::prefix!!;
            }
        }
    }
    urpm::media::write_config($urpm);
}

sub remove_from_fstab {
    my ($all_hds, $phys_m) = @_;

    @{$all_hds->{nfss}} = grep { $_ != $phys_m } @{$all_hds->{nfss}} if $phys_m->{method} eq 'nfs';
}

sub _find_and_add_to_fstab {
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

    my $phys_m = _url2phys_medium($o, $url);
    $phys_m->{name} = $o_name if $o_name; #- useful for CDs which prompts a name in change_phys_medium
    change_phys_medium($phys_m, $o_rel_file, $o->{packages}) or return;
    $phys_m;
}

sub _url2phys_medium {
    my ($o, $url) = @_;
    my ($method, $path) = $url =~ m!([^:]*)://(.*)! or internal_error("bad url $url");
    if ($method eq 'drakx') {
	my $m = { %{$o->{stage2_phys_medium}}, is_stage2_phys_medium => 1 };
	if ($m->{loopback_device}) {
	    $m->{loopback_device} = _find_and_add_to_fstab($o->{all_hds}, $m->{loopback_device}, 'force_mount');
	}
	$m->{url} .= "/$path";
	$m->{rel_path} .= "/$path" if $m->{device};
	$m = _find_and_add_to_fstab($o->{all_hds}, $m) if $m->{device};
	_phys_medium_is_mounted($m);
	$m;
    } elsif ($method eq 'cdrom') {
	my $cdrom = first(detect_devices::cdroms());
	my $m = { 
	    url => $url, method => $method, fs_type => 'iso9660', device => $cdrom->{device}, 
	    rel_path => "/$path",
	};
	my $m_ = _find_and_add_to_fstab($o->{all_hds}, $m);
	if ($m_->{name}) {
	    #- we need a new phys medium, different from current CD
	    $m_ = _get_phys_media_cdrom($m_, '');
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
	_find_and_add_to_fstab($o->{all_hds}, $m);
    } else {
	{ url => $url, method => $method };
    }
}

sub _get_media_url {
    my ($o, $phys_medium) = @_;
    my $uri;
    if ($phys_medium->{is_suppl}) {
        if (member($phys_medium->{method}, qw(ftp http))) {
            $uri = $phys_medium->{url};
            $uri =~ s!/media$!!;
        } elsif (member($phys_medium->{method}, qw(cdrom nfs))) {
            $uri = "$::prefix/$phys_medium->{mntpoint}";
            my $arch = arch() =~ /i.86/ ? $MDK::Common::System::compat_arch{arch()} : arch();
            $uri .= "/$arch" if -d "$uri/$arch";
        }
    } else {
        $uri = $o->{stage2_phys_medium}{url} =~ m!^(http|ftp)://! && $o->{stage2_phys_medium}{url} ||
          $phys_medium->{method} =~ m!^(ftp|http)://! && $phys_medium->{method} || '/tmp/image';
    }
    $uri;
 }

sub get_media_cfg {
    my ($o, $phys_medium, $packages, $selected_names, $force_rpmsrate) = @_;

    my @media = @{$packages->{media}};

    my ($distribconf);
    if (getAndSaveFile_($phys_medium, 'media_info/media.cfg', '/tmp/media.cfg')) {
	($distribconf) = _parse_media_cfg('/tmp/media.cfg');
    } else {
        die "media.cfg not found";
    }

    my $suppl_CDs = exists $o->{supplmedia} ? $o->{supplmedia} : $distribconf->{suppl} || 0;
    my $deselectionAllowed = $distribconf->{askmedia} || $o->{askmedia} || 0;

    log::l(Data::Dumper->Dump([ $phys_medium ], [ 'phys_medium' ]));
    log::l(Data::Dumper->Dump([ $o->{stage2_phys_medium} ], [ 'stage2_phys_medium' ]));
    my $uri = _get_media_url($o, $phys_medium);
    log::l("adding distrib media from $uri");

    urpm::media::add_distrib_media($packages, undef, $uri, ask_media => undef); #allmedia => 1

    my @new_media = difference2($packages->{media}, \@media);
    _associate_phys_media($o->{all_hds}, $phys_medium, \@new_media);

    select_only_some_media(\@new_media, $selected_names) if defined $selected_names;

    if ($deselectionAllowed && !@{$packages->{media}}) {
	my $allow = _allow_copy_rpms_on_disk($phys_medium, $packages->{media});
	$o->ask_deselect_media__copy_on_disk($packages->{media}, $allow && \$o->{copy_rpms_on_disk}) if $allow || @{$packages->{media}} > 1;
    }

    log::l("get_media_cfg read " . int(@{$packages->{depslist}}) . " headers");

    _get_compsUsers_pl($phys_medium, $force_rpmsrate);

    $suppl_CDs, $o->{copy_rpms_on_disk};
}

sub _get_compsUsers_pl {
    my ($phys_medium, $force_rpmsrate) = @_;
    #- copy latest compssUsers.pl and rpmsrate somewhere locally
    if ($force_rpmsrate || ! -e '/tmp/rpmsrate') {
	getAndSaveFile_($phys_medium, "media_info/rpmsrate", "/tmp/rpmsrate");
    }
    if ($force_rpmsrate || ! -e '/tmp/compssUsers.pl') {
	getAndSaveFile_($phys_medium, "media_info/compssUsers.pl", "/tmp/compssUsers.pl");
    }
}

sub get_standalone_medium {
    my ($in, $phys_m, $packages, $m) = @_;

    add2hash($m, { phys_medium => $phys_m, rel_hdlist => 'media_info/hdlist.cz' });
    local $phys_m->{is_suppl} = 1; # so that _get_media_url() works
    _get_medium($in, $phys_m, $packages, $m);
}

sub _get_medium {
    my ($_in_wait, $phys_m, $packages, $m) = @_;

    !$m->{ignore} or log::l("ignoring packages in $m->{rel_hdlist}"), return;

    my $url = _get_media_url({}, $phys_m);
    log::l("trying '$url'\n");
    urpm::media::add_medium($packages, $m->{name} || 'Supplementary medium', $url, 0) or $packages->{fatal}(10, N("unable to add medium"));
}



#-######################################################################################
#- Post installation RPMS from cdrom only, functions
#-######################################################################################
sub _setup_postinstall_rpms {
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
		$m->{ignore} = 1;
	    }
	}
	my $dest_medium_dir = $dest_dir . '/' . basename($rpmsdir);
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

sub _get_medium_dir {
    my ($phys_m) = @_;
    if (member($phys_m->{method}, qw(ftp http cdrom))) {
        $phys_m->{url};
    } else {
        "$phys_m->{mntpoint}$phys_m->{rel_path}";
    }
}

sub install_urpmi {
    my ($stage2_method, $packages) = @_;

    my @media = @{$packages->{media}};

    log::l("install_urpmi $stage2_method");
    #- clean to avoid opening twice the rpm db.
    delete $packages->{rpmdb};

    my (@cfg, @netrc);
    foreach my $medium (@media) {
	if (!$medium->{ignore}) {
            my ($dir, $removable_device);

	    my $phys_m = $medium->{phys_medium};
            $dir = _get_medium_dir($phys_m);

            if ($phys_m->{method} eq 'iso') {
                $removable_device = $phys_m->{loopback_device}{mntpoint} . $phys_m->{loopback_file};
            }

	    $dir = MDK::Common::File::concat_symlink($dir, $medium->{rpmsdir});

	    my ($qname, $qdir) = ($medium->{fakemedium}, $dir);

	    if (my $u = urpm::download::parse_url_with_login($qdir)) {
		$qdir = sprintf('%s://%s@%s%s', $u->{proto}, $u->{login}, $u->{machine}, $u->{dir});
		push @netrc, sprintf("machine %s login %s password %s\n", $u->{machine}, $u->{login}, $u->{password});
	    }

	    s/(\s)/\\$1/g foreach $qname, $qdir;

	    #- output new urpmi.cfg format here.
	    push @cfg, map { "$_\n" } 
	      "$qname $qdir {", 
		if_($medium->{'key-ids'},
	      "  key-ids: " . $medium->{'key-ids'}),
		if_($removable_device, 
	      "  removable: $removable_device"),
		if_($medium->{update},
	      "  update"), 
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

    if (! -e "/etc/resolv.conf") {
        #- symlink resolv.conf in install root too so that updates and suppl media can be added
	#  (clearly not the right place to do this, but for some reason it just won't work if done
	#  either before or after this function..??
	#  fsckit, I've had enough spaghetti for this round!)
        symlink "$::prefix/etc/resolv.conf", "/etc/resolv.conf";
    }
 
    log::l(sprintf "Installed: %dMB(df), %dMB(rpm)",
	   ($df[0] - $df[1]) / 1024,
	   sum(run_program::rooted_get_stdout($::prefix, 'rpm', '-qa', '--queryformat', '%{size}\n')) / 1024 / 1024) if -x "$::prefix/bin/rpm";
}

1;
