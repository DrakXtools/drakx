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
                                                # returned value is next step name (it overrides "next" field)
                             end => ,       # is it the last step ?
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


# sync me with interactive::ask_from_normalize() if needed:
my %default_callback = (changed => sub {}, focus_out => sub {}, complete => sub { 0 }, canceled => sub { 0 }, advanced => sub {});


sub process {
    my ($_w, $o, $in) = @_;
    local $::isWizard = 1;
    local $::Wizard_title = $o->{name} || $::Wizard_title;
    local $::Wizard_pix_up = $o->{defaultimage} || $::Wizard_pix_up;
    #require_root_capability() if $> && !$o->{allow_user} && !$::testing;
    check_rpm($in, $o->{needed_rpm}) if ref($o->{needed_rpm});
    if (defined $o->{init}) {
        my ($res, $msg) = &{$o->{init}};
        if (!$res) {
            $in->ask_okcancel(N("Error"), $msg);
            die "wizard failled" if !$::testing
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
        print qq(STEPPING "$next"\n);
        defined $page->{pre} and $page->{pre}($page);
        die qq(inexistant "$next" wizard step) if is_empty_hash_ref($page);
        
        # FIXME or the displaying fails
        my $data = defined $page->{data} ? (ref($page->{data}) eq 'CODE' ? $page->{data}->() : $page->{data}) : [ { label => '' } ];
        my $data2;
        foreach my $d (@$data) {
            $d->{val} = ${$d->{val_ref}} if $d->{val_ref};
            $d->{list} = $d->{list_ref} if $d->{list_ref};
            #$d->{val} = ref($d->{val}) eq 'CODE' ? $d->{val}->() : $d->{val};
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
        my $name = ref($page->{name}) ? $page->{name}->() : $page->{name};
        #use Data::Dumper; print Dumper([ $name, $data2 ]);
        my $a = $in->ask_from_({ title => $o->{name}, 
                                 messages => $name, 
                                 callbacks => { map { $_ => $page->{$_} || $default_callback{$_} } qw(focus_out complete) },
                                 if_($page->{interactive_help_id}, interactive_help_id => $page->{interactive_help_id}),
                               }, $data2);
        print "WIZGOT ($a)\n";
        if ($a) {
            print "FORWARD($a)\n";
            # step forward:
            push @steps, $next if !$page->{ignore} && $steps[-1] ne $next;
            my $current = $next;
            $next = defined $page->{post} ? $page->{post}($a) : 0;
            # or add a field end => 1
            return if $current eq "end";
            if (!$next) {
                if (!defined $o->{pages}{$next}) {
                    $next = $page->{next};
                } else {
                    die qq(the "$next" page (from previous wizard step) is undefined) if !$next;
                }
            }
            die qq(Step "$current": inexistant "$next" page) if !exists $o->{pages}{$next};
            print qq(GOING from "$current" to "$next"\n);
        } else {
            print "BACKWARD\n";
            # step back:
            $next = pop @steps
        }
        $page = $o->{pages}{$next}
    }
}


sub safe_process {
    my ($w, $wiz, $in) = @_;
    eval { $w->process($wiz, $in) };
    my $err = $@;
    if ($err =~ /wizcancel/) {
        $in->exit(0);
    } else { 
        die $err if $err;
    }
}

1;
