package any;

use diagnostics;
use strict;
use vars qw(@users);

#-######################################################################################
#- misc imports
#-######################################################################################
use common qw(:common :system :file);
use commands;
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

1;
