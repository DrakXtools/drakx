use ExtUtils::MakeMaker;
use Config;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $libs = '-lldetect -lext2fs';
$libs .= ' -L/usr/X11R6/lib -lX11 -lgdk -lXxf86misc' if $ENV{C_DRAKX};
$libs .= ' -lrpm -lrpmdb -lrpmio -lpopt -lz' if $ENV{C_RPM};

my $pcmcia_dir = $ENV{C_DRAKX} && $Config{archname} =~ /i.86/ ? '../../mdk-stage1/pcmcia_' : '';

symlink "$pcmcia_dir/probe.c", "probe.c" if $pcmcia_dir;

WriteMakefile(
    'NAME'	=> 'stuff',
    'OPTIMIZE'  => '-Os',
    'MAKEFILE'  => 'Makefile_c',
    'OBJECT'    => "stuff.o smp.o sbus.o silo.o" . ($pcmcia_dir && " probe.o"),
    'VERSION_FROM' => 'stuff.pm', # finds $VERSION
    'LIBS'	=> [$libs],   # e.g., '-lm' 
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
    'INC'	=> "-I/usr/include/rpm `gtk-config --cflags` `glib-config --cflags`" . ($pcmcia_dir && " -I$pcmcia_dir -I$pcmcia_dir/.."), 
);
