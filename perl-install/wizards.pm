package wizards;
# $Id$

use strict;
use c;
use common;

=head1 NAME

wizards - a layer on top of interactive that ensure proper stepping

=head1 SYNOPSIS

    use wizards
    # global wizard options:

    use wizards;
    use interactive;
    my $wiz = {

               allow_user => "", # do we need root
               defaultimage => "", # wizard icon
               init => sub { },    # code run on wizard startup
               name => "logdrake", # wizard title
               needed_rpm => "packages list", # packages to install before running the wizard
               pages => {
                         {
                             name => "welcome", # first step
                             next => "step1",   # which step should be displayed after the current one
                             pre =>  sub { },   # code executing when stepping backward
                             post => sub { },   # code executing when stepping forward;
                                                # returned value is next step name (but is overriden by "next" field)
                             end => ,       # is it the last step ?
                             no_cancel => , # do not display the cancel button (eg for first step)
                             no_back => ,   # do not display the back button (eg for first step)
                             ignore => ,    # do not stack this step for back stepping (eg for warnings and the like steps)
                             data => [],    # the actual data passed to interactive
                         },
                         {
                          name => "step1",
                          data => [
                                   {
                                       # usual interactive fields:
                                       label => N("Banner:"),
                                       val => \$o->{var}{wiz_banner}
                                       list => [] ,
                                       # wizard layer variables:
                                       boolean_list => "", # provide default status for booleans list
                                   },
                                   ],
                      },
                     },
           };

    my $w => wizards->new
    $w->process($wiz, $in);

=head1 DESCRIPTION

wizards is a layer built on top of the interactive layer that do proper
backward/forward stepping for us.

=cut


sub new { bless {}, $_[0] }


sub check_rpm {
    my ($in, $rpms) = @_;
    foreach my $rpm (@$rpms) {
        next if !$in->do_pkgs->is_installed($rpm);
        if ($in->ask_okcancel(N("Error"), N("%s is not installed\nClick \"Next\" to install or \"Cancel\" to quit", c::from_utf8($rpm)))) {
            $::testing and next;
            if (!$in->do_pkgs->install($rpm)) {
                local $::Wizard_finished = 1;
                $in->ask_okcancel(N("Error"), N("Installation failed"));
                $in->exit;
            }
        } else { $in->exit }
    }
}


sub process {
    my ($w, $o, $in) = @_;
    my $page = $o->{pages}{welcome};
    local $::isWizard = 1;
    local $::Wizard_title = $o->{name} || $::Wizard_title;
    local $::Wizard_pix_up = $o->{defaultimage} || $::Wizard_pix_up;
    #require_root_capability() if $> && !$o->{allow_user} && !$::testing;
    check_rpm($in, $o->{needed_rpm}) if $o->{needed_rpm};
    if (defined $o->{init}) {
        my ($res, $msg) = &{$o->{init}};
        if (!$res) {
            $in->ask_okcancel(N("Error"), $msg);
            die "wizard failled" if !$::testing
        }
    }
    
    my $next = 'welcome';  # initial step
    my @steps;             # steps stack
    while ($next) {
        local $::Wizard_no_previous = $page->{no_back};
        local $::Wizard_no_cancel = $page->{no_cancel} || $page->{end};
        local $::Wizard_finished = $page->{end};
        defined $page->{pre} and $page->{pre}();
        # FIXME or the displaying fails
        my $data = defined $page->{data} ? ref $page->{data} ? $page->{data} : [ { label => '' } ] : [ { label => '' } ];
        my $data2;
        foreach my $d (@$data) {
            $d->{val} = ${$d->{val_ref}} if $d->{val_ref};
            $d->{list} = $d->{list_ref} if $d->{list_ref};
            if ($d->{boolean_list}) { 
                my $i;
                foreach (@{$d->{boolean_list}}) { 
                    push @$data2, { text => $_, type => 'bool', val => \${$d->{val}}->[$i], disabled => $d->{disabled} };
                    $i++
                }
            } else {
                push @$data2, $d
            }
        }
        my $a = $in->ask_from($o->{name}, $page->{name}, $data2, complete => $page->{complete} || sub { 0 });
        if ($a) {
            # step forward:
            push @steps, $next if !$page->{ignore} && $steps[-1] ne $next;
            $next = defined $page->{post} ? $page->{post}() : 0;
            defined $o->{pages}{$next} or $next = $page->{next};
        } else {
            # step back:
            $next = pop @steps
        }
        $next or return;
        $page = $o->{pages}{$next}
    }
}

1;
