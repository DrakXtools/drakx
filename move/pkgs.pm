#- $Id$ $

package urpm_pkg;

sub flag_available {
    return 1;
}


package pkgs;
use log;

sub rpmDbOpen {
    #- install_steps:343
}

sub packageByName {
    #- install_steps:344
    return bless {}, 'urpm_pkg';  #- we'll need to call flag_available on it
}

sub selectPackage {
    #- install_steps:344
}

sub packagesToInstall {
    #- install_steps:346
    return ();
}

    
1;
