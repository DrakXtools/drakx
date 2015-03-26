package install::any;

use strict;
use feature 'state';

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(addToBeDone);

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use run_program;
use fs::type;
use fs::format;
use fs::any;
use partition_table;
use devices;
use modules;
use detect_devices;
use install::media 'getFile_';
use lang;
use any;
use log;

=head1 SYNOPSYS

Misc installer specific functions

=head1 Functions

=over

=cut

our @advertising_images;

=item drakx_version($o)

Returns DrakX version as stored in C<install/stage2/VERSION> file

=cut

sub drakx_version { 
    my ($o) = @_;

	my $version = cat__(getFile_($o->{stage2_phys_medium}, arch() . "/install/stage2/VERSION"));
	sprintf "DrakX v%s", chomp_($version);
}

#-######################################################################################
#- Functions
#-######################################################################################
sub dont_run_directly_stage2() {
    readlink("/usr/bin/runinstall2") eq "runinstall2.sh";
}

=item is_network_install($o)

Is it a network install?

=cut

sub is_network_install {
    my ($o) = @_;
    member($o->{method}, qw(ftp http nfs));
}

=item spawnShell()

Starts a shell on tty2

=cut

sub spawnShell() {
    return if $::local_install || $::testing;

    my $shellpid_file = '/var/run/drakx_shell.pid';
    return if -e $shellpid_file && -d '/proc/' . chomp_(cat_($shellpid_file));

    if (my $shellpid = fork()) {
        output($shellpid_file, $shellpid);
        return;
    }

    #- why not :pp
    $ENV{DISPLAY} ||= ":0" if $::o->{interactive} eq "gtk";

    local *F;
    sysopen F, "/dev/tty2", 2 or log::l("cannot open /dev/tty2 -- no shell will be provided: $!"), goto cant_spawn;

    open STDIN, "<&F" or goto cant_spawn;
    open STDOUT, ">&F" or goto cant_spawn;
    open STDERR, ">&F" or goto cant_spawn;
    close F;

    print drakx_version($::o), "\n";

    c::setsid();

    ioctl(STDIN, c::TIOCSCTTY(), 0) or warn "could not set new controlling tty: $!";

    my @args; -e '/etc/bashrc' and @args = qw(--rcfile /etc/bashrc);
    foreach (qw(/bin/bash /usr/bin/busybox /bin/sh)) {
        -x $_ or next;
        my $program_name = /busybox/ ? "/bin/sh" : $_;  #- since perl_checker is too dumb
        exec { $_ } $program_name, @args or log::l("exec of $_ failed: $!");
    }

    log::l("cannot open any shell");
cant_spawn:
    c::_exit(1);
}

=item getAvailableSpace($o)

Returns available space

=cut

sub getAvailableSpace {
    my ($o) = @_;
    fs::any::getAvailableSpace($o->{fstab});
}

sub preConfigureTimezone {
    my ($o) = @_;
    require timezone;
   
    #- cannot be done in install cuz' timeconfig %post creates funny things
    add2hash($o->{timezone}, timezone::read()) if $o->{isUpgrade};

    $o->{timezone}{timezone} ||= timezone::bestTimezone($o->{locale}{country});

    my $utc = every { !isFat_or_NTFS($_) } @{$o->{fstab}};
    my $ntp = timezone::ntp_server();
    add2hash_($o->{timezone}, { UTC => $utc, ntp => $ntp });
}

=item ask_suppl_media_method($o)

Enables to add supplementary media

=cut

sub ask_suppl_media_method {
    my ($o) = @_;
    our $suppl_already_asked;

    my $msg = $suppl_already_asked
      ? N("Do you have further supplementary media?")
      : formatAlaTeX(
#-PO: keep the double empty lines between sections, this is formatted a la LaTeX
	    N("The following media have been found and will be used during install: %s.


Do you have a supplementary installation medium to configure?",
	    "\n\n\n" . join(",\n\n", map { "- $_->{name}" . ($_->{ignore} ? " (disabled)" : '') } install::media::allMediums($o->{packages}))));

    my %l = my @l = (
	''      => N("None"),
	'cdrom' => N("CD-ROM"),
	'http'  => N("Network (HTTP)"),
	'ftp'   => N("Network (FTP)"),
	'nfs'   => N("Network (NFS)"),
    );

    $o->ask_from_({ messages => $msg,
		    interactive_help_id => 'add_supplemental_media',
		  },
	[ {
	    val => \my $suppl,
	    list => [ map { $_->[0] } group_by2(@l) ],
	    type => 'list',
	    format => sub { $l{$_[0]} },
	} ],
    );

    $suppl_already_asked = 1;
    $suppl;
}

=item prep_net_suppl_media($o)

If the supplementary media is networked, but not the main one, network
support must be installed and network started.

=cut

sub prep_net_suppl_media {
    my ($o) = @_;

    require network::tools;
    return if our $net_suppl_media_configured && network::tools::has_network_connection();
    $net_suppl_media_configured = 1;

    # needed so that one can install basesystem-minimal before adding suppl network media:
    install::media::update_media($o->{packages});
    require urpm::media;
    urpm::media::configure($o->{packages});

    #- install basesystem-minimal now
    $o->do_pkgs->ensure_is_installed('basesystem-minimal', undef, 1);

    # in case of no network install:
    $o->{net} ||= {};
    require network::netconnect;
    network::netconnect::real_main($o->{net}, $o, $o->{modules_conf});
    require install::interactive;
    install::interactive::upNetwork($o);
    sleep(3);
}

=item ask_url($in, $o_url)

Asks URL of the mirror

=cut

sub ask_url {
    my ($in, $o_url) = @_;

    my $url = $o_url;
    $in->ask_from_({ messages => N("URL of the mirror?"), focus_first => 1 }, [ 
	{ val => \$url,
	  validate => sub { 
	      if ($url =~ m!^(http|ftp)://!) {
		  1;
	      } else {
		  $in->ask_warn('', N("URL must start with ftp:// or http://"));
		  0;
	      }
	  } } ]) && $url;
}

=item ask_mirror($o, $type, $o_url)

Retrieves list of mirrors and offers to pick one

=cut

sub ask_mirror {
    my ($o, $type, $o_url) = @_;
    
    require mirror;

    my $mirrors = eval {
	my $_w = $o->wait_message('', N("Contacting %s web site to get the list of available mirrors...", "Moondrake GNU/Linux"));
	mirror::list($o->{product_id}, $type);
    };
    my $err = $@;
    if (!$mirrors) {
	$o->ask_warn('', N("Failed contacting %s web site to get the list of available mirrors", "Moondrake GNU/Linux") . "\n$err");
	return ask_url($o, $o_url);
    }

    my $give_url = { country => '-', host => 'URL' };

    my $mirror = $o_url ? (find { $_->{url} eq $o_url } @$mirrors) || $give_url 
        #- use current time zone to select best mirror
      : mirror::nearest($o->{timezone}{timezone}, $mirrors);

    $o->ask_from_({ messages => N("Choose a mirror from which to get the packages"),
		    cancel => N("Cancel"),
		}, [ { separator => '|',
		       format => \&mirror::mirror2text,
		       list => [ @$mirrors, $give_url ],
		       val => \$mirror,
		   },
		 ]) or return;

    my $url;
    if ($mirror eq $give_url) {
	$url = ask_url($o, $o_url) or goto &ask_mirror;
    } else {
	$url = $mirror->{url};
    }
    $url =~ s!/main/?$!!;
    log::l("chosen mirror: $url");
    $url;
}

sub ask_suppl_media_url {
    my ($o, $method, $o_url) = @_;

    if (member($method, qw(ftp http))) {
	install::any::ask_mirror($o, 'distrib', $o_url);
    } elsif ($method eq 'cdrom') {
	'cdrom://';
    } elsif ($method eq 'nfs') {
	my ($host, $dir) = $o_url ? $o_url =~ m!nfs://(.*?)(/.*)! : ();
	$o->ask_from_(
	    { title => N("NFS setup"), 
	      messages => N("Please enter the hostname and directory of your NFS media"),
	      focus_first => 1,
	      callbacks => {
		  complete => sub {
		      $host or $o->ask_warn('', N("Hostname missing")), return 1, 0;
		      $dir eq '' || begins_with($dir, '/') or $o->ask_warn('', N("Directory must begin with \"/\"")), return 1, 1;
		      0;
		  },
	      } },
	    [ { label => N("Hostname of the NFS mount ?"), val => \$host }, 
	      { label => N("Directory"), val => \$dir } ],
	) or return;
	$dir =~ s!/+$!!; 
	$dir ||= '/';
	"nfs://$host$dir";
    } else { internal_error("bad method $method") }
}


