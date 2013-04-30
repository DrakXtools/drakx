package fs::dmcrypt; # $Id: $

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common;
use fs::type;
use fs::get;
use run_program;

sub _crypttab() { "$::prefix/etc/crypttab" }

sub init() {
    whereis_binary('cryptsetup') or die "cryptsetup not installed";

    eval { modules::load('dm-crypt', list_modules::category2modules('various/crypto')) };
    devices::init_device_mapper();
    1;
}
my $initialized;
sub _ensure_initialized() {
    $initialized++ or init();
}

sub read_crypttab_ {
    my ($all_hds, $crypttab) = @_;

    -e $crypttab or return;

    my @raw_parts = grep { fs::type::isRawLUKS($_) } fs::get::really_all_fstab($all_hds);

    foreach (cat_($crypttab)) {
	next if /^#/;
	my ($dm_name, $dev) = split;

	my $raw_part = fs::get::device2part($dev, \@raw_parts)
	  or log::l("crypttab: unknown device $dev for $dm_name"), next;

	$raw_part->{dm_name} = $dm_name;
	_get_existing_one_with_state($raw_part);
    }
}

sub read_crypttab {
    my ($all_hds) = @_;
    read_crypttab_($all_hds, _crypttab());
}

sub save_crypttab_ {
    my ($all_hds, $crypttab) = @_;

    my @raw_parts = grep { $_->{dm_name} } fs::get::really_all_fstab($all_hds) or return;

    my %names = map { $_->{dm_name} => fs::wild_device::from_part('', $_) } @raw_parts;

    substInFile {
	my ($name, $_dev) = split;
	if (my $new_dev = delete $names{$name}) {
	    $_ = "$name $new_dev\n";
	}
	if (eof) {
	    $_ .= join('', map { "$_ $names{$_}\n" } sort keys %names);
	}
    } $crypttab;
}

sub save_crypttab {
    my ($all_hds) = @_;
    save_crypttab_($all_hds, _crypttab());
}

sub format_part {
    my ($part) = @_;

    my $tmp_key_file = "/tmp/.dmcrypt_key-$$";
    common::with_private_tmp_file($tmp_key_file, $part->{dmcrypt_key}, sub {
	_run_or_die('--cipher=aes-xts-benbi', '--key-size=512', 'luksFormat', '--batch-mode', devices::make($part->{device}), $_[0]);
    });
    fs::format::after_formatting($part);
}

sub open_part {
    my ($dmcrypts, $part) = @_;

    my $tmp_key_file = "/tmp/.dmcrypt_key-$$";
    common::with_private_tmp_file($tmp_key_file, $part->{dmcrypt_key}, sub {
	_run_or_die('luksOpen', devices::make($part->{device}), 
				$part->{dm_name}, '--key-file', $_[0]);
    });
    run_program::run('udevadm', 'settle');

    push @$dmcrypts, _get_existing_one_with_state($part);
}


sub _get_existing_one_with_state {
    my ($part) = @_;
    my $active_dmcrypt = _parse_dmsetup_table($part->{dm_name}, 
					      run_program::get_stdout('dmsetup', 'table', $part->{dm_name}));
    _get_existing_one([$part], $active_dmcrypt);
}

sub close_part {
    my ($dmcrypts, $part) = @_;
    my $dm_part = fs::get::device2part("mapper/$part->{dm_name}", $dmcrypts);
    _run_or_die('luksClose', devices::make($dm_part->{device}));
    $part->{dm_active} = 0;
    @$dmcrypts = grep { $_ != $dm_part } @$dmcrypts;    
}

sub _run_or_die {
    my ($command, @para) = @_;

    _ensure_initialized();

    run_program::run_or_die('cryptsetup', $command, @para);
}

sub get_existing {
    my $fstab = \@_;
    map { _get_existing_one($fstab, $_) } active_dmcrypts();
}

sub _get_existing_one {
    my ($fstab, $active_dmcrypt) = @_;

    my $p = fs::wild_device::to_subpart("/dev/mapper/$active_dmcrypt->{name}");

    my $part = { device => "mapper/$active_dmcrypt->{name}", size => $active_dmcrypt->{size}, 
		 options => 'noatime', dmcrypt_name => $active_dmcrypt->{name},
		 major => $p->{major}, minor => $p->{minor} };

    if (my $raw_part = find { fs::get::is_same_hd($active_dmcrypt, $_) } @$fstab) {
	$part->{rootDevice} = $raw_part->{device};
	$raw_part->{dm_name} = $active_dmcrypt->{name};
	$raw_part->{dm_active} = 1;
    } else {
	log::l("could not find the device $active_dmcrypt->{major}:$active_dmcrypt->{minor} for $part->{device}");
    }

    if (my $type = fs::type::type_subpart_from_magic($part)) {
	put_in_hash($part, $type);
    }
    fs::type::set_isFormatted($part, to_bool($part->{fs_type}));

    unless (fs::type::cannotBeMountable($part)) {
	$part->{fs_type} or fs::type::set_fs_type($part, defaultFS());
    }

    log::l("dmcrypt: found $part->{device} type $part->{fs_type} with rootDevice $part->{rootDevice}");

    $part;
}

sub active_dmcrypts() {
    grep { $_->{type} eq 'crypt' } active_dm();
}

sub _parse_dmsetup_table {
    my ($name, $s) = @_;

    my @l = split(' ', $s);
    my ($major, $minor) = split(':', $l[6]);
    { name => $name, size => $l[1], type => $l[2], major => $major, minor => $minor };
}

sub active_dm() {
    run_program::run('udevadm', 'settle');

    map {
	my $name = s/(.*?):\s*// && $1;
	_parse_dmsetup_table($name, $_);
    } run_program::get_stdout('dmsetup', 'table');
}

1;
