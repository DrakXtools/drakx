use common;

log::l("PATCHING: installing mo");
my $dir = '/usr/share/locale_special/da/LC_MESSAGES';
mkdir_p($dir);
system("gzip -dc /mnt/da_mo.gz > $dir/libDrakX.mo");