=item selectSupplMedia($o)

Offers to add a supplementary media. If yes, ask which mirror to use, ...

=cut

sub selectSupplMedia {
    my ($o) = @_;
    my $url;

  ask_method:
    my $method = ask_suppl_media_method($o) or return;

    #- configure network if needed
    if (!scalar keys %{$o->{net}{ifcfg}} && $method !~ /^(?:cdrom|disk)/ && !$::local_install) {
	prep_net_suppl_media($o);
    }

  ask_url:
    $url = ask_suppl_media_url($o, $method, $url) or goto ask_method;

    my $phys_medium = install::media::url2mounted_phys_medium($o, $url, undef, N("Supplementary")) or $o->ask_warn('', formatError($@)), goto ask_url;
    $phys_medium->{is_suppl} = 1;
    $phys_medium->{unknown_CD} = 1;

    my $arch = $o->{product_id}{arch};
    my $field = $phys_medium->{device} ? 'rel_path' : 'url';
    my $val = $phys_medium->{$field};
    my $val0 = $val =~ m!^(.*?)(/media)?/?$! && "$1/media";
    my $val2 = $val =~ m!^(.*?)(/\Q$arch\E)?(/media)?/?$! && "$1/$arch/media";

    foreach (uniq($val0, $val, $val2)) {
	log::l("trying with $field set to $_");
	$phys_medium->{$field} = $_;

	#- first, try to find a media.cfg file
	eval { install::media::get_media_cfg($o, $phys_medium, $o->{packages}, undef, 'force_rpmsrate') };
	if (!$@) {
	    delete $phys_medium->{unknown_CD}; #- we have a known CD now
	    return 1;
	}
    }
    #- restore it
    $phys_medium->{$field} = $val;

    #- try using media_info/hdlist.cz
    my $medium_id = int(@{$o->{packages}{media}});
    eval { install::media::get_standalone_medium($o, $phys_medium, $o->{packages}, { name => "Supplementary media $medium_id" }) };
    if (!$@) {
	log::l("read suppl hdlist (via $method)");
	delete $phys_medium->{unknown_CD}; #- we have a known CD now
	return 1;
    }

    install::media::umount_phys_medium($phys_medium);
    install::media::remove_from_fstab($o->{all_hds}, $phys_medium);
    $o->ask_warn('', N("Can't find a package list file on this mirror. Make sure the location is correct."));
    goto ask_url;
}

=item load_rate_files($o)

Loads the package rates file (C<rpmsrate>) as well as the C<compssUsers.pl>
file which contains the package groups GUI.

Both files came from the C<meta-task> package.

=cut

sub load_rate_files {
    my ($o) = @_;
    #- must be done after getProvides

    require pkgs;
    pkgs::read_rpmsrate($o->{packages}, $o->{rpmsrate_flags_chosen}, '/tmp/rpmsrate', $o->{match_all_hardware});

    ($o->{compssUsers}, $o->{gtk_display_compssUsers}) = install::pkgs::readCompssUsers('/tmp/compssUsers.pl');

    defined $o->{compssUsers} or die "Can't read compssUsers.pl file, aborting installation\n";
}

sub _main_medium() { N("Main Release") }

sub _contrib_medium() { N("Contrib Release") }

sub _nonfree_medium() { N("Non-free Release") }

# FIXME: move me in ../any.pm or in harddrake::*, might be needed by rpmdrake/harddrake:
sub is_firmware_needed_ {
    my ($o) = @_;
    require list_firmwares;
    my @l = map { $_->{driver} } detect_devices::probeall();
    my @need = intersection(\@l, \@list_firmwares::modules_with_nonfree_firmware);
    log::l("the following driver(s) need nonfree firmware(s): " . join(', ', @need)) if @need;

    require pkgs;
    my @xpkgs = pkgs::detect_graphical_drivers($o->do_pkgs);
    log::l("the following nonfree firmware(s) are needed for X.org: " . join(', ', @xpkgs)) if @xpkgs;

    my $need_microcode = detect_devices::hasCPUMicrocode();
    log::l("nonfree firmware is needed for the CPU (microcode)") if $need_microcode;

    @need || @xpkgs || $need_microcode;
}

=item is_firmware_needed($o)

Is a firmware needed by some HW?

=cut

sub is_firmware_needed {
    my ($o) = @_;
    return 0 if $::o->{match_all_hardware};
    state $res;
    $res = is_firmware_needed_($o) if !defined $res;
    $res;
}

sub msg_if_firmware_needed {
    my ($o) = @_;
    return if !is_firmware_needed($o);
    join("\n",
	 # FIXME: actually can be proprietary drivers (same medium eventually):
         N("Some hardware on your machine needs some non free firmwares in order for the free software drivers to work."),
         N("You should enable \"%s\"", _nonfree_medium()),
     );
}

=item enable_nonfree_media($medium)

Enable a disabled Nonfree medium.

=cut

sub enable_nonfree_media {
    my ($medium) = @_;
    return if $medium->{name} !~ /Nonfree/ || !$medium->{ignore};
    log::l("preselecting $medium->{name}");
    $medium->{temp_enabled} = 1;
}

=item media_screen($o)

Lists available media with their status (enabled/disabled).
Suggests to enable Nonfree media if needed.

=cut

sub media_screen {
    my ($o) = @_;

    my $urpm = $o->{packages};
    # FIXME:
    # - nice info
    # - ignore already failed media (such as 32bit media on NFS)
    # - detect if non-free/tainted were selected previously / are now needed
    #   rpm -qa |grep tainted/non-free + check for kmod with firmwares
    # - use red color in that case (gtk+ version? interactive::gtk version?)
    # - present media as trees (eg 3 main branches (main/contrib/nonfree and sub medium below (release/updates/...)
    # - enable to add media from the media screen
    # - use keywords (backports,testing,testing,sources) to blacklist
    # - introduce 'mandatory' keyword for guessing media that can *not* be disabled
    my %descriptions = (
        'Main Release' => N("\"%s\" contains the various pieces of the systems and its applications.", _main_medium()),
        'Contrib Release' => N("\"%s\" contains software that's not officially supported and might not receive the same level of maintenance.", _contrib_medium()),
        'Non-free Release' => N("\"%s\" contains non free software.\n", _nonfree_medium()) .
          N("It also contains firmware needed for certain devices to operate (eg: some ATI/AMD graphic cards, some network cards, some RAID cards, ...)"),
    );

    $o->ask_from_({ messages => join("\n",
                                      N("Here you can enable more media if you want."),
                                      msg_if_firmware_needed($o)
                                  ),
		    interactive_help_id => 'media_selection',
                     focus_first => sub { 1 } }, [ 
        map {
            my $medium = $_;
	    $medium->{temp_enabled} = !$medium->{ignore};
	    +{
                val => \$medium->{temp_enabled}, type => 'bool', text => $medium->{name},
                # 'Main Release' cannot be unselected:
                disabled => sub { $medium->{name} eq 'Main Release' },
                format => sub { $descriptions{$_[0]} || translate(%descriptions) },
            };
        } grep { $_->{name} !~ /Debug|Testing|Sources|Backports/ } @{$urpm->{media}},
    ]);


    # is there some media to enable?
    my $todo;
    foreach my $medium (@{$urpm->{media}}) {
        if ($medium->{temp_enabled} == $medium->{ignore}) {
            $medium->{ignore} = !$medium->{temp_enabled};
            if (!$medium->{ignore}) {
		delete $medium->{ignore};
		log::l("Medium '$medium->{name}' needs to be updated to be usable");
		urpm::media::select_media($urpm, $medium->{name});
		$todo = 1;
	    }
	}
	delete $medium->{temp_enabled};
    }
    return if !$todo;
    urpm::media::update_media($urpm, allow_failures => 1, nolock => 1, noclean => 1,
			      callback => \&urpm::download::sync_logger
			     );
}

