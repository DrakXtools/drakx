use ExtUtils::MakeMaker;
use MDK::Common;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $lib = arch() =~ /x86_64/ ? 'lib64' : 'lib';

WriteMakefile(
    'NAME'	=> 'main',
    'MAKEFILE'  => 'Makefile_c',
    'OPTIMIZE'  => '-Os',
    'VERSION_FROM' => 'main.pm', # finds $VERSION
    'LIBS'	=> ["-L/usr/X11R6/$lib -lX11 -lXext -lXxf86misc"],
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
);
