package any;

use diagnostics;
use strict;
use vars qw(@users);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :system :file);
use commands;
use detect_devices;
use fsedit;
use run_program;

#-PO: names (tie, curly...) have corresponding icons for kdm
my @users_male = (__("tie"), __("default"), __("curly")); #- don't change the names, files correspond to them
my @users_female = (__("brunette"), __("girl"), __("woman-blond"));
@users = (@users_male, @users_female);

sub addKdmIcon {
    my ($prefix, $user, $icon, $force) = @_;
    my $dest = "$prefix/usr/share/apps/kdm/pics/users/$user.xpm";
    unlink $dest if $force;
    eval { commands::cp("$prefix/usr/share/icons/user-$icon-mdk.xpm", $dest) } if $icon;
}

sub addKdmUsers {
    my ($prefix, @users) = @_;
    require timezone;
    my @u1 = @users_male;
    my @u2 = @users_female;
    foreach (@users) {
	my $l = rand() < timezone::sexProb($_) ? \@u2 : \@u1;
	my $u = splice(@$l, rand(@$l), 1); #- known biased (see cookbook for better)
	addKdmIcon($prefix, $_, $u);
	eval { commands::cp "$prefix/usr/share/icons/user-$u-mdk.xpm", "$prefix/usr/share/apps/kdm/pics/users/$_.xpm" };
	@u1 = @users_male   unless @u1;
	@u2 = @users_female unless @u2;
    }
    addKdmIcon($prefix, 'root', 'hat', 'force');
}