=item setPackages($o)

=over 4

=item * Initialize urpmi

=item * Retrieves media.cfg

=item * Offers to add supplementary media (according to the install method)

=item * Offers to enable some disabled media

=item * Ensure we have a kernel and basesystem

=item * Flags package rates

=item * Select default packages according to the computer

=back

=cut

sub setPackages {
    my ($o) = @_;

    my $urpm;
    require install::pkgs;
    {
	#  (update_media will open rpmdb for listing existing pubkeys,
	$urpm = $o->{packages} = install::pkgs::empty_packages($o->{keep_unrequested_dependencies});
	
	my $media = $o->{media} || [ { type => 'media_cfg', url => 'drakx://media' } ];
	my ($suppl_method, $copy_rpms_on_disk);

	install::pkgs::start_pushing_error();
    	($suppl_method, $copy_rpms_on_disk) = install::media::get_media($o, $media, $urpm);

	if ($suppl_method) {
	    1 while $o->selectSupplMedia;
	}
	install::media::update_media($urpm);
	install::pkgs::popup_errors();

        install::pkgs::start_pushing_error();
	# should we really use this? merged from mageia for easier maintenance..
        media_screen($o) if !$::auto_install;
        my @choosen_media = map { $_->{name} } grep { !$_->{ignore} } @{$urpm->{media}};
        log::l("choosen media: ", join(', ', @choosen_media));
        die "no choosen media" if !@choosen_media;

        # actually read synthesis now we have all the ones we want:
        require urpm::media;
        urpm::media::configure($urpm);

        install::pkgs::popup_errors();

        install::media::adjust_paths_in_urpmi_cfg($urpm);
        log::l('urpmi completely set up');

	#- open rpm db according to right mode needed
	$urpm->{rpmdb} ||= install::pkgs::rpmDbOpen('rebuild_if_needed');

	{
	    my $_wait = $o->wait_message('', N("Looking at packages already installed..."));
	    install::pkgs::selectPackagesAlreadyInstalled($urpm);
	}

        remove_package_for_upgrade($o);

	mark_skipped_packages($o);

	#- always try to select basic kernel (else on upgrade, kernel will never be updated provided a kernel is already
	#- installed and provides what is necessary).
	my $kernel_pkg = install::pkgs::bestKernelPackage($urpm, $o->{match_all_hardware});
	install::pkgs::selectPackage($urpm, $kernel_pkg, 1);
	if ($o->{isUpgrade} && $urpm->{sizes}{dkms} && $kernel_pkg =~ /(.*)-latest/) {
	    my $devel_kernel_pkg = "$1-devel-latest";
	    log::l("selecting $devel_kernel_pkg (since dkms was installed)");
	    install::pkgs::select_by_package_names($urpm, [ $devel_kernel_pkg ], 1);
	}

	install::pkgs::select_by_package_names_or_die($urpm, ['basesystem'], 1);

	my $rpmsrate_flags_was_chosen = $o->{rpmsrate_flags_chosen};

	put_in_hash($o->{rpmsrate_flags_chosen} ||= {}, rpmsrate_always_flags($o)); #- must be done before pkgs::read_rpmsrate()
	load_rate_files($o);

	install::media::copy_rpms_on_disk($o) if $copy_rpms_on_disk;

	set_rpmsrate_default_category_flags($o, $rpmsrate_flags_was_chosen);

	push @{$o->{default_packages}}, default_packages($o);
	select_default_packages($o);
    }

    if ($o->{isUpgrade}) {
	{
	    my $_w = $o->wait_message('', N("Finding packages to upgrade..."));
	    install::pkgs::selectPackagesToUpgrade($urpm);
	}
	if ($o->{packages}{sizes}{'kdebase-progs'}) {
	    log::l("selecting task-kde (since kdebase-progs was installed)");
	    install::pkgs::select_by_package_names($o->{packages}, ['task-kde']);
	}
    }
}

=item remove_package_for_upgrade($o)

Removes packages that must be uninstalled prior to upgrade

=cut

sub remove_package_for_upgrade {
    my ($o) = @_;
    my $extension = $o->{upgrade_by_removing_pkgs_matching};

    return if !$extension;

    my $time = time();
    my ($_w, $wait_message) = $o->wait_message_with_progress_bar;
    $wait_message->(N("Removing packages prior to upgrade..."));
    my ($current, $total);
    my $callback = sub {
        my (undef, $type, $_id, $subtype, $amount) = @_;
        if ($type eq 'user') {
            ($current, $total) = (0, $amount);
        } elsif ($type eq 'uninst' && $subtype eq 'stop') {
            $wait_message->('', $current++, $total);
        }
    };
    push @{$o->{default_packages}}, install::pkgs::upgrade_by_removing_pkgs($o->{packages}, $callback, $extension, $o->{isUpgrade});
    log::l("Removing packages took: ", formatTimeRaw(time() - $time));
}

=item count_files($dir)

Returns the number of files in $dir

=cut

sub count_files {
    my ($dir) = @_;
    -d $dir or return 0;
    opendir my $dh, $dir or return 0;
    my @list = grep { !/^\.\.?$/ } readdir $dh;
    closedir $dh;
    my $c = 0;
    foreach my $n (@list) {
	my $p = "$dir/$n";
	if (-d $p) { $c += count_files($p) } else { ++$c }
    }
    $c;
}

sub cp_with_progress {
    my $wait_message = shift;
    my $_current = shift;
    my $total = shift;
    my $dest = pop @_;
    cp_with_progress_({ keep_special => 1 }, $wait_message, $total, \@_, $dest);
}
sub cp_with_progress_ {
    my ($options, $wait_message, $total, $list, $dest) = @_;
    @$list or return;
    @$list == 1 || -d $dest or die "cp: copying multiple files, but last argument ($dest) is not a directory\n";

    -d $dest or $dest = dirname($dest);
    _cp_with_progress($options, $wait_message, 0, $total, $list, $dest);
}
sub _cp_with_progress {
    my ($options, $wait_message, $current, $total, $list, $dest) = @_;

    foreach my $src (@$list) {
	my $dest = $dest;
	-d $dest and $dest .= '/' . basename($src);

	unlink $dest;

	if (-l $src && $options->{keep_special}) {
	    unless (symlink(readlink($src) || die("readlink failed: $!"), $dest)) {
		warn "symlink: can't create symlink $dest: $!\n";
	    }
	} elsif (-d $src) {
	    -d $dest or mkdir $dest, (stat($src))[2] or die "mkdir: can't create directory $dest: $!\n";
	    _cp_with_progress($options, $wait_message, $current, $total, [ glob_($src) ], $dest);
	} else {
	    open(my $F, $src) or die "can't open $src for reading: $!\n";
	    open(my $G, ">", $dest) or die "can't cp to file $dest: $!\n";
	    local $/ = \4096;
	    local $_; while (<$F>) { print $G $_ }
	    chmod((stat($src))[2], $dest);
	    $wait_message->('', ++$current, $total);
	}
    }
    1;
}

sub set_rpmsrate_default_category_flags {
    my ($o, $rpmsrate_flags_was_chosen) = @_;

    #- if no cleaning needed, populate by default, clean is used for second or more call to this function.
    if ($::auto_install && ($o->{rpmsrate_flags_chosen} || {})->{CAT_ALL}) {
	$o->{rpmsrate_flags_chosen}{"CAT_$_"} = 1 foreach map { @{$_->{flags}} } @{$o->{compssUsers}};
    }
    if (!$rpmsrate_flags_was_chosen && !$o->{isUpgrade}) {
	#- use default selection seen in compssUsers directly.
	$_->{selected} = $_->{default_selected} foreach @{$o->{compssUsers}};
	set_rpmsrate_category_flags($o, $o->{compssUsers});
    }
}

