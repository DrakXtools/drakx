use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

WriteMakefile(
    'NAME'	=> 'Newt',
    'OBJECT'    => 'Av_CharPtrPtr.o Newt.o',
    'MAKEFILE'  => 'Makefile_c',
    'OPTIMIZE'  => '-Os',
    'VERSION_FROM' => 'Newt.pm', # finds $VERSION
    'LIBS'	=> ['-lnewt -lslang'],
    'DEFINE'	=> '',     # e.g., '-DHAVE_SOMETHING' 
);
