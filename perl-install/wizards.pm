package wizards;
# $Id$

use strict;
use c;
use common;

=head1 NAME

wizards - a layer on top of interactive that ensure proper stepping

=head1 SYNOPSIS

    use wizards;
    use interactive;

    my $wiz = wizards->new({

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
                                                # returned value is next step name (it overrides "next" field)
                             end => ,       # is it the last step ?
                             default => ,       # default answer for yes/no or when data does not conatains any fields
                             no_cancel => , # do not display the cancel button (eg for first step)
                             no_back => ,   # do not display the back button (eg for first step)
                             ignore => ,    # do not stack this step for back stepping (eg for warnings and the like steps)
                             interactive_help_id => , # help id  (for installer only)
                             data => [],    # the actual data passed to interactive
                         },
                         {
                          name => "step1",
                          data => [
                                   {
                                       # usual interactive fields:
                                       label => N("Banner:"),
                                       val => \$o->{var}{wiz_banner},
                                       list => [] ,
                                       # wizard layer variables:
                                       boolean_list => "", # provide default status for booleans list
                                   },
                                   ],
                      },
                     },
           });
    my $in = 'interactive'->vnew;
    $wiz->process($in);

=head1 DESCRIPTION

wizards is a layer built on top of the interactive layer that do proper
backward/forward stepping for us.

A step is made up of a name/description, a list of interactive fields (see
interactive documentation), a "complete", "pre" and "post" callbacks, an help
id, ...

The "pre" callback is run first. Its only argument is the actual step hash.

Then, if the "name" fiels is a code reference, that callback is run and its
actual result is used as the description of the step.

At this stage, the interactive layer is used to display the actual step.

The "post" callback is only run if the user has steped forward.


Alternatively, you can call safe_process() rather than process().
safe_process() will handle for you the "wizcancel" exception while running the
wizard.  Actually, it should be used everywhere but where the wizard is not the
main path (eg "mail alert wizard" in logdrake, ...), ie when you may need to do
extra exception managment such as destroying the wizard window and the like.

=cut


sub new {
    my ($class, $o) = @_;
    bless $o, $class;
}


sub check_rpm {
    my ($in, $rpms) = @_;
    foreach my $rpm (@$rpms) {
        next if $in->do_pkgs->is_installed($rpm);
        if ($in->ask_okcancel(N("Error"), N("%s is not installed\nClick \"Next\" to install or \"Cancel\" to quit", $rpm))) {
            $::testing and next;
            if (!$in->do_pkgs->install($rpm)) {
                local $::Wizard_finished = 1;
                $in->ask_okcancel(N("Error"), N("Installation failed"));
                $in->exit;
            }
        } else { $in->exit }
    }
}


# sync me with interactive::ask_from_normalize() if needed:
my %default_callback = (complete => sub { 0 });


sub process {
    my ($o, $in) = @_;
    local $::isWizard = 1;
    local $::Wizard_title = $o->{name} || $::Wizard_title;
    local $::Wizard_pix_up = $o->{defaultimage} || $::Wizard_pix_up;
    #require_root_capability() if $> && !$o->{allow_user} && !$::testing;
    check_rpm($in, $o->{needed_rpm}) if ref($o->{needed_rpm});
    if (defined $o->{init}) {
        my ($res, $msg) = &{$o->{init}};
        if (!$res) {
            $in->ask_okcancel(N("Error"), $msg);
            die "wizcancel" if !$::testing;
        }
    }
    
    my @steps;             # steps stack

    # initial step:
    my $next = 'welcome';  
    my $page = $o->{pages}{welcome};
    while ($next) {
        local $::Wizard_no_previous = $page->{no_back};
        local $::Wizard_no_cancel = $page->{no_cancel} || $page->{end};
        local $::Wizard_finished = $page->{end};
        defined $page->{pre} and $page->{pre}($page);
        die qq(inexistant "$next" wizard step) if is_empty_hash_ref($page);
        
        # FIXME or the displaying fails
        my $data = defined $page->{data} ? (ref($page->{data}) eq 'CODE' ? $page->{data}->() : $page->{data}) : [];
        my $data2;
        foreach my $d (@$data) {
            $d->{val} = ${$d->{val_ref}} if $d->{val_ref};
            $d->{list} = $d->{list_ref} if $d->{list_ref};
            #$d->{val} = ref($d->{val}) eq 'CODE' ? $d->{val}->() : $d->{val};
            if ($d->{boolean_list}) { 
                my $i;
                foreach (@{$d->{boolean_list}}) { 
                    push @$data2, { text => $_, type => 'bool', val => \${$d->{val}}->[$i], disabled => $d->{disabled} };
                    $i++;
                }
            } else {
                push @$data2, $d;
            }
        }
        my $name = ref($page->{name}) ? $page->{name}->() : $page->{name};
        my %yesno = (yes => N("Yes"), no => N("No"));
        my $yes = ref($page->{default}) eq 'CODE' ? $page->{default}->() : $page->{default};
        $data2 = [ { val => \$yes, type => 'list', list => [ keys %yesno ], format => sub { $yesno{$_[0]} }, 
                     gtk => { use_boxradio => 1 } } ] if $page->{type} eq "yesorno";
        my $a;
        if (ref $data2 eq 'ARRAY' && @$data2) {
            $a = $in->ask_from_({ title => $o->{name}, 
                                 messages => $name, 
                                 (map { $_ => $page->{$_} || $default_callback{$_} } qw(complete)),
                                 if_($page->{interactive_help_id}, interactive_help_id => $page->{interactive_help_id}),
                               }, $data2);
        } else {
            $a = $in->ask_okcancel($o->{name}, $name, $yes || 'ok');
        }
        # interactive->ask_yesorno does not support stepping forward or backward:
        $a = $yes if $a && $page->{type} eq "yesorno";
        if ($a) {
            # step forward:
            push @steps, $next if !$page->{ignore} && $steps[-1] ne $next;
            my $current = $next;
            $next = defined $page->{post} ? $page->{post}($page->{type} eq "yesorno" ? $yes eq 'yes' : $a) : 0;
            return if $page->{end};
            if (!$next) {
                if (!defined $o->{pages}{$next}) {
                    $next = $page->{next};
                } else {
                    die qq(the "$next" page (from previous wizard step) is undefined) if !$next;
                }
            }
            die qq(Step "$current": inexistant "$next" page) if !exists $o->{pages}{$next};
        } else {
            # step back:
            $next = pop @steps;
        }
        $page = $o->{pages}{$next};
    }
}


sub safe_process {
    my ($o, $in) = @_;
    eval { $o->process($in) };
    my $err = $@;
    if ($err =~ /wizcancel/) {
        $in->exit(0);
    } else { 
        die $err if $err;
    }
}

1;
