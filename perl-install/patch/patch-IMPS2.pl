use install_gtk;
package install_gtk;

my $old_createXconf = \&createXconf;
undef *createXconf;
*createXconf = sub {
    symlink 'mouse', '/dev/cdrom';
    &$old_createXconf;
}
