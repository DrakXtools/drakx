package steps;

use strict;
use vars qw(%installSteps @orderedInstallSteps);
use common;

#-######################################################################################
#- Steps table
#-######################################################################################
{
    my @installStepsFields = qw(text redoable onError hidden needs icon); 
    #entered reachable toBeDone next done;
    my @installSteps = (
  selectLanguage     => [ __("Choose your language"), 1, 1, '', '', 'default' ],
  selectInstallClass => [ __("Select installation class"), 1, 1, '', '', 'default' ],
  setupSCSI          => [ __("Hard drive detection"), 1, 0, '', '', 'harddrive' ],
  selectMouse        => [ __("Configure mouse"), 1, 1, '', "selectInstallClass", 'mouse' ],
  selectKeyboard     => [ __("Choose your keyboard"), 1, 1, '', "selectInstallClass", 'keyboard' ],
  miscellaneous      => [ __("Security"), 1, 1, '!$::expert', '', 'security' ],
  doPartitionDisks   => [ __("Setup filesystems"), 1, 0, '', "selectInstallClass", 'default' ],
  formatPartitions   => [ __("Format partitions"), 1, -1, '$o->{isUpgrade}', "doPartitionDisks", 'default' ],
  choosePackages     => [ __("Choose packages to install"), 1, -2, '!$::expert', "formatPartitions", 'default' ],
  installPackages    => [ __("Install system"), 1, -1, '', ["formatPartitions", "selectInstallClass"], '' ],
  setRootPassword    => [ __("Set root password"), 1, 1, '', "installPackages", 'rootpasswd' ],
  addUser            => [ __("Add a user"), 1, 1, '', "installPackages", 'user' ],
  configureNetwork   => [ __("Configure networking"), 1, 1, '', "formatPartitions", 'network' ],
  summary            => [ __("Summary"), 1, 0, '', "installPackages", 'default' ],
  configureServices  => [ __("Configure services"), 1, 1, '!$::expert', "installPackages", 'services' ],
if_((arch() !~ /alpha/) && (arch() !~ /ppc/),
  createBootdisk     => [ __("Create a bootdisk"), 1, 0, '', "installPackages", 'bootdisk' ],
),
  setupBootloader    => [ __("Install bootloader"), 1, 1, '', "installPackages", 'bootloader' ],
  configureX         => [ __("Configure X"), 1, 1, '', ["formatPartitions", "setupBootloader"], 'X' ],
  exitInstall        => [ __("Exit install"), 0, 0, '!$::expert && !$::live', '', 'default' ],
);
    for (my $i = 0; $i < @installSteps; $i += 2) {
	my %h; @h{@installStepsFields} = @{ $installSteps[$i + 1] };
	$h{next}    = $installSteps[$i + 2];
	$h{entered} = 0;
	$h{onError} = $installSteps[$i + 2 * $h{onError}];
	$h{reachable} = !$h{needs};
	$installSteps{ $installSteps[$i] } = \%h;
	push @orderedInstallSteps, $installSteps[$i];
    }
    $installSteps{first} = $installSteps[0];
}


#- Wonderful perl :(
1;
