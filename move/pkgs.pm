package pkg;

sub flag_available {
    return 1;
}


package pkgs; # $Id$ $
use log;

sub rpmDbOpen {
    #- install_steps:343
}

sub packageByName {
    #- install_steps:344
    return bless {}, 'pkg';
}

sub selectPackage {
    #- install_steps:344
}

sub packagesToInstall {
    #- install_steps:346
    return ();
}

    
1;
