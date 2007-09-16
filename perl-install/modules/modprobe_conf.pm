package modules::modprobe_conf; # $Id$

use log;
use common;

our @ISA = qw(modules::any_conf);


sub file { '/etc/modprobe.conf' }
sub handled_fields { qw(alias options install remove) }

sub mapping {
    my ($_conf, @modules) = @_;
    my @l = map { modules::mapping_24_26($_) } @modules;
    wantarray() ? @l : $l[0];
}

sub get_above {
    my ($conf, $module) = @_;
    $module = $conf->mapping($module);

    my (undef, $after) = parse_non_virtual($module, $conf->{$module}{install}) or return;
    my ($l, $_other_cmds) = partition_modprobes($after);
    @$l;
}
sub set_above {
    my ($conf, $module, $o_modules) = @_;
    $module = $conf->mapping($module);
    my @modules = $conf->mapping(split(' ', $o_modules || ''));

    { #- first add to "install" command
	my ($before, $after) = parse_non_virtual($module, $conf->{$module}{install});
	my ($_previous_modules, $other_cmds) = partition_modprobes($after || '');
	$after = join('; ', @$other_cmds, map { "/sbin/modprobe $_" } @modules);
	$conf->{$module}{install} = unparse_non_virtual($module, '--ignore-install', $before, $after);
    }
    { #- then to "remove" command
	my ($before, $after) = parse_non_virtual($module, $conf->{$module}{remove});
	my ($_previous_modules, $other_cmds) = partition_modprobes($before || '');
	$before = join('; ', @$other_cmds, map { "/sbin/modprobe -r $_" } @modules);
	$conf->{$module}{remove} = unparse_non_virtual($module, '-r --ignore-remove', $before, $after);
    }
}

sub create_from_old() {
    #- use module-init-tools script
    run_program::rooted($::prefix, "/sbin/generate-modprobe.conf", ">", file());
}

sub read {
    my ($type, $o_file) = @_;

    my $file = $o_file || do {
	my $f = $::prefix . file();
	if (!-e $f && -e "$::prefix/etc/modules.conf") {
	    create_from_old();
	}
	$f;
    };

    my $conf = modules::any_conf::read_handled($type, $file);

    extract_probeall_field($conf);

    $conf;
}

sub write {
    my ($conf, $o_file) = @_;

    remove_probeall_field($conf);

    my $_b = before_leaving { extract_probeall_field($conf) };

    modules::any_conf::write($conf, $o_file);
}



################################################################################
sub remove_braces {
    my ($s) = @_;
    $s =~ s/^\s*\{\s*(.*)\s*;\s*\}\s*$/$1/;
    $s;
}

sub parse_non_virtual {
    my ($module, $s) = @_;
    my ($before, $options, $after) = 
      $s =~ m!^(?:(.*);)?
              \s*(?:/sbin/)?modprobe\s+(-\S+\s+)*\Q$module\E
              \s*(?:&&\s*(.*))?$!x 
		or return;
    $options =~ /--ignore-(install|remove)\b/ or return;

    ($before, $after) = map { remove_braces($_ || '') } $before, $after;
    $after =~ s!\s*;\s*/bin/true$!!;

    $before, $after;
}

sub unparse_non_virtual {
    my ($module, $mode, $before, $after) = @_;
    ($before ? "$before; " : '')
      . "/sbin/modprobe --first-time $mode $module" 
	. ($after ? " && { $after; /bin/true; }" : '');    
}

sub partition_modprobes {
    my ($s) = @_;

    my (@modprobes, @other_cmds);
    my @l = split(/\s*;\s*/, $s);
    foreach (@l) {
	if (m!^(?:/sbin/)?modprobe\s+(?:-r\s+)?(\S+)$!) {
	    push @modprobes, $1;
	} else {
	    push @other_cmds, $1;
	}
    }
    \@modprobes, \@other_cmds;
}

sub parse_for_probeall {
    my ($module, $s) = @_;

    parse_non_virtual($module, $s) and return;
    if ($s =~ /[{&|]/) {
	log::l("weird install line in modprobe.conf for $module: $s");
	return;
    }
    $s ne '/bin/true' or return; #- we have "alias $module off" here

    $s =~ s!\s*;\s*/bin/true$!!;

    my ($l, $other_cmds) = partition_modprobes($s);

    @$other_cmds ? undef : $l;
}

sub extract_probeall_field {
    my ($conf) = @_;

    foreach my $module (keys %$conf) {
	$conf->{$module}{install} or next;
	my $l = parse_for_probeall($module, $conf->{$module}{install}) or next;

	$conf->{$module}{probeall} = join(' ', @$l);
	delete $conf->{$module}{install};
    }
}

sub remove_probeall_field {
    my ($conf) = @_;

    foreach my $module (keys %$conf) {
	my $modules = delete $conf->{$module}{probeall} or next;

	$conf->{$module}{install} = join('; ', (map { "/sbin/modprobe $_" }    split(' ', $modules)), '/bin/true');
    }
}

1;
