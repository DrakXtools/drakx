use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'c',
    'VERSION_FROM' => 'c.pm', # finds $VERSION
    'LIBS'	=> ['-lrpm -ldb1 -lz -L/usr/X11R6/lib -lX11 -lgdk'],   # e.g., '-lm' 
#    'OBJECT'    => 'c.o librpm.a',
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
    'INC'	=> '-Wall `gtk-config --cflags`',     # e.g., '-I/usr/include/other' 
);
