package install::steps_list;

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
  selectLanguage     => [
      #-PO: please keep the following messages very short: they must fit in the left list of the installer!!!
      N_("_: Keep these entry short\nLanguage"), 1, 1, '', '' ],
  acceptLicense      => [ N_("_: Keep these entry short\nLicense"), 1, -1, '', '' ],
  selectMouse        => [ N_("_: Keep these entry short\nMouse"), 1, 1, '1', '' ],
  setupSCSI          => [ N_("_: Keep these entry short\nHard drive detection"), 1, 0, '1', '' ],
  selectInstallClass => [ N_("_: Keep these entry short\nInstallation class"), 1, 1, '1', '' ],
  selectKeyboard     => [ N_("_: Keep these entry short\nKeyboard"), 1, 1, '1' ],
  miscellaneous      => [ N_("_: Keep these entry short\nSecurity"), 1, 1, '', '' ],
  doPartitionDisks   => [ N_("_: Keep these entry short\nPartitioning"), 1, 0, '', "selectInstallClass" ],
  formatPartitions   => [ N_("_: Keep these entry short\nFormatting"), 1, -1, '1', "doPartitionDisks" ],
  choosePackages     => [ N_("_: Keep these entry short\nChoosing packages"), 1, -2, '1', "formatPartitions" ],
  installPackages    => [ N_("_: Keep these entry short\nInstalling"), 1, -1, '', ["formatPartitions", "selectInstallClass"] ],
  setRootPassword    => [ N_("_: Keep these entry short\nAuthentication"), 1, 1, '', "installPackages" ],
  addUser            => [ N_("_: Keep these entry short\nUsers"), 1, 1, '', "installPackages" ],
  configureNetwork   => [ N_("_: Keep these entry short\nNetworking"), 1, 1, '1', "formatPartitions" ],
  setupBootloader    => [ N_("_: Keep these entry short\nBootloader"), 1, 0, '', "installPackages" ],
  configureX         => [ N_("_: Keep these entry short\nConfigure X"), 1, 1, '1', ["formatPartitions", "setupBootloader"] ],
  summary            => [ N_("_: Keep these entry short\nSummary"), 1, 0, '', "installPackages" ],
  configureServices  => [ N_("_: Keep these entry short\nServices"), 1, 1, '1', "installPackages" ],
  installUpdates     => [ N_("_: Keep these entry short\nUpdates"), 1, 1, '',  ["installPackages", "configureNetwork", "summary"] ],
  exitInstall        => [ N_("_: Keep these entry short\nExit"), 0, 0, '', '' ],
);
    for (my $i = 0; $i < @installSteps; $i += 2) {
	my %h; @h{@installStepsFields} = @{ $installSteps[$i + 1] };
	$h{entered} = 0;
	$h{onError} = $installSteps[$i + 2 * $h{onError}];
	$h{reachable} = !$h{needs};
	$installSteps{$installSteps[$i]} = \%h;
	push @orderedInstallSteps, $installSteps[$i];
    }
    $installSteps{first} = $installSteps[0];
}


1;
