package any;

use diagnostics;
use strict;

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:system :file);
use commands;
use run_program;

sub addKdmUsers {
    my ($prefix, @users) = @_;
    require timezone;
    my @u1 = my @users_male = qw(tie default curly);
    my @u2 = my @users_female = qw(brunette girl woman-blond);
    foreach (@users) {
	my $l = rand() < timezone::sexProb($_) ? \@u2 : \@u1;
	my $u = splice(@$l, rand(@$l), 1); #- known biased (see cookbook for better)
	eval { commands::cp "$prefix/usr/share/icons/user-$u-mdk.xpm", "$prefix/usr/share/apps/kdm/pics/users/$_.xpm" };
	@u1 = @users_male   unless @u1;
	@u2 = @users_female unless @u2;
    }
    eval { commands::cp "-f", "$prefix/usr/share/icons/user-hat-mdk.xpm", "$prefix/usr/share/apps/kdm/pics/users/root.xpm" } unless $::isStandalone;
}

sub addUsers {
    my ($prefix, @users) = @_;
    my $msec = "$prefix/etc/security/msec";
    foreach my $u (@users) {
	substInFile { s/^$u\n//; $_ .= "$u\n" if eof } "$msec/user.conf" if -d $msec;
    }
    run_program::rooted($prefix, "/etc/security/msec/init-sh/grpuser.sh --refresh");

    addKdmUsers($prefix, @users);
}

1;
