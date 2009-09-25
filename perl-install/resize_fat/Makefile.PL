use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    'MAKEFILE'  => 'Makefile_c',
    'NAME'	=> 'c_rewritten',
    'OPTIMIZE'  => '-Os',
    'VERSION_FROM' => 'c_rewritten.pm', # finds $VERSION
    'LIBS'	=> '',   # e.g., '-lm' 
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
    'INC'	=> '',     # e.g., '-I/usr/include/other' 
);
