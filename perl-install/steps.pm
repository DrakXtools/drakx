package steps;

use strict;
use vars qw(%installSteps @orderedInstallSteps);
use common;

#-######################################################################################
#- Steps table
#-######################################################################################
{
    my @installStepsFields = qw(text redoable onError hidden needs); 
    #entered reachable toBeDone next done;
    my @installSteps = (
  selectLanguage     => [ N_("Choose your language"), 1, 1, '', '' ],
  acceptLicense      => [ N_("License"), 1, -1, '', '' ],
  selectMouse        => [ N_("Configure mouse"), 1, 1, '1', '' ],
  setupSCSI          => [ N_("Hard drive detection"), 1, 0, '1', '' ],
  selectInstallClass => [ N_("Select installation class"), 1, 1, '1', '' ],
  selectKeyboard     => [ N_("Choose your keyboard"), 1, 1, '1' ],
  miscellaneous      => [ N_("Security"), 1, 1, '', '' ],
  doPartitionDisks   => [ N_("Partitioning"), 1, 0, '', "selectInstallClass" ],
  formatPartitions   => [ N_("Format partitions"), 1, -1, '1', "doPartitionDisks" ],
  choosePackages     => [ N_("Choose packages to install"), 1, -2, '!$::expert', "formatPartitions" ],
  installPackages    => [ N_("Install system"), 1, -1, '', ["formatPartitions", "selectInstallClass"] ],
  setRootPassword    => [ N_("Set root password"), 1, 1, '', "installPackages" ],
  addUser            => [ N_("Add a user"), 1, 1, '', "installPackages" ],
  configureNetwork   => [ N_("Configure networking"), 1, 1, '1', "formatPartitions" ],
  setupBootloader    => [ N_("Install bootloader"), 1, 0, '', "installPackages" ],
  configureX         => [ N_("Configure X"), 1, 1, '1', ["formatPartitions", "setupBootloader"] ],
  summary            => [ N_("Summary"), 1, 0, '', "installPackages" ],
  configureServices  => [ N_("Configure services"), 1, 1, '!$::expert', "installPackages" ],
  installUpdates     => [ N_("Install system updates"), 1, 1, '',  ["installPackages", "configureNetwork", "summary"] ],
  exitInstall        => [ N_("Exit install"), 0, 0, '', '' ],
);
    for (my $i = 0; $i < @installSteps; $i += 2) {
	my %h; @h{@installStepsFields} = @{ $installSteps[$i + 1] };
	$h{next}    = $installSteps[$i + 2];
	$h{entered} = 0;
	$h{onError} = $installSteps[$i + 2 * $h{onError}];
	$h{reachable} = !$h{needs};
	$installSteps{$installSteps[$i]} = \%h;
	push @orderedInstallSteps, $installSteps[$i];
    }
    $installSteps{first} = $installSteps[0];
}


1;
