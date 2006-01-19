
warn "PATCHING\n";
log::l("PATCHING\n");

use install_any;

undef *find_root_parts;
*find_root_parts = sub {
    my ($fstab, $prefix) = @_;
    map { 
	my $handle = any::inspect($_, $prefix);
	my $s = $handle && cat_("$handle->{dir}/etc/redhat-release");
	if ($s) {
	    chomp($s);
	    $s =~ s/\s+for\s+\S+//;
	    log::l("find_root_parts found $_->{device}: $s");
	    { release => $s, part => $_ };
	} else { () }
    } @$fstab;
};


use pkgs;
package pkgs;

my $old_compare_pkg = \&URPM::Package::compare_pkg;
undef *URPM::Package::compare_pkg;
*URPM::Package::compare_pkg = sub {
    my ($lpkg, $rpkg) = @_;
    my $c = ($lpkg->release =~ /mdk$/ ? 1 : 0) - ($rpkg->release =~ /mdk$/ ? 1 : 0);
    if ($c) {
	my $lpkg_ver = $lpkg->version . '-' . $lpkg->release;
	my $rpkg_ver = $rpkg->version . '-' . $rpkg->release;
	log::l($lpkg->name . ' ' . $rpkg->name . ': prefering ' . ($c == 1 ? "$lpkg_ver over $rpkg_ver" : "$rpkg_ver over $lpkg_ver"));
	return $c;
    }
    &$old_compare_pkg;
};

my $old_compare = \&URPM::Package::compare;
undef *URPM::Package::compare;
*URPM::Package::compare = sub {
    my ($lpkg, $rpkg_ver) = @_;
    my $c = ($lpkg->release =~ /mdk$/ ? 1 : 0) - ($rpkg_ver =~ /mdk$/ ? 1 : 0);
    if ($c) {
	my $lpkg_ver = $lpkg->version . '-' . $lpkg->release;
	log::l($lpkg->name . ' ' . ': prefering ' . ($c == 1 ? "$lpkg_ver over $rpkg_ver" : "$rpkg_ver over $lpkg_ver"));
	return $c;
    }
    &$old_compare;
};

use install2;
package install2;
my $old_choosePackages = \&choosePackages;
undef *choosePackages;
*choosePackages = sub {
    my @should_not_be_dirs = qw(/usr/X11R6/lib/X11/xkb /usr/share/locale/zh_TW/LC_TIME /usr/include/GL);
    my @should_be_dirs = qw(/etc/X11/xkb);
    foreach (@should_not_be_dirs) {
	my $f = "$::prefix$_";
	rm_rf($f) if !-l $f && -d $f;
    }
    foreach (@should_be_dirs) {
	my $f = "$::prefix$_";
	rm_rf($f) if -l $f || !-d $f;
    }
    unlink "$::prefix/etc/X11/XF86Config";
    unlink "$::prefix/etc/X11/XF86Config-4";

    &$old_choosePackages;
};

use fs;
package fs;

my $old = \&read_fstab;
undef *read_fstab;
*read_fstab = sub {
    my @l = &$old;

    my %label2device = map {
 	my $dev = devices::make($_->{device});
	if (my ($label) = `tune2fs -l $dev 2>/dev/null` =~ /volume name:\s*(\S+)/) {
	    log::l("device $_->{device} has label $label");
	    $label => $_->{device};
	} else {
	    ();
	}
    } fsedit::read_proc_partitions([]);

    foreach (@l) {
	my ($label) = ($_->{device_LABEL} || $_->{device}) =~ /^LABEL=(.*)/ or next;
	if ($label2device{$label}) {
	    $_->{device} = $label2device{$label};
	} else {
	    log::l("can't find label $label");
	}
    }

    @l;
};

use any;
package any;

undef *fix_broken_alternatives;
*fix_broken_alternatives = sub {
    #- fix bad update-alternatives that may occurs after upgrade (and sometimes for install too).
    -d "$::prefix/etc/alternatives" or return;

    foreach (all("$::prefix/etc/alternatives")) {
	log::l("setting alternative $_");
	run_program::rooted($::prefix, 'update-alternatives', '--auto', $_);
    }
};