sub set_rpmsrate_category_flags {
    my ($o, $compssUsers) = @_;

    $o->{rpmsrate_flags_chosen}{$_} = 0 foreach grep { /^CAT_/ } keys %{$o->{rpmsrate_flags_chosen}};
    $o->{rpmsrate_flags_chosen}{"CAT_$_"} = 1 foreach map { @{$_->{flags}} } grep { $_->{selected} } @$compssUsers;
    $o->{rpmsrate_flags_chosen}{CAT_SYSTEM} = 1;
    $o->{rpmsrate_flags_chosen}{CAT_MINIMAL_DOCS} = 1;
}


sub rpmsrate_always_flags {
    my ($o) = @_;

    my $rpmsrate_flags_chosen = {};
    $rpmsrate_flags_chosen->{qq(META_CLASS"$o->{meta_class}")} = 1;
    $rpmsrate_flags_chosen->{uc($_)} = 1 foreach grep { $o->{match_all_hardware} || detect_devices::probe_category("multimedia/$_") } modules::sub_categories('multimedia');
    $rpmsrate_flags_chosen->{uc($_)} = 1 foreach detect_devices::probe_name('Flag');
    $rpmsrate_flags_chosen->{UTF8} = $o->{locale}{utf8};
    $rpmsrate_flags_chosen->{BURNER} = 1 if $o->{match_all_hardware} || detect_devices::burners();
    $rpmsrate_flags_chosen->{DVD} = 1 if $o->{match_all_hardware} || detect_devices::dvdroms();
    $rpmsrate_flags_chosen->{USB} = 1 if $o->{match_all_hardware} || $o->{modules_conf}->get_probeall("usb-interface");
    $rpmsrate_flags_chosen->{PCMCIA} = 1 if $o->{match_all_hardware} || detect_devices::hasPCMCIA();
    $rpmsrate_flags_chosen->{HIGH_SECURITY} = 1 if $o->{security} > 1;
    $rpmsrate_flags_chosen->{BIGMEM} = 1 if detect_devices::BIGMEM();
    $rpmsrate_flags_chosen->{SMP} = 1 if $o->{match_all_hardware} || detect_devices::hasSMP();
    if (!$o->{match_all_hardware} && !defined $o->{compssListLevel} && detect_devices::need_light_desktop()) {
        log::l("activation light desktop mode (for low resources systems or netbook/nettops)");
        $rpmsrate_flags_chosen->{LIGHT} = 1;
    }
    # FIXME: to be updated!!!
    $rpmsrate_flags_chosen->{'3D'} = 1 if
      $o->{match_all_hardware} ||
      detect_devices::matching_desc__regexp('Matrox.* G[245][05]0') ||
      detect_devices::matching_desc__regexp('Rage X[CL]') ||
      detect_devices::matching_desc__regexp('3D Rage (?:LT|Pro)') ||
      detect_devices::matching_desc__regexp('Voodoo [35]') ||
      detect_devices::matching_desc__regexp('Voodoo Banshee') ||
      detect_devices::matching_desc__regexp('8281[05].* CGC') ||
      detect_devices::matching_desc__regexp('Rage 128') ||
      detect_devices::matching_desc__regexp('Radeon ') || #- all Radeon card are now 3D with 4.3.0
      detect_devices::matching_desc__regexp('[nN]Vidia.*T[nN]T2') || #- TNT2 cards
      detect_devices::matching_desc__regexp('[nN][vV]idia.*NV[56]') ||
      detect_devices::matching_desc__regexp('[nN][vV]idia.*Vanta') ||
      detect_devices::matching_desc__regexp('[nN][vV]idia.*[gG]e[fF]orce') || #- GeForce cards
      detect_devices::matching_desc__regexp('[nN][vV]idia.*NV1[15]') ||
      detect_devices::matching_desc__regexp('[nN][vV]idia.*Quadro');

    foreach (lang::langsLANGUAGE($o->{locale}{langs})) {
	$rpmsrate_flags_chosen->{qq(LOCALES"$_")} = 1;
    }
    $rpmsrate_flags_chosen->{'CHARSET"' . lang::l2charset($o->{locale}{lang}) . '"'} = 1;

    $rpmsrate_flags_chosen;
}

=item default_packages($o)

Selects default packages to install according to configuration (FS, HW, ...)

=cut

