package install::steps_list;

use strict;
use vars qw(%installSteps @orderedInstallSteps);
use common;

#-######################################################################################
#- Steps table
#-######################################################################################
{
    my @installStepsFields = qw(text redoable onError hidden needs banner_title); 
    #entered reachable toBeDone next done;
    my @installSteps = (
  selectLanguage     => [
      #-PO: please keep the following messages very short: they must fit in the left list of the installer!!!
      N_("_: Keep these entry short\nLanguage"), 1, 1, '', '', N_("Localization") ],
  acceptLicense      => [ N_("_: Keep these entry short\nLicense"), 1, -1, '', '', N_("License agreement") ],
  selectMouse        => [ N_("_: Keep these entry short\nMouse"), 1, 1, '1', '', N_("Mouse") ],
  setupSCSI          => [ N_("_: Keep these entry short\nHard drive detection"), 1, 0, '1', '',
                          N_("_: Keep these entry short\nHard drive detection") ],
  selectInstallClass => [ N_("_: Keep these entry short\nInstallation class"), 1, 1, '1', '',
                          N_("_: Keep these entry short\nInstallation class") ],
  selectKeyboard     => [ N_("_: Keep these entry short\nKeyboard"), 1, 1, '1', '', N_("Localization") ],
  miscellaneous      => [ N_("_: Keep these entry short\nSecurity"), 1, 1, '1', '', N_("Security") ],
  doPartitionDisks   => [ N_("_: Keep these entry short\nPartitioning"), 1, 0, '', "selectInstallClass",
                          N_("Partitioning") ],
  formatPartitions   => [ N_("_: Keep these entry short\nFormatting"), 1, -1, '1', "doPartitionDisks",
                          N_("_: Keep these entry short\nFormatting") ],
  choosePackages     => [ N_("_: Keep these entry short\nChoosing packages"), 1, -2, '1', "formatPartitions",
                          N_("Package Group Selection") ],
  installPackages    => [ N_("_: Keep these entry short\nInstalling"), 1, -1, '', ["formatPartitions", "selectInstallClass"],
                          N_("Installing") ],
  setRootPassword_addUser
                     => [ N_("_: Keep these entry short\nUsers"), 1, 1, '', "installPackages",
                          N_("User management") ],
  configureNetwork   => [ N_("_: Keep these entry short\nNetworking"), 1, 1, '1', "formatPartitions",
                          N_("_: Keep these entry short\nNetworking") ],
  setupBootloader    => [ N_("_: Keep these entry short\nBootloader"), 1, 0, '', "installPackages",
                          N_("_: Keep these entry short\nBootloader")  ],
  configureX         => [ N_("_: Keep these entry short\nConfigure X"), 1, 1, '1', ["formatPartitions", "setupBootloader"],
                      N_("_: Keep these entry short\nConfigure X") ],
  summary            => [ N_("_: Keep these entry short\nSummary"), 1, 0, '', "installPackages",
                          N_("Summary") ],
  configureServices  => [ N_("_: Keep these entry short\nServices"), 1, 1, '1', "installPackages",
                          N_("_: Keep these entry short\nServices") ],
  installUpdates     => [ N_("_: Keep these entry short\nUpdates"), 1, 1, '',
                          ["installPackages", "configureNetwork", "summary"], N_("Updates") ],
  exitInstall        => [ N_("_: Keep these entry short\nExit"), 0, 0, '', '', N_("Exit")  ],
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
