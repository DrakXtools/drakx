package install::steps_list;

use strict;
use vars qw(%installSteps @orderedInstallSteps);
use common;

#-######################################################################################
#- Steps table
#-######################################################################################
{
    my @installStepsFields = qw(text redoable onError hidden needs banner_icon banner_title); 
    #entered reachable toBeDone next done;
    my @installSteps = (
  selectLanguage     => [
      #-PO: please keep the following messages very short: they must fit in the left list of the installer!!!
      N_("_: Keep these entry short\nLanguage"), 1, 1, '', '', 'banner-languages', N("Localization") ],
  acceptLicense      => [ N_("_: Keep these entry short\nLicense"), 1, -1, '', '', 'banner-license', N("License agreement") ],
  selectMouse        => [ N_("_: Keep these entry short\nMouse"), 1, 1, '1', '' ],
  setupSCSI          => [ N_("_: Keep these entry short\nHard drive detection"), 1, 0, '1', '' ],
  selectInstallClass => [ N_("_: Keep these entry short\nInstallation class"), 1, 1, '1', '',
                          'banner-sys', N("_: Keep these entry short\nInstallation class") ],
  selectKeyboard     => [ N_("_: Keep these entry short\nKeyboard"), 1, 1, '1', 'banner-languages', N("Localization") ],
  miscellaneous      => [ N_("_: Keep these entry short\nSecurity"), 1, 1, '1', '' ],
  doPartitionDisks   => [ N_("_: Keep these entry short\nPartitioning"), 1, 0, '', "selectInstallClass",
                          'banner-part', N("Partitioning") ],
  formatPartitions   => [ N_("_: Keep these entry short\nFormatting"), 1, -1, '1', "doPartitionDisks" ],
  choosePackages     => [ N_("_: Keep these entry short\nChoosing packages"), 1, -2, '1', "formatPartitions",
                          'banner-sys', N("Package Group Selection") ],
  installPackages    => [ N_("_: Keep these entry short\nInstalling"), 1, -1, '', ["formatPartitions", "selectInstallClass"],
                          'banner-sys', N("Installing") ],
  setRootPassword_addUser
                     => [ N_("_: Keep these entry short\nUsers"), 1, 1, '', "installPackages" ],
  configureNetwork   => [ N_("_: Keep these entry short\nNetworking"), 1, 1, '1', "formatPartitions" ],
  setupBootloader    => [ N_("_: Keep these entry short\nBootloader"), 1, 0, '', "installPackages",
                          'banner-bootL', N("_: Keep these entry short\nBootloader")  ],
  configureX         => [ N_("_: Keep these entry short\nConfigure X"), 1, 1, '1', ["formatPartitions", "setupBootloader"] ],
  summary            => [ N_("_: Keep these entry short\nSummary"), 1, 0, '', "installPackages",
                          'banner-summary', N("Summary") ],
  configureServices  => [ N_("_: Keep these entry short\nServices"), 1, 1, '1', "installPackages" ],
  installUpdates     => [ N_("_: Keep these entry short\nUpdates"), 1, 1, '',
                          ["installPackages", "configureNetwork", "summary"], 'banner-update', N("Updates") ],
  exitInstall        => [ N_("_: Keep these entry short\nExit"), 0, 0, '', '', 'banner-exit', N("Exit")  ],
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