sub default_packages {
    my ($o) = @_;
    my @l;
    sub add_n_log {
       my ($reason, @packages) = @_;
       if (@packages) {
          log::l("selecting " . join(',', @packages) . " because of $reason");
          push @l, @packages;
       }
    }

    add_n_log("/proc/cmdline=~/brltty=/", "brltty") if cat_("/proc/cmdline") =~ /brltty=/;
    add_n_log("method==nfs", "nfs-utils") if $o->{method} eq "nfs";
    add_n_log("have RAID", "mdadm") if !is_empty_array_ref($o->{all_hds}{raids});
    add_n_log("have LVM", "lvm2") if !is_empty_array_ref($o->{all_hds}{lvms});
    add_n_log("have crypted DM", "cryptsetup") if !is_empty_array_ref($o->{all_hds}{dmcrypts});
    add_n_log("some disks are fake RAID", qw(mdadm dmraid)) if any { fs::type::is_dmraid($_) } @{$o->{all_hds}{hds}};
    add_n_log("CPU needs microcode", "microcode_ctl") if detect_devices::hasCPUMicrocode();
    add_n_log("either CPU or GFX needs firmware", qw(kernel-firmware-nonfree radeon-firmware)) if is_firmware_needed($o);
    add_n_log("CPU needs cpupower", 'cpupower') if detect_devices::hasCPUFreq();
    add_n_log("APM support needed", 'apmd') if -e "/proc/apm";
    add_n_log("needed by hardware", detect_devices::probe_name('Pkg'));
    my @ltmp = map { $_->{BOOTPROTO} eq 'dhcp' ? $_->{DHCP_CLIENT} || 'dhcpcd' : () } values %{$o->{net}{ifcfg}};
    add_n_log("needed by networking", @ltmp) if @ltmp;
    # will get auto selected at summary stage for bootloader:
    add_n_log("needed later at summary stage", qw(acpi acpid mandriva-gfxboot-theme));
    # will get auto selected at summary stage for firewall:
    add_n_log("needed for firewall/security", qw(shorewall shorewall-ipv6 mandi-ifw));
    # only needed for CDs/DVDs installations:
    add_n_log("method='cdrom'", 'perl-Hal-Cdroms') if $o->{method} eq 'cdrom';
    add_n_log("needed for VMware hypervisor", 'open-vm-tools') if detect_devices::is_vmware();
    # we only support grub2-efi on UEFI:
    add_n_log("needed for UEFI boot", 'grub2-efi') if is_uefi();

    my $dmi_BIOS = detect_devices::dmidecode_category('BIOS');
    my $dmi_Base_Board = detect_devices::dmidecode_category('Base Board');
    if ($dmi_BIOS->{Vendor} eq 'COMPAL' && $dmi_BIOS->{Characteristics} =~ /Function key-initiated network boot is supported/
          || $dmi_Base_Board->{Manufacturer} =~ /^ACER/ && $dmi_Base_Board->{'Product Name'} =~ /TravelMate 610/) {
	#- FIXME : append correct options (wireless, ...)
	modules::append_to_modules_loaded_at_startup_for_all_kernels('acerhk');
    }

    add_n_log("some fs is mounted with quota options", 'quota') if any { $_->{options} =~ /usrquota|grpquota/ } @{$o->{fstab}};
    @ltmp = uniq(grep { $_ } map { fs::format::package_needed_for_partition_type($_) } @{$o->{fstab}});
    add_n_log("needed by some fs", @ltmp) if @ltmp;
    add_n_log("some fs is NTFS-3G", 'ntfs-3g') if any { $_->{fs_type} eq 'ntfs-3g' } @{$o->{fstab}};
    add_n_log("some fs is btrfs", 'btrfs-progs') if any { $_->{fs_type} eq 'btrfs' } @{$o->{fstab}};

    # handle locales with specified scripting:
    my @languages = map { s/\@.*//; $_ } lang::langsLANGUAGE($o->{locale}{langs});
    my @locale_pkgs = map { URPM::packages_providing($o->{packages}, 'locales-' . $_) } @languages;
    unshift @l, uniq(map { $_->name } @locale_pkgs);

    uniq(@l);
}

sub mark_skipped_packages {
    my ($o) = @_;
    install::pkgs::skip_packages($o->{packages}, $o->{skipped_packages}) if $o->{skipped_packages};
}

sub select_default_packages {
    my ($o) = @_;
    install::pkgs::select_by_package_names($o->{packages}, $o->{default_packages});
}

sub unselectMostPackages {
    my ($o) = @_;
    install::pkgs::unselectAllPackages($o->{packages});
    select_default_packages($o);
}

sub warnAboutRemovedPackages {
    my ($o, $packages) = @_;
    my @removedPackages = keys %{$packages->{state}{ask_remove} || {}} or return;
    if (!$o->ask_yesorno('', 
formatAlaTeX(
             #-PO: keep the double empty lines between sections, this is formatted a la LaTeX
             N("The following packages will be removed to allow upgrading your system: %s


Do you really want to remove these packages?
", join(", ", @removedPackages))), 1)) {
	$packages->{state}{ask_remove} = {};
    }
}

sub addToBeDone(&$) {
    my ($f, $step) = @_;

    return &$f() if $::o->{steps}{$step}{done};

    push @{$::o->{steps}{$step}{toBeDone}}, $f;
}

sub set_authentication {
    my ($o) = @_;

    my $when_network_is_up = sub {
	my ($f) = @_;
	#- defer running xxx - no network yet
	addToBeDone {
	    require install::steps;
	    install::steps::upNetwork($o, 'pppAvoided');
	    $f->();
	} 'configureNetwork';
    };
    require authentication;
    authentication::set($o, $o->{net}, $o->{authentication} ||= {}, $when_network_is_up);
}

#-###############################################################################
#- kde stuff
#-###############################################################################
sub kdemove_desktop_file {
    my ($prefix) = @_;
    my @toMove = qw(doc.kdelnk news.kdelnk updates.kdelnk home.kdelnk printer.kdelnk floppy.kdelnk cdrom.kdelnk FLOPPY.kdelnk CDROM.kdelnk);

    #- remove any existing save in Trash of each user and
    #- move appropriate file there after an upgrade.
    foreach my $dir (grep { -d $_ } list_skels($prefix, 'Desktop')) {
	renamef("$dir/$_", "$dir/Trash/$_") 
	  foreach grep { -e "$dir/$_" } @toMove, grep { /\.rpmorig$/ } all($dir);
    }
}


#-###############################################################################
#- auto_install stuff
#-###############################################################################
sub auto_inst_file() { "$::prefix/root/drakx/auto_inst.cfg.pl" }

sub report_bug() {
    any::report_bug('auto_inst' => g_auto_install('', 1));
}

sub g_auto_install {
    my ($b_replay, $b_respect_privacy) = @_;
    my $o = {};

    require install::pkgs;
    $o->{default_packages} = install::pkgs::selected_leaves($::o->{packages});

    my @fields = qw(fs_type hd level mntpoint options parts size VG_name);
    $o->{partitions} = [ map { 
	my %l; @l{@fields} = @$_{@fields}; \%l;
    } grep { 
	$_->{mntpoint} && fs::format::known_type($_);
    } @{$::o->{fstab}} ];
    
    exists $::o->{$_} and $o->{$_} = $::o->{$_} foreach qw(locale authentication mouse net timezone superuser keyboard users partitioning isUpgrade manualFstab nomouseprobe crypto security security_user autoExitInstall X services postInstall postInstallNonRooted); #- TODO modules bootloader 

    local $o->{partitioning}{auto_allocate} = !$b_replay;
    $o->{autoExitInstall} = !$b_replay;
    $o->{interactiveSteps} = [ 'doPartitionDisks', 'formatPartitions' ] if $b_replay;

    #- deep copy because we're modifying it below
    $o->{users} = $b_respect_privacy ? [] : [ @{$o->{users} || []} ];

    my @user_info_to_remove = (
	if_($b_respect_privacy, qw(realname pw)), 
	qw(oldu oldg password password2),
    );
    $_ = { %{$_ || {}} }, delete @$_{@user_info_to_remove} foreach $o->{superuser}, @{$o->{users} || []};

    if ($b_respect_privacy && $o->{net}) {
	if (my $type = $o->{net}{type}) {
	    my @net_type_to_remove = qw(passwd login phone_in phone_out);
	    $_ = { %{$_ || {}} }, delete @$_{@net_type_to_remove} foreach $o->{net}{$type};
	}
    }
    my $warn_privacy = $b_respect_privacy ? "!! This file has been simplified to respect privacy when reporting problems.
# You should use /root/drakx/auto_inst.cfg.pl instead !!\n#" : '';
    
    require Data::Dumper;
    my $str = join('', 
"#!/usr/bin/perl -cw
# $warn_privacy
# You should check the syntax of this file before using it in an auto-install.
# You can do this with 'perl -cw auto_inst.cfg.pl' or by executing this file
# (note the '#!/usr/bin/perl -cw' on the first line).
", Data::Dumper->Dump([$o], ['$o']));
    $str =~ s/ {8}/\t/g; #- replace all 8 space char by only one tabulation, this reduces file size so much :-)
    $str;
}

sub getAndSaveAutoInstallFloppies {
    my ($o, $replay) = @_;
    my $name = ($replay ? 'replay' : 'auto') . '_install';
    my $dest_dir = "$::prefix/root/drakx";

    eval { modules::load('loop') };

	my $mountdir = "$::prefix/root/aif-mount"; -d $mountdir or mkdir $mountdir, 0755;
	my $param = 'kickstart=floppy ' . generate_automatic_stage1_params($o);

	my $img = install::media::getAndSaveInstallFloppies($o, $dest_dir, $name) or return;

	{
	    my $dev = devices::set_loop($img) or log::l("couldn't set loopback device"), return;
	    find { eval { fs::mount::mount($dev, $mountdir, $_, 0); 1 } } qw(ext2 vfat) or return;

	    if (-e "$mountdir/menu.lst") {
		# hd_grub boot disk is different than others
		substInFile {
		    s/^(\s*timeout.*)/timeout 1/;
		    s/\bautomatic=method:disk/$param/;
		} "$mountdir/menu.lst";
	    } elsif (-e "$mountdir/syslinux.cfg") {
		#- make room first
		unlink "$mountdir/help.msg", "$mountdir/boot.msg";

		substInFile { 
		    s/timeout.*/$replay ? 'timeout 1' : ''/e;
		    s/^(\s*append)/$1 $param/; 
		} "$mountdir/syslinux.cfg";

		output "$mountdir/boot.msg", $replay ? '' : "\n0c" .
"!! If you press enter, an auto-install is going to start.
   All data on this computer is going to be lost,
   including any Windows partitions !!
" . "07\n";
	    }

	    {
		local $o->{partitioning}{clearall} = !$replay;
		eval { output("$mountdir/auto_inst.cfg", g_auto_install($replay)) };
		$@ and log::l("Warning: <", formatError($@), ">");
	    }
	
	    fs::mount::umount($mountdir);
	    devices::del_loop($dev);
	}
	rmdir $mountdir;
	$img;
}


sub g_default_packages {
    my ($o) = @_;

    my ($_h, $file) = media_browser($o, 'save', 'package_list.pl') or return;
    output($file, selected_leaves_pl($o));
}

sub selected_leaves_pl {
    my ($o) = @_;

    require Data::Dumper;
    my $str = Data::Dumper->Dump([ { default_packages => install::pkgs::selected_leaves($o->{packages}) } ], ['$o']);
    $str =~ s/ {8}/\t/g;

    "# You should always check the syntax with 'perl -cw auto_inst.cfg.pl'\n" .
      "# before testing.  To use it, boot with ``linux defcfg=floppy''\n" .
      $str;
}

sub loadO {
    my ($O, $f) = @_; $f ||= auto_inst_file();
    if ($f =~ /^(floppy|patch)$/) {
	my $f = $f eq "floppy" ? 'auto_inst.cfg' : "patch";
	my $o;
	foreach (removable_media__early_in_install()) {
            my $dev = devices::make($_->{device});
            foreach my $fs (qw(ext2 vfat)) {
                eval { fs::mount::mount($dev, '/mnt', $fs, 'readonly'); 1 } or next;
		if (my $abs_f = find { -e $_ } "/mnt/$f", "/mnt/$f.pl") {
		    $o = loadO_($O, $abs_f);
		}
		fs::mount::umount("/mnt");
		goto found if $o;
            }
	}
	die "Could not find $f";
      found:
	modules::unload(qw(vfat fat));
	$o;
    } else {
	loadO_($O, $f);
    }
}

sub loadO_ {
    my ($O, $f) = @_; 

    my $o;
    {
	my $fh;
	if (ref $f) {
	    $fh = $f;
	} else {
	    -e "$f.pl" and $f .= ".pl" unless -e $f;

	    $fh = -e $f ? common::open_file($f) : getFile_($O->{stage2_phys_medium}, $f) || die N("Error reading file %s", $f);
	}
	my $s = cat__($fh);
	close $fh;
	{
	    no strict;
	    eval $s;
	    $@ and die;
	}
	$O and add2hash_($o ||= {}, $O);
    }
    $O and bless $o, ref $O;

    handle_old_auto_install_format($o);

    $o;
}

sub handle_old_auto_install_format {
    my ($o) = @_;

    #- handle backward compatibility for things that changed
    foreach (@{$o->{partitions} || []}, @{$o->{manualFstab} || []}) {
	if (my $type = delete $_->{type}) {
	    if ($type =~ /^(0x)?(\d*)$/) {
		fs::type::set_pt_type($_, $type);
	    } else {
		fs::type::set_fs_type($_, $type);
	    }
	}
    }
    #- {rpmsrate_flags_chosen} was called {compssUsersChoice}
    if (my $rpmsrate_flags_chosen = delete $o->{compssUsersChoice}) {
	$o->{rpmsrate_flags_chosen} = $rpmsrate_flags_chosen;
    }
    #- compssUsers flags are now named CAT_XXX
    if ($o->{rpmsrate_flags_chosen} &&
	! any { /^CAT_/ } keys %{$o->{rpmsrate_flags_chosen}}) {
	#- we don't really know if this is needed for compatibility, but it won't hurt :)
	foreach (keys %{$o->{rpmsrate_flags_chosen}}) {
	    $o->{rpmsrate_flags_chosen}{"CAT_$_"} = $o->{rpmsrate_flags_chosen}{$_};
	}
	#- it used to be always selected
	$o->{rpmsrate_flags_chosen}{CAT_SYSTEM} = 1;
    }
    if ($o->{updates} && $o->{updates}{mirror}) {
	$o->{updates}{url} = delete $o->{updates}{mirror};
    }

    #- backward compatibility for network fields
    exists $o->{intf} and $o->{net}{ifcfg} = delete $o->{intf};
    exists $o->{netcnx}{type} and $o->{net}{type} = delete $o->{netcnx}{type};
    exists $o->{netc}{NET_INTERFACE} and $o->{net}{net_interface} = delete $o->{netc}{NET_INTERFACE};
    my %netc_translation = (
			    resolv => [ qw(dnsServer dnsServer2 dnsServer3 DOMAINNAME DOMAINNAME2 DOMAINNAME3) ],
			    network => [ qw(NETWORKING FORWARD_IPV4 NETWORKING_IPV6 HOSTNAME GATEWAY GATEWAYDEV NISDOMAIN) ],
			    auth => [ qw(LDAPDOMAIN WINDOMAIN) ],
			   );
    foreach my $dest (keys %netc_translation) {
	exists $o->{netc}{$_} and $o->{net}{$dest}{$_} = delete $o->{netc}{$_} foreach @{$netc_translation{$dest}};
    }
    delete @$o{qw(netc netcnx)};

    $o;
}

sub generate_automatic_stage1_params {
    my ($o) = @_;

    my $method = $o->{method};
    my @ks;

    if ($o->{method} eq 'http') {
	$ENV{URLPREFIX} =~ m!(http|ftp)://([^/:]+)(.*)! or die;
	$method = $1; #- in stage1, FTP via HTTP proxy is available through FTP config, not HTTP
	@ks = (server => $2, directory => $3);
    } elsif ($o->{method} eq 'ftp') {
	require install::ftp;
	my @l = install::ftp::parse_ftp_url($ENV{URLPREFIX});
	@ks = (server => $l[0], directory => $l[1], user => $l[2], pass => $l[3]);
    } elsif ($o->{method} eq 'nfs') {
	cat_("/proc/mounts") =~ m|(\S+):(\S+)\s+/tmp/media| or internal_error("cannot find nfsimage");
	@ks = (server => $1, directory => $2);
    }
    @ks = (method => $method, @ks);

    if (is_network_install($o)) {
	if ($ENV{PROXY}) {
	    push @ks, proxy_host => $ENV{PROXY}, proxy_port => $ENV{PROXYPORT};
	}
	my $intf = first(values %{$o->{net}{ifcfg}});
	push @ks, interface => $intf->{DEVICE};
	if ($intf->{BOOTPROTO} eq 'dhcp') {
	    push @ks, network => 'dhcp';
	} else {
	    push @ks, network => 'static', ip => $intf->{IPADDR}, netmask => $intf->{NETMASK}, gateway => $o->{net}{network}{GATEWAY};
	    require network::network;
	    if (my @dnss = network::network::dnsServers($o->{net})) {
		push @ks, dns => $dnss[0];
	    }
	}
    }

    #- sync it with ../mdk-stage1/automatic.c
    my %aliases = (method => 'met', network => 'netw', interface => 'int', gateway => 'gat', netmask => 'netm',
		   adsluser => 'adslu', adslpass => 'adslp', hostname => 'hos', domain => 'dom', server => 'ser',
		   directory => 'dir', user => 'use', pass => 'pas', disk => 'dis', partition => 'par');
    
    'automatic=' . join(',', map { ($aliases{$_->[0]} || $_->[0]) . ':' . $_->[1] } group_by2(@ks));
}

sub find_root_parts {
    my ($fstab, $prefix) = @_;

    grep { $_->{release} =~ /\b(mandrake|mandrakelinux|mandriva|conectiva|mageia)\b/i } 
      _find_root_parts($fstab, $prefix);
}

sub _find_root_parts {
    my ($fstab, $prefix) = @_;

    if ($::local_install) {
	my $f = common::release_file('/mnt') or return;
	return common::parse_release_file('/mnt', $f, {});
    }

    map { 
	my $handle = any::inspect($_, $prefix);
	if (my $f = $handle && common::release_file($handle->{dir})) {
	    common::parse_release_file($handle->{dir}, $f, $_);
	} else { () }
    } grep { isTrueLocalFS($_) } @$fstab;
}

sub migrate_device_names {
    my ($all_hds, $from_fstab, $new_root, $root_from_fstab, $o_in) = @_;

    log::l("warning: fstab says root partition is $root_from_fstab->{device}, whereas we were reading fstab from $new_root->{device}");
    my ($old_prefix, $old_part_number) = devices::simple_partition_scan($root_from_fstab);
    my ($new_prefix, $new_part_number) = devices::simple_partition_scan($new_root);

    if ($old_part_number != $new_part_number) {
	log::l("argh, $root_from_fstab->{device} and $old_part_number->{device} are not the same partition number");
	return;
    }

    log::l("replacing $old_prefix with $new_prefix");
    
    my %h;
    foreach (@$from_fstab) {
	if ($_->{device} =~ s!^\Q$old_prefix!$new_prefix!) {
	    #- this is simple to handle, nothing more to do
	} elsif ($_->{part_number}) {
	    my $device_prefix = devices::part_prefix($_);
	    push @{$h{$device_prefix}}, $_;
	} else {
	    #- hopefully this does not need anything special
	}
    }
    my @from_fstab_per_hds = values %h or return;


    my @current_hds = grep { $new_root->{rootDevice} ne $_->{device} } fs::get::hds($all_hds);

    found_one:
    @from_fstab_per_hds or return;

    foreach my $from_fstab_per_hd (@from_fstab_per_hds) {
	my ($matching, $other) = partition { 
	    my $hd = $_;
	    every {
		my $wanted = $_;
		my $part = find { $_->{part_number} eq $wanted->{part_number} } partition_table::get_normal_parts($hd);
		$part && $part->{fs_type} && fs::type::can_be_this_fs_type($wanted, $part->{fs_type});
	    } @$from_fstab_per_hd;
	} @current_hds;
	@$matching == 1 or next;

	my ($hd) = @$matching;
	@current_hds = @$other;
	@from_fstab_per_hds = grep { $_ != $from_fstab_per_hd } @from_fstab_per_hds;

	log::l("$hd->{device} nicely corresponds to " . join(' ', map { $_->{device} } @$from_fstab_per_hd));
	foreach (@$from_fstab_per_hd) {
	    partition_table::compute_device_name($_, $hd);
	}
	goto found_one;
    }
	
    #- we cannot find one and only one matching hd
    my @from_fstab_not_handled = map { @$_ } @from_fstab_per_hds;
    log::l("we still do not know what to do with: " . join(' ', map { $_->{device} } @from_fstab_not_handled));


    if (!$o_in) {
	log::l("well, ignoring them!");
	return;
    }

    my $propositions_valid = every {
	my $wanted = $_;
	my @parts = grep { $_->{part_number} eq $wanted->{part_number}
			     && $_->{fs_type} && fs::type::can_be_this_fs_type($wanted, $_->{fs_type}) } fs::get::hds_fstab(@current_hds);
	$wanted->{propositions} = \@parts;
	@parts > 0;
    } @from_fstab_not_handled;

    $o_in->ask_from('', 
		    N("The following disk(s) were renamed:"),
		    [ map {
			{ label => N("%s (previously named as %s)", $_->{mntpoint}, $_->{device}),
			  val => \$_->{device}, format => sub { $_[0] && $_->{device} },
			  list => [ '', 
				    $propositions_valid ? @{$_->{propositions}} : 
				    fs::get::hds_fstab(@current_hds) ] };
		    } @from_fstab_not_handled ]);
}

sub use_root_part {
    my ($all_hds, $part, $o_in) = @_;
    return if $::local_install;

    my $migrate_device_names;
    {
	my $handle = any::inspect($part, $::prefix) or internal_error();

	my @from_fstab = fs::read_fstab($handle->{dir}, '/etc/fstab', 'keep_default');

	my $root_from_fstab = fs::get::root_(\@from_fstab);
	if (!fs::get::is_same_hd($root_from_fstab, $part)) {
	    $migrate_device_names = 1;
	    log::l("from_fstab contained: $_->{device} $_->{mntpoint}") foreach @from_fstab;
	    migrate_device_names($all_hds, \@from_fstab, $part, $root_from_fstab, $o_in);
	    log::l("from_fstab now contains: $_->{device} $_->{mntpoint}") foreach @from_fstab;
	}
	fs::add2all_hds($all_hds, @from_fstab);
	log::l("fstab is now: $_->{device} $_->{mntpoint}") foreach fs::get::fstab($all_hds);
    }
    isSwap($_) and $_->{mntpoint} = 'swap' foreach fs::get::really_all_fstab($all_hds); #- use all available swap.
    $migrate_device_names;
}

sub getHds {
    my ($o, $o_in) = @_;
    fs::any::get_hds($o->{all_hds} ||= {}, $o->{fstab} ||= [], 
		     $o->{manualFstab}, $o->{partitioning}, $::local_install, $o_in);
}

sub removable_media__early_in_install() {
    eval { modules::load('usb_storage', 'sd_mod') } if detect_devices::usbStorage();
    my $all_hds = fsedit::get_hds({});
    fs::get_raw_hds('', $all_hds);

    my @l1 = grep { detect_devices::isKeyUsb($_) } @{$all_hds->{hds}};
    my @l2 = grep { $_->{media_type} eq 'fd' || detect_devices::isKeyUsb($_) } @{$all_hds->{raw_hds}};
    (fs::get::hds_fstab(@l1), @l2);
}

my %media_browser;
sub media_browser {
    my ($in, $save, $o_suggested_name) = @_;

    my %media_type2text = (
	fd => N("Floppy"),
	hd => N("Hard Disk"),
	cdrom => N("CDROM"),
    );
    my @network_protocols = (if_(!$save, N_("HTTP")), if_(0, N_("FTP")), N_("NFS"));

    my $to_text = sub {
	my ($hd) = @_;
	($media_type2text{$hd->{media_type}} || $hd->{media_type}) . ': ' . partition_table::description($hd);
    };

  ask_media:
    my $all_hds = fsedit::get_hds({}, $in);
    fs::get_raw_hds('', $all_hds);

    my @raw_hds = grep { !$save || $_->{media_type} ne 'cdrom' } @{$all_hds->{raw_hds}};
    my @dev_and_text = group_by2(
	(map { $_ => $to_text->($_) } @raw_hds),
	(map { 
	    my $hd = $to_text->($_);
	    map { $_ => join('\1', $hd, partition_table::description($_)) } grep { isTrueFS($_) || isOtherAvailableFS($_) } fs::get::hds_fstab($_);
	} fs::get::hds($all_hds)),
	if_(is_network_install($::o) || install::steps::hasNetwork($::o),
	    map { $_ => join('\1', N("Network"), translate($_)) } @network_protocols),
    );

    $in->ask_from_({
	messages => N("Please choose a media"),
    }, [ 
	{ val => \$media_browser{dev}, separator => '\1', list => [ map { $_->[1] } @dev_and_text ] },
    ]) or return;

    my $dev = (find { $_->[1] eq $media_browser{dev} } @dev_and_text)->[0];

    my $browse = sub {
	my ($dir) = @_;

      browse:
	my $file = $in->ask_filename({ save => $save, 
				       directory => $dir, 
				       if_($o_suggested_name, file => "$dir/$o_suggested_name"),
				   }) or return;
	if (-e $file && $save) {
	    $in->ask_yesorno('', N("File already exists. Overwrite it?")) or goto browse;
	}
	if ($save) {
	    if (!open(my $_fh, ">>$file")) {
		$in->ask_warn('', N("Permission denied"));
		goto browse;
	    }
	    $file;
	} else {
	    common::open_file($file) || goto browse;
	}
    };
    my $inspect_and_browse = sub {
	my ($dev) = @_;

	if (my $h = any::inspect($dev, $::prefix, $save)) {
	    if (my $file = $browse->($h->{dir})) {
		return $h, $file;
	    }
	    undef $h; #- help perl
	} else {
	    $in->ask_warn(N("Error"), formatError($@));
	}
	();
    };

    if (member($dev, @network_protocols)) {
	require install::interactive;
	install::interactive::upNetwork($::o);

	if ($dev eq 'HTTP') {
	    require install::http;
	    $media_browser{url} ||= 'http://';

	    while (1) {
		$in->ask_from('', 'URL', [
		    { val => \$media_browser{url} }
		]) or last;
		    
		if ($dev eq 'HTTP') {
		    my $fh = install::http::getFile($media_browser{url});
		    $fh and return '', $fh;
		}
	    }
	} elsif ($dev eq 'NFS') {
	    while (1) {
		$in->ask_from('', 'NFS', [
		    { val => \$media_browser{nfs} }
		]) or last;

		my ($kind) = fs::wild_device::analyze($media_browser{nfs});
		if ($kind ne 'nfs') {
		    $in->ask_warn('', N("Bad NFS name"));
		    next;
		}

		my $nfs = fs::wild_device::to_subpart($media_browser{nfs});
		$nfs->{fs_type} = 'nfs';

		if (my ($h, $file) = $inspect_and_browse->($nfs)) {
		    return $h, $file;
		}
	    }
	} else {
	    $in->ask_warn('', 'todo');
	    goto ask_media;
	}
    } else {
	if (!$dev->{fs_type} || $dev->{fs_type} eq 'auto' || $dev->{fs_type} =~ /:/) {
	    if (my $p = fs::type::type_subpart_from_magic($dev)) {
		add2hash($p, $dev);
		$dev = $p;
	    } else {
		$in->ask_warn(N("Error"), N("Bad media %s", partition_table::description($dev)));
		goto ask_media;
	    }
	}

	if (my ($h, $file) = $inspect_and_browse->($dev)) {
	    return $h, $file;
	}

	goto ask_media;
    }
}

sub X_options_from_o {
    my ($o) = @_;
    { 
	freedriver => $o->{freedriver},
	allowFB => $o->{allowFB},
	ignore_bad_conf => $o->{isUpgrade} =~ /redhat|conectiva/,
    };
}

sub screenshot_dir__and_move() {
    my ($dir0, $dir1, $dir2) = ('/root', "$::prefix/root", '/tmp');
    if (-e $dir0 && ! -e '/root/non-chrooted-marker.DrakX') {
	($dir0, 'nowarn'); #- it occurs during pkgs install when we are chrooted
    } elsif (-e $dir1) {
        my $path = "$dir2/DrakX-screenshots";
	if (-e $path) {
	    cp_af($path, $dir1);
	    rm_rf($path);
	}
	$dir1;
    } else {
	$dir2;
    }
}

my $warned;
sub take_screenshot {
    my ($in) = @_;
    my ($base_dir, $nowarn) = screenshot_dir__and_move();
    my $dir = "$base_dir/DrakX-screenshots";
    if (!-e $dir) {
	mkdir $dir or $in->ask_warn('', N("Cannot make screenshots before partitioning")), return;
    }
    my $nb = 1;
    $nb++ while -e "$dir/$nb.png";
    run_program::run('fb2png', '-p', "$dir/$nb.png");

    # help doesn't remember warning has been shown (one shot processes):
    $warned ||= -e "$dir/2.png";

    if (!$warned && !$nowarn) {
	$warned = 1;
	$in->ask_warn('', N("Screenshots will be available after install in %s", "/root/DrakX-screenshots"));
    }
}

sub copy_advertising {
    my ($o) = @_;

    return if $::rootwidth < 800;

    my $f;
    my $source_dir = "install/extra/advertising";
    foreach ("." . $o->{locale}{lang}, "." . substr($o->{locale}{lang},0,2), '') {
	$f = getFile_($o->{stage2_phys_medium}, "$source_dir$_/list") or next;
	$source_dir = "$source_dir$_";
    }
    if (my @files = <$f>) {
	my $dir = "$::prefix/tmp/drakx-images";
	mkdir $dir;
	unlink glob_("$dir/*");
	foreach (@files) {
	    chomp;
	    install::media::getAndSaveFile_($o->{stage2_phys_medium}, "$source_dir/$_", "$dir/$_");
	    (my $pl = $_) =~ s/\.png/.pl/;
	    install::media::getAndSaveFile_($o->{stage2_phys_medium}, "$source_dir/$pl", "$dir/$pl");
	}
	@advertising_images = map { "$dir/$_" } @files;
    }
}

sub remove_advertising() {
    eval { rm_rf("$::prefix/tmp/drakx-images") };
    @advertising_images = ();
}

sub disable_user_view() {
    substInFile { s/^UserView=.*/UserView=true/ } "$::prefix/etc/kde/kdm/kdmrc";
    substInFile { s/^Browser=.*/Browser=0/ } "$::prefix/etc/X11/gdm/custom.conf";
}

sub set_security {
    my ($o) = @_;
    require security::various;
    return if !-x "$::prefix/usr/sbin/msec";
    security::level::set($o->{security});
    security::various::config_security_user($::prefix, $o->{security_user});
}

sub write_fstab {
    my ($o) = @_;
    return if $::local_install || $o->{isUpgrade} && $o->{isUpgrade} !~ /redhat|conectiva/ && !$o->{migrate_device_names};
    fs::write_fstab($o->{all_hds}, $::prefix);
}

=item adjust_files_mtime_to_timezone() {

Fixes mtime of a couple important files according to timezone in order to:

=over 4

=item * to ensure linuxconf does not cry against those files being in the future

=item * to ensure fc-cache works correctly on fonts installed after reboot

=back

=cut

sub adjust_files_mtime_to_timezone() {
    my $timezone_shift = run_program::rooted_get_stdout($::prefix, 'date', '+%z');
    my ($h, $m) = $timezone_shift =~ /\+(..)(..)/ or return;
    my $now = time() - ($h * 60 + $m * 60) * 60;

    my @files = (
	(map { "$::prefix/$_" } '/etc/modules.conf', '/etc/crontab', '/etc/sysconfig/mouse', '/etc/sysconfig/network', '/etc/X11/fs/config'),
	glob_("$::prefix/var/cache/fontconfig/*"),
    );
    log::l("adjust_files_mtime_to_timezone: setting time back $h:$m for files " . join(' ', @files));
    foreach (@files) {
	utime $now, $now, $_;
    }
}


sub move_compressed_image_to_disk {
    my ($o) = @_;

    our $compressed_image_on_disk;
    return if $compressed_image_on_disk || $::local_install;

    my $name = 'mdkinst.sqfs';
    my ($loop, $current_image) = devices::find_compressed_image($name) or return;
    my $compressed_image_size = (-s $current_image) / 1024; #- put in KiB

    my $dir;
    if (availableRamMB() > 400) {
	$dir = '/tmp'; #- on tmpfs
    } else {
	my $tmp = fs::get::mntpoint2part('/tmp', $o->{fstab});
	if ($tmp && fs::df($tmp, $::prefix) / 2 > $compressed_image_size * 1.2) { #- we want at least 20% free afterwards
	    $dir = "$::prefix/tmp";
	} else {
	    my $root = fs::get::mntpoint2part('/', $o->{fstab});
	    my $root_free_MB = fs::df($root, $::prefix) / 2 / 1024;
	    my $wanted_size_MB = $o->{isUpgrade} || fs::get::mntpoint2part('/usr', $o->{fstab}) ? 150 : 300;
	    log::l("compressed image: root free $root_free_MB MB, wanted at least $wanted_size_MB MB");
	    if ($root_free_MB > $wanted_size_MB) {
		$dir = $tmp ? $::prefix : "$::prefix/tmp";
	    } else {
		$dir = '/tmp'; #- on tmpfs
		if (availableRamMB() < 200) {
		    log::l("ERROR: not much ram (" . availableRamMB() . " MB), we're going in the wall!");
		}
	    }
	}
    }
    $compressed_image_on_disk = "$dir/$name";

    if ($current_image ne $compressed_image_on_disk) {
	log::l("move_compressed_image_to_disk: copying $current_image to $compressed_image_on_disk");
	cp_af($current_image, $compressed_image_on_disk);
	run_program::run('losetup', '-r', $loop, $compressed_image_on_disk);
	unlink $current_image if $current_image eq "/tmp/$name";
    }
}

sub deploy_server_notify {
    my ($o) = @_;
    my $fallback_intf = "eth0";
    my $fallback_port = 3710;

    my ($server, $port) = $o->{deploy_server} =~ /^(.*?)(?::(\d+))?$/;
    if ($server) {
        require network::tools;
        require IO::Socket;
        $port ||= $fallback_port;
        my $intf = network::tools::get_current_gateway_interface() || $fallback_intf;
        my $mac = c::get_hw_address($intf);
        my $sock = IO::Socket::INET->new(PeerAddr => $server, PeerPort => $port, Proto => 'tcp');
        if ($sock) {
            print $sock "$mac\n";
            close($sock);
            log::l(qq(successfully notified deploy server $server on port $port));
        } else {
            log::l(qq(unable to contact deploy server $server on port $port));
        }
    } else {
        log::l(qq(unable to parse deploy server in string $o->{deploy_server}));
    }
}

#-###############################################################################
#- pcmcia various
#-###############################################################################
sub configure_pcmcia {
    my ($o) = @_;
    my $controller = detect_devices::pcmcia_controller_probe();
    $o->{pcmcia} ||= $controller && $controller->{driver} or return;
    log::l("configuring PCMCIA controller ($o->{pcmcia})");
    symlink "/tmp/stage2/$_", $_ foreach "/etc/pcmcia";
    eval { modules::load($o->{pcmcia}, 'pcmcia') };
    run_program::run("/lib/udev/pcmcia-socket-startup");
}

=back

=cut

1;
