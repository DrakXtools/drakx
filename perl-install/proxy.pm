package proxy;

sub main {
    my ($prefix, $in, $install) = @_;
  begin:
    $::Wizard_no_previous = 1;
    $in->ask_okcancel(_("Proxy configuration"), _("blabla proxy"), 1) or quit_global($in, 0);
    my $url = $in->ask_from_entry($url, _("foo"), _("url"));
    print STDERR $url, "\n";
    undef $::Wizard_no_previous;
    log::l("[drakproxy] Installation complete, exiting\n");
}

#---------------------------------------------
#                WONDERFULL pad
#---------------------------------------------
1;
