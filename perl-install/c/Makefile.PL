use MDK::Common;
use ExtUtils::MakeMaker;
use Config;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $lib = arch() =~ /x86_64/ ? 'lib64' : 'lib';

my $libs = '-lldetect';

my $pcmcia_dir = $Config{archname} =~ /i.86/ ? '../../mdk-stage1/pcmcia_' : '';

symlink "$pcmcia_dir/probe.c", "probe.c" if $pcmcia_dir;

WriteMakefile(
    'NAME'	=> 'stuff',
    'OPTIMIZE'  => '-Os',
    'MAKEFILE'  => 'Makefile_c',
    'OBJECT'    => "stuff.o sbus.o silo.o " . ($pcmcia_dir && " probe.o"),
    'VERSION_FROM' => 'stuff.pm', # finds $VERSION
    'LIBS'	=> [$libs],   # e.g., '-lm' 
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
    'INC'	=> ($pcmcia_dir && " -I$pcmcia_dir -I$pcmcia_dir/.."), 
);
