use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $libs = '-L/usr/X11R6/lib -lX11 -lgdk';

$libs .= ' -lrpm -ldb1 -lz' if $ENV{C_RPM};

WriteMakefile(
    'NAME'	=> 'c',
    'OPTIMIZE'  => '-Os',
    'VERSION_FROM' => 'c.pm', # finds $VERSION
    'LIBS'	=> [$libs],   # e.g., '-lm' 
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
    'INC'	=> '-I/usr/include/rpm `gtk-config --cflags`',     # e.g., '-I/usr/include/other' 
);
