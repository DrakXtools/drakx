use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $libs = '-lldetect';
$libs .= ' -L/usr/X11R6/lib -lX11 -lgdk -lXxf86misc' if $ENV{C_DRAKX};
$libs .= ' -lrpm -lrpmio -lz' if $ENV{C_RPM};

my $pcmcia_dir = '../../mdk-stage1/pcmcia';

WriteMakefile(
    'NAME'	=> 'stuff',
    'OPTIMIZE'  => '-Os',
    'MAKEFILE'  => 'Makefile_c',
    'OBJECT'    => "stuff.o smp.o sbus.o silo.o $pcmcia_dir/pcmcia_probe.o",
    'VERSION_FROM' => 'stuff.pm', # finds $VERSION
    'LIBS'	=> [$libs],   # e.g., '-lm' 
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
    'INC'	=> "-I/usr/include/rpm -I$pcmcia_dir `gtk-config --cflags` `glib-config --cflags`",     # e.g., '-I/usr/include/other' 
);
