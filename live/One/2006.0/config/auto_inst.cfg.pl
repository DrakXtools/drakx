#!/usr/bin/perl -cw
# 
# You should check the syntax of this file before using it in an auto-install.
# You can do this with 'perl -cw auto_inst.cfg.pl' or by executing this file
# (note the '#!/usr/bin/perl -cw' on the first line).
$o = {
       'rpmsrate_flags_chosen' => {
           # office
           CAT_OFFICE => 1,
           CAT_SPELLCHECK => 1,
           CAT_PUBLISHING => 1,
           CAT_PIM => 1,
           CAT_ARCHIVING => 1,
           CAT_PRINTER => 1,
           # multimedia
           CAT_AUDIO => 1,
           CAT_GRAPHICS => 1,
           CAT_VIDEO => 1,
           # internet
           CAT_NETWORKING_WWW => 1,
           CAT_NETWORKING_MAIL => 1,
           CAT_NETWORKING_NEWS => 1,
           CAT_COMMUNICATIONS => 1,
           CAT_NETWORKING_CHAT => 1,
           CAT_NETWORKING_FILE_TRANSFER => 1,
           CAT_NETWORKING_IRC => 1,
           CAT_NETWORKING_INSTANT_MESSAGING => 1,
           CAT_NETWORKING_DNS => 1,
           # network
           CAT_NETWORKING_REMOTE_ACCESS => 1,
           CAT_NETWORKING_FILE => 1,
           # config
           CAT_CONFIG => 1,
           # console
           CAT_TERMINALS => 1,
           CAT_TEXT_TOOLS => 1,
           CAT_SHELLS => 1,
           CAT_FILE_TOOLS => 1,
           # kde
           CAT_KDE => 1,
           CAT_X => 1,
           CAT_ACCESSIBILITY => 1,
           CAT_THEMES => 1,
           # system
           CAT_SYSTEM => 1,

           # FIXME, use $::o->{build_live_system} for that
           '3D' => 1,
           BURNER => 1,
           DVD => 1,
           PCMCIA => 1,
           TV => 1,
           USB => 1,
           SCANNER => 1,
           # installs Gnome packages only, not suitable for One
           # PHOTO => 1,
       },
       # so that rpmsrate flags are really used
       'compssListLevel' => 4, # default from install_steps_interactive
       'default_packages' => [
                               #- live requirements
                               'drakx-finish-install',
                               'squashfs-tools',
                               'dkms-minimal',

                               #- should be required by live-install
                               'lilo',
                               'grub',
                               # perl -MMDK::Common -e 'my $cmds = eval (`cat /usr/lib/libDrakX/fs/format.pm` . "\\%cmds"); print join(", ", uniq(map { "\"$_->[0]\"" } values %$cmds)) . "\n";' 2>/dev/null
                               "reiserfsprogs", "jfsprogs", "reiser4progs", "hfsutils", "dosfstools", "e2fsprogs", "xfsprogs", "util-linux",
                               # from diskdrake/*.pm
                               'ntfsprogs',
                               'davfs',

                               #- should be required by draklive copy wizard
                               'syslinux',
                               'cdrecord',
                               'rsync',
                               'mtools',

                               #- printerdrake/scannerdrake related
                               'gutenprint-gimp2',
                               'foomatic-filters',
                               'foomatic-db',
                               'foomatic-db-hpijs',
                               'foomatic-db-engine',
                               'printer-filters',
                               'printer-utils',
                               'printer-testpages',
                               'ghostscript',
                               'hplip-hpijs',
                               'gutenprint-ijs',
                               'gutenprint-foomatic',
                               'gutenprint-escputil',
                               'postscript-ppds',
                               'hplip-model-data',
                               'nmap',
                               'scli',
                               'cups',
                               'net-tools',
                               'xpp',
                               'cups-drivers',
                               'gutenprint-cups',
                               'curl',
                               'cups-common',
                               'samba-client',
                               'nc',
                               'hplip',
                               'sane-backends',
                               'xsane',
                               'libsane-hpaio1',
                               'usbutils',
                               'ImageMagick',
                               'libhpip0',
                               'xinetd',
                               'saned',
                               'kdegraphics-kooka',

                               #- drakclock
                               'ntp',

                               #- finish-install (network)
                               'zcip', 'tmdns',

                               #- useful packages
                               'ndiswrapper',
                               'xmoto',
			     ],
       # explicitely specify the security level, so that environment of the build machine doesn't take precedence
       'security' => 3,
       'useSupermount' => 'magicdev',
       'users' => [
		    {
		      'icon' => 'default',
		      'realname' => '',
		      'uid' => '',
		      'groups' => [],
		      'name' => 'guest',
		      'shell' => '/bin/bash',
		      'gid' => ''
		    }
		  ],
       'locale' => {
                     'country' => 'US',
                     'IM' => undef,
                     'lang' => 'en_US',
                     'utf8' => 1
                   },
       'authentication' => {
			     'shadow' => 1,
			     'local' => 1,
			     'md5' => 1
			   },
       'superuser' => {
			'pw' => '',
			'realname' => 'root',
			'uid' => '0',
			'shell' => '/bin/bash',
			'home' => '/root',
			'gid' => '0'
		      },
       'keyboard' => {
		       'GRP_TOGGLE' => '',
		       'KBCHARSET' => 'C',
		       'KEYBOARD' => 'us',
		       'KEYTABLE' => 'us'
		     },
       'timezone' => {
		       'ntp' => undef,
		       'timezone' => 'America/New_York',
		       'UTC' => 1
		     },
       'X' => {},
       'partitioning' => {
			   'auto_allocate' => '',
			   'clearall' => 0,
			   'eraseBadPartitions' => 0
			 },
       #- doc takes too much place
       'excludedocs' => 1,
       'postInstall' => join(";",
                             #- do not modify it the standard way, since the behaviour would be unexpected during install
                             "perl -pi -e 's/META_CLASS=.*/META_CLASS=one/' /etc/sysconfig/system",
                             #- try not to run kat a second time when running kde apps as root (#21308)
                             "touch /root/.mdv-no_kat"),
     };