sub addUsers {
    my ($prefix, @users) = @_;
    my $msec = "$prefix/etc/security/msec";
    foreach my $u (@users) {
	substInFile { s/^$u\n//; $_ .= "$u\n" if eof } "$msec/user.conf" if -d $msec;
    }
    run_program::rooted($prefix, "/etc/security/msec/init-sh/grpuser.sh --refresh");
}

sub setupBootloader {
    my ($in, $b, $hds, $fstab, $security, $prefix, $more) = @_;

    $more++ if $b->{bootUnsafe};

    if ($::beginner && $more == 1) {
	my @l = (__("First sector of drive (MBR)"), __("First sector of boot partition"));

	$in->set_help('setupBootloaderBeginner') unless $::isStandalone;
	my $boot = $hds->[0]{device};
	my $onmbr = "/dev/$boot" eq $b->{boot};
	$b->{boot} = "/dev/" . ($in->ask_from_list_(_("LILO Installation"),
					_("Where do you want to install the bootloader?"),
					\@l, $l[!$onmbr]) eq $l[0] 
					  ? $boot : fsedit::get_root($fstab, 'boot')->{device});
    } elsif ($more || !$::beginner) {
	$in->set_help("setupBootloaderGeneral") unless $::isStandalone;

	$::expert and $in->ask_yesorno('', _("Do you want to use LILO?"), 1) || return;

	my @l = (
_("Boot device") => { val => \$b->{boot}, list => [ map { "/dev/$_" } (map { $_->{device} } @$hds, @$fstab), detect_devices::floppies() ], not_edit => !$::expert },
_("LBA (doesn't work on old BIOSes)") => { val => \$b->{lba32}, type => "bool", text => "lba" },
_("Compact") => { val => \$b->{compact}, type => "bool", text => _("compact") },
_("Delay before booting default image") => \$b->{timeout},
_("Video mode") => { val => \$b->{vga}, list => [ keys %lilo::vga_modes ], not_edit => $::beginner },
$security < 4 ? () : (
_("Password") => { val => \$b->{password}, hidden => 1 },
_("Password (again)") => { val => \$b->{password2}, hidden => 1 },
_("Restrict command line options") => { val => \$b->{restricted}, type => "bool", text => _("restrict") },
)
	);
	@l = @l[0..3] unless $::expert;

	$b->{vga} ||= 'Normal';
	$in->ask_from_entries_refH('', _("LILO main options"), \@l,
				 complete => sub {
#-				     $security > 4 && length($b->{password}) < 6 and $in->ask_warn('', _("At this level of security, a password (and a good one) in lilo is requested")), return 1;
				     $b->{restricted} && !$b->{password} and $in->ask_warn('', _("Option ``Restrict command line options'' is of no use without a password")), return 1;
				     $b->{password} eq $b->{password2} or !$b->{restricted} or $in->ask_warn('', [ _("The passwords do not match"), _("Please try again") ]), return 1;
				     0;
				 }
				) or return 0;
	$b->{vga} = $lilo::vga_modes{$b->{vga}} || $b->{vga};
    }

    until ($::beginner && $more <= 1) {
	$in->set_help('setupBootloaderAddEntry') unless $::isStandalone;
	my $c = $in->ask_from_list_([''], 
_("Here are the following entries in LILO.
You can add some more or change the existing ones."),
		[ (sort @{[map { "$_->{label} ($_->{kernel_or_dev})" . ($b->{default} eq $_->{label} && "  *") } @{$b->{entries}}]}), __("Add"), __("Done") ],
	);
	$c eq "Done" and last;

	my ($e);

	if ($c eq "Add") {
	    my @labels = map { $_->{label} } @{$b->{entries}};
	    my $prefix;
	    if ($in->ask_from_list_('', _("Which type of entry do you want to add"), [ __("Linux"), __("Other OS (windows...)") ]) eq "Linux") {
		$e = { type => 'image' };
		$prefix = "linux";
	    } else {
		$e = { type => 'other' };
		$prefix = "windows";
	    }
	    $e->{label} = $prefix;
	    for (my $nb = 0; member($e->{label}, @labels); $nb++) { $e->{label} = "$prefix-$nb" }
	} else {
	    $c =~ /(\S+)/;
	    ($e) = grep { $_->{label} eq $1 } @{$b->{entries}};
	}
	my %old_e = %$e;
	my $default = my $old_default = $e->{label} eq $b->{default};
	    
	my @l;
	if ($e->{type} eq "image") { 
	    @l = (
_("Image") => { val => \$e->{kernel_or_dev}, list => [ eval { glob_("/boot/vmlinuz*") } ] },
_("Root") => { val => \$e->{root}, list => [ map { "/dev/$_->{device}" } @$fstab ], not_edit => !$::expert },
_("Append") => \$e->{append},
_("Initrd") => { val => \$e->{initrd}, list => [ eval { glob_("/boot/initrd*") } ] },
_("Read-write") => { val => \$e->{'read-write'}, type => 'bool' }
	    );
	    @l = @l[0..5] unless $::expert;
	} else {
	    @l = ( 
_("Root") => { val => \$e->{kernel_or_dev}, list => [ map { "/dev/$_->{device}" } @$fstab ], not_edit => !$::expert },
_("Table") => { val => \$e->{table}, list => [ '', map { "/dev/$_->{device}" } @$hds ], not_edit => !$::expert },
_("Unsafe") => { val => \$e->{unsafe}, type => 'bool' }
	    );
	    @l = @l[0..1] unless $::expert;
	}
	@l = (
_("Label") => \$e->{label},
@l,
_("Default") => { val => \$default, type => 'bool' },
	);

	if ($in->ask_from_entries_refH($c eq "Add" ? '' : ['', _("Ok"), _("Remove entry")], 
	    '', \@l,
	    complete => sub {
		$e->{label} or $in->ask_warn('', _("Empty label not allowed")), return 1;
		member($e->{label}, map { $_->{label} } grep { $_ != $e } @{$b->{entries}}) and $in->ask_warn('', _("This label is already in use")), return 1;
		0;
	    })) {
	    $b->{default} = $old_default || $default ? $default && $e->{label} : $b->{default};
	    
	    push @{$b->{entries}}, $e if $c eq "Add";
	} else {
	    @{$b->{entries}} = grep { $_ != $e } @{$b->{entries}};
	}
    }
    1;
}

1;
