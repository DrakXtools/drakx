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
  selectLanguage     => [ N_("Choose your language"), 1, 1, '', '', 'language' ],
  acceptLicense      => [ N_("License"), 1, 1, '', '', '' ],
  selectMouse        => [ N_("Configure mouse"), 1, 1, '1', '', 'mouse' ],
  setupSCSI          => [ N_("Hard drive detection"), 1, 0, '1', '', 'harddrive' ],
  selectInstallClass => [ N_("Select installation class"), 1, 1, '1', '', '' ],
  selectKeyboard     => [ N_("Choose your keyboard"), 1, 1, '1', "selectInstallClass", 'keyboard' ],
  miscellaneous      => [ N_("Security"), 1, 1, '', '', 'security' ],
  doPartitionDisks   => [ N_("Partitioning"), 1, 0, '', "selectInstallClass", 'partition' ],
  formatPartitions   => [ N_("Format partitions"), 1, -1, '1', "doPartitionDisks", 'partition' ],
  choosePackages     => [ N_("Choose packages to install"), 1, -2, '!$::expert', "formatPartitions", 'partition' ],
  installPackages    => [ N_("Install system"), 1, -1, '', ["formatPartitions", "selectInstallClass"], '' ],
  setRootPassword    => [ N_("Set root password"), 1, 1, '', "installPackages", 'rootpasswd' ],
  addUser            => [ N_("Add a user"), 1, 1, '', "installPackages", 'user' ],
  configureNetwork   => [ N_("Configure networking"), 1, 1, '1', "formatPartitions", 'network' ],
  setupBootloader    => [ N_("Install bootloader"), 1, 0, '', "installPackages", 'bootloader' ],
  configureX         => [ N_("Configure X"), 1, 1, '1', ["formatPartitions", "setupBootloader"], 'X' ],
  summary            => [ N_("Summary"), 1, 0, '', "installPackages", 'summary' ],
  configureServices  => [ N_("Configure services"), 1, 1, '!$::expert', "installPackages", 'services' ],
if_(arch() !~ /alpha/ && arch() !~ /ppc/,
  createBootdisk     => [ N_("Create a bootdisk"), 1, 0, '', "installPackages", 'bootdisk' ],
),
  installUpdates     => [ N_("Install system updates"), 1, 1, '',  ["installPackages", "configureNetwork", "summary"], '' ],
  exitInstall        => [ N_("Exit install"), 0, 0, '', '', 'exit' ],
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
