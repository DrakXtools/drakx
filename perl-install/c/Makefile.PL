use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'c',
    'VERSION_FROM' => 'c.pm', # finds $VERSION
    'LIBS'	=> ['-ldb1 -lz'],   # e.g., '-lm' 
#    'OBJECT'    => 'c.o librpm.a',
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
    'INC'	=> '-Wall',     # e.g., '-I/usr/include/other' 
);
