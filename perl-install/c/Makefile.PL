use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $libs = '-L/usr/X11R6/lib -lX11 -lgdk -lXxf86misc';

$libs .= ' -lrpm -ldb1 -lz' if $ENV{C_RPM};

WriteMakefile(
    'NAME'	=> 'stuff',
    'OPTIMIZE'  => '-Os',
    'MAKEFILE'  => 'Makefile_c',
    'OBJECT'    => 'stuff.o smp.o md5.o md5_crypt.o sbus.o',
    'VERSION_FROM' => 'stuff.pm', # finds $VERSION
    'LIBS'	=> [$libs],   # e.g., '-lm' 
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
    'INC'	=> '-I/usr/include/rpm `gtk-config --cflags`',     # e.g., '-I/usr/include/other' 
);
