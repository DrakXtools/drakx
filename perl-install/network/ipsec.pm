package network::ipsec;



use detect_devices;
use run_program;
use common;
use log;

#- debugg functions ----------
sub recreate_ipsec_conf {
	my ($ipsec, $kernel_version) = @_;
	if ($kernel_version < 2.5) {
	#- kernel 2.4 part -------------------------------
		foreach my $key1 (ikeys %$ipsec) {
			print "$ipsec->{$key1}\n" if ! $ipsec->{$key1}{1};
			foreach my $key2 (ikeys %{$ipsec->{$key1}}) {
				if ($ipsec->{$key1}{$key2}[0] =~ m/^#/) {
					print "\t$ipsec->{$key1}{$key2}[0]\n";
				} elsif ($ipsec->{$key1}{$key2}[0] =~ m/(conn|config|version)/) {
					print "$ipsec->{$key1}{$key2}[0] $ipsec->{$key1}{$key2}[1]\n";
				} else {
					print "\t$ipsec->{$key1}{$key2}[0]=$ipsec->{$key1}{$key2}[1]\n";
				}
			}
		}
	} else { 
	#- kernel 2.6 part -------------------------------
		foreach my $key1 (ikeys %$ipsec) {
			if (! $ipsec->{$key1}{command}) {
				print "$ipsec->{$key1}\n";
			} else {	
				print 	$ipsec->{$key1}{command} . " " .
					$ipsec->{$key1}{src_range} . " " .
					$ipsec->{$key1}{dst_range} . " " .
					$ipsec->{$key1}{upperspec} . " " .
					$ipsec->{$key1}{flag} . " " .
					$ipsec->{$key1}{direction} . " " .
					$ipsec->{$key1}{ipsec} . "\n\t" .
					$ipsec->{$key1}{protocol} . "/" .
					$ipsec->{$key1}{mode} . "/" .
					$ipsec->{$key1}{src_dest} . "/" .
					$ipsec->{$key1}{level} . ";\n";
			}
		}
	}
}

sub recreate_racoon_conf {
	my ($racoon) = @_;
	my $in_a_section = "n";
	my $in_a_proposal_section = "n";
	foreach my $key1 (ikeys %$racoon) {
		if ($in_a_proposal_section eq "y") {
			print "\t}\n}\n$racoon->{$key1}\n" if ! $racoon->{$key1}{1};
		} elsif ($in_a_section eq "y") {
			print "}\n$racoon->{$key1}\n" if ! $racoon->{$key1}{1};
		} else {
			print "$racoon->{$key1}\n" if ! $racoon->{$key1}{1};
		}
			$in_a_section = "n";
			$in_a_proposal_section = "n";
		foreach my $key2 (ikeys %{$racoon->{$key1}}) {
			 if ($racoon->{$key1}{$key2}[0] =~ /^path/) {
				print "$racoon->{$key1}{$key2}[0] $racoon->{$key1}{$key2}[1] $racoon->{$key1}{$key2}[2];\n";
			 } elsif ($racoon->{$key1}{$key2}[0] =~ /^remote/) {
				$in_a_section = "y";
				$in_a_proposal_section = "n";
				print "$racoon->{$key1}{$key2}[0] $racoon->{$key1}{$key2}[1] {\n";
			 } elsif ($racoon->{$key1}{$key2}[0] =~ /^sainfo/) {
				$in_a_section = "y";
				$in_a_proposal_section = "n";
				if ($racoon->{$key1}{$key2}[2] && $racoon->{$key1}{$key2}[5]) {
					print  "$racoon->{$key1}{$key2}[0] $racoon->{$key1}{$key2}[1] $racoon->{$key1}{$key2}[2] $racoon->{$key1}{$key2}[3] $racoon->{$key1}{$key2}[4] $racoon->{$key1}{$key2}[5] $racoon->{$key1}{$key2}[6] {\n";
				} else {
					print "$racoon->{$key1}{$key2}[0] anonymous {\n";
				}
			} elsif ($racoon->{$key1}{$key2}[0] =~ /^proposal /) {
				$in_a_proposal_section = "y";
				print "\t$racoon->{$key1}{$key2}[0] {\n";
			} elsif ($in_a_section eq "y" && $racoon->{$key1}{$key2}[0] =~ /^certificate_type/) {
				print "\t$racoon->{$key1}{$key2}[0] $racoon->{$key1}{$key2}[1] $racoon->{$key1}{$key2}[2] $racoon->{$key1}{$key2}[3];\n";
			} elsif ($in_a_section eq "y" && $racoon->{$key1}{$key2}[0] =~ /^#/) {
				print "\t$racoon->{$key1}{$key2}[0] $racoon->{$key1}{$key2}[1]\n";
			} elsif ($in_a_section eq "y") {
				print "\t$racoon->{$key1}{$key2}[0] $racoon->{$key1}{$key2}[1];\n";
			} elsif ($in_a_proposal_section eq "y" && $racoon->{$key1}{$key2}[0] =~ /^#/) {
				print "\t\t$racoon->{$key1}{$key2}[0] $racoon->{$key1}{$key2}[1]\n";
			} elsif ($in_a_proposal_section eq "y") {
				print "\t\t$racoon->{$key1}{$key2}[0] $racoon->{$key1}{$key2}[1];\n";
			}
		}
	}

print "}\n";
}

sub recreate_ipsec_conf1_k24 {
	my ($ipsec) = @_;
	foreach my $key1 (ikeys %$ipsec) {
	print "$key1-->$ipsec->{$key1}\n" if ! $ipsec->{$key1}{1};
		foreach my $key2 (ikeys %{$ipsec->{$key1}}) {
			if ($ipsec->{$key1}{$key2}[0] =~ m/^#/) {
			print "\t$key2-->$ipsec->{$key1}{$key2}[0]\n";
			} elsif ($ipsec->{$key1}{$key2}[0] =~ m/(conn|config|version)/) {
				print "$key1-->$key2-->$ipsec->{$key1}{$key2}[0] $ipsec->{$key1}{$key2}[1]\n";
			} else {
				print "\t$key2-->$ipsec->{$key1}{$key2}[0]=$ipsec->{$key1}{$key2}[1]\n";
			}
		}
	}
}
#- end of debug functions --------

sub sys { system(@_) == 0 or log::l("[drakvpn] Warning, sys failed for $_[0]") }

sub start_daemons () {
    return if $::testing;
    log::explanations("Starting daemons");
	if (-e "/etc/rc.d/init.d/ipsec") {
   		system("/etc/rc.d/init.d/ipsec status >/dev/null") == 0 and sys("/etc/rc.d/init.d/ipsec stop");
	    sys("/etc/rc.d/init.d/$_ start >/dev/null"), sys("/sbin/chkconfig --level 345 $_ on") foreach 'ipsec';
	} else {

	}
	    sys("/etc/rc.d/init.d/$_ start >/dev/null"), sys("/sbin/chkconfig --level 345 $_ on") foreach 'shorewall';
}

sub stop_daemons () {
    return if $::testing;
    log::explanations("Stopping daemons");
	if (-e "/etc/rc.d/init.d/ipsec") {
    	foreach (qw(ipsec)) {
			system("/etc/rc.d/init.d/$_ status >/dev/null 2>/dev/null") == 0 and sys("/etc/rc.d/init.d/$_ stop");
	    }
		sys("/sbin/chkconfig --level 345 $_ off") && -e "/etc/rc.d/init.d/$_" foreach 'ipsec';
	}
	    system("/etc/rc.d/init.d/shorewall status >/dev/null 2>/dev/null") == 0 and sys("/etc/rc.d/init.d/shorewall stop >/dev/null");

}

sub set_config_file {
    my ($file, @l) = @_;

    my $done;
    substInFile {
	if (!$done && (/^#LAST LINE/ || eof)) {
	    $_ = join('', map { join("\t", @$_) . "\n" } @l) . $_;
	    $done = 1;
	} else {
	    $_ = '' if /^[^#]/;
	}
    } "$::prefix/$file";
}

sub get_config_file {
    my ($file) = @_;
    map { [ split ' ' ] } grep { !/^#/ } cat_("$::prefix/$file");
}


#-------------------------------------------------------------------
#---------------------- configure racoon_conf -----------------------
#-------------------------------------------------------------------

sub read_racoon_conf {
	my ($racoon_conf) = @_;
	my %conf;
	my $nb = 0; #total number
	my $i = 0; #nb within a section 
	my $in_a_section = "n";
	my @line1;
	my $line = "";
	local $_;
	open(my $LIST, "< $racoon_conf"); 
	while (<$LIST>) {
       		chomp($_);
			$line = $_;
			$in_a_section = "n" if $line =~ /}/ && $line !~ /^#/; 
			$line =~ s/^\s+|\s*;|\s*{//g if $line !~ /^#/;
			$line =~ /(.*)#(.*)/ if $line !~ /^#/; #- define before and after comment
#			print "--line-->$line\n";
	                my $data_part = $1;
        	        my $comment_part = "#" . $2;
			if ($data_part) {
				$data_part =~ s/,//g;
#				print "@@".$data_part."->".$comment_part."\n";
				@line1 = split /\s+/,$data_part;
				@line1 = (@line1, $comment_part) if $comment_part;
			} else {
				@line1 = split /\s+/,$line;
			}
			if (!$line && $in_a_section eq "n") {
				$nb++;
				put_in_hash(\%conf, { $nb => $line });
				$in_a_section = "n";
			} elsif (!$line && $in_a_section eq "y") {
				put_in_hash($conf{$nb} ||= {}, { $i => [ '' ] });
				$i++;
			} elsif ($line =~ /^path/) {
				$i=1;
				$nb++;
				put_in_hash($conf{$nb} ||= {}, { $i => [@line1] });
				$in_a_section = "n";
				$i++;
			} elsif ($line =~ /^#|^{|^}/) {
				if ($in_a_section eq "y") {
					put_in_hash($conf{$nb} ||= {}, { $i => [$line] });
					$i++;
				} else {
					$nb++;
					put_in_hash(\%conf, { $nb => $line });
					$in_a_section = "n";
				}
			} elsif ($line =~ /^sainfo|^remote|^listen|^timer|^padding/ && $in_a_section eq "n") {
				$i=1;
				$nb++;
				put_in_hash($conf{$nb} ||= {}, { $i => [@line1] });
				$in_a_section = "y";
				$i++;
			} elsif ($line eq "proposal" && $in_a_section eq "y") {
				$i=1;
				$nb++;
				put_in_hash($conf{$nb} ||= {}, { $i => [@line1] });
				$in_a_section = "y";
				$i++;
			} else {
				put_in_hash($conf{$nb} ||= {}, { $i => [@line1]  });
				$i++;
			}
	}
	
\%conf;
}

sub display_racoon_conf {
	my ($racoon) = @_;
	my $display = "";
	my $prefix_to_simple_line = "";
	foreach my $key1 (ikeys %$racoon) {
		if (!$racoon->{$key1}{1}) {
			$display .= $prefix_to_simple_line . $racoon->{$key1} . "\n";
			$prefix_to_simple_line = "";
		} else {
			foreach my $key2 (ikeys %{$racoon->{$key1}}) {
				my $t = $racoon->{$key1}{1}[0];
				my $f = $racoon->{$key1}{$key2}[0];
				my $list_length = scalar @{$racoon->{$key1}{$key2}};
				my $line = "";
				
				if ($racoon->{$key1}{$key2}[0] eq "sainfo" && !$racoon->{$key1}{$key2}[2]) {
					$line = "sainfo anonymous";
				} else {
					for (my $i = 0; $i <= $list_length-1; $i++) {	

						my $c = $racoon->{$key1}{$key2}[$i];
						my $n = $racoon->{$key1}{$key2}[$i+1];

						if ($c =~ /^path|^log|^timer|^listen|^padding|^remote|^proposal|^sainfo/) {
							$line .= "$c "; 
						} elsif ($i == $list_length-2 && $n =~ /^#/) {
							$line .= "$c; "; 
						} elsif ($i == $list_length-1) {
							if ($f =~ /^#|^$|^timer|^listen|^padding|^remote|^proposal\s+|^sainfo/) {
								$line .= $c; 
							} elsif ($c =~ /^#/) {
								$line .= "\t$c"; 
							} else {
								$line .= "$c;"; 
							}
						} else {
							$line .= "$c "; 
						}
					}
				}
	
				if ($f =~ /^timer|^listen|^padding|^remote|^sainfo/) {
					$line .= " {";
					$prefix_to_simple_line = "";
				} elsif ($f eq "proposal") {
					$line = "\t" . $line . " {";
				} elsif ($t eq "proposal") {
					$line = "\t\t" . $line if $line ne "proposal";
					$prefix_to_simple_line = "\t";
				} else {
					$line = "\t" . $line if $t !~ /^path|^log/;
					$prefix_to_simple_line = "";
				}
				$display .= "$line\n";
			}
		}
	}

$display;

}

sub write_racoon_conf {
	my ($racoon_conf, $racoon) = @_;
	my $display = "";
	my $prefix_to_simple_line = "";
	foreach my $key1 (ikeys %$racoon) {
		if (!$racoon->{$key1}{1}) {
			$display .= $prefix_to_simple_line . $racoon->{$key1} . "\n";
			$prefix_to_simple_line = "";
		} else {
			foreach my $key2 (ikeys %{$racoon->{$key1}}) {
				my $t = $racoon->{$key1}{1}[0];
				my $f = $racoon->{$key1}{$key2}[0];
				my $list_length = scalar @{$racoon->{$key1}{$key2}};
				my $line = "";

				if ($racoon->{$key1}{$key2}[0] eq "sainfo" && !$racoon->{$key1}{$key2}[2]) {
					$line = "sainfo anonymous";
				} else {
					for (my $i = 0; $i <= $list_length-1; $i++) {	
	
						my $c = $racoon->{$key1}{$key2}[$i];
						my $n = $racoon->{$key1}{$key2}[$i+1];
	
						if ($c =~ /^path|^log|^timer|^listen|^padding|^remote|^proposal|^sainfo/) {
							$line .= "$c "; 
						} elsif ($i == $list_length-2 && $n =~ /^#/) {
							$line .= "$c; "; 
						} elsif ($i == $list_length-1) {
							if ($f =~ /^#|^$|^timer|^listen|^padding|^remote|^proposal\s+|^sainfo/) {
								$line .= $c; 
							} elsif ($c =~ /^#/) {
								$line .= "\t$c"; 
							} else {
								$line .= "$c;"; 
							}
						} else {
							$line .= "$c "; 
						}
                          }
				}

				if ($f =~ /^timer|^listen|^padding|^remote|^sainfo/) {
					$line .= " {";
					$prefix_to_simple_line = "";
				} elsif ($f eq "proposal") {
					$line = "\t" . $line . " {";
				} elsif ($t eq "proposal") {
					$line = "\t\t" . $line if $line ne "proposal";
					$prefix_to_simple_line = "\t";
				} else {
					$line = "\t" . $line if $t !~ /^path|^log/;
					$prefix_to_simple_line = "";
				}
				$display .= "$line\n";
			}
		}
	}

open(my $ADD, "> $racoon_conf") or die "Can not open the $racoon_conf file for writing";
	print $ADD "$display\n";

}

sub get_section_names_racoon_conf {
  my ($racoon) = @_;
  my @section_names;

	foreach my $key1 (ikeys %$racoon) {
		if (!$racoon->{$key1}{1}) {
			next;
		} else {
			my $list_length = scalar @{$racoon->{$key1}{1}};
			my $section_title = "";
			my $separator = "";
			for (my $i = 0; $i <= $list_length-1; $i++) {	
				my $s = $racoon->{$key1}{1}[$i];
				if ($s !~ /^#|^proposal/) {
					$section_title .=  $separator . $s;
					$separator = " ";
				}
			}
			push(@section_names, $section_title) if $section_title ne "";
		}
	}

	@section_names;

}

sub add_section_racoon_conf {
	my ($new_section, $racoon) = @_;
	put_in_hash($racoon, { max(keys %$racoon) + 1 => '' });
	put_in_hash($racoon, { max(keys %$racoon) + 1 => $new_section });
	put_in_hash($racoon, { max(keys %$racoon) + 1 => '}' }) if $new_section->{1}[0] !~ /^path|^remote/;
	put_in_hash($racoon, { max(keys %$racoon) + 1 => '' }) if $new_section->{1}[0] =~ /^proposal/;
	put_in_hash($racoon, { max(keys %$racoon) + 1 => '}' }) if $new_section->{1}[0] =~ /^proposal/;
}

sub matched_section_key_number_racoon_conf {
  my ($section_name, $racoon) = @_;
	foreach my $key1 (ikeys %$racoon) {
		if (!$racoon->{$key1}{1}) {
			next;
		} else  {
			my $list_length = scalar @{$racoon->{$key1}{1}};
			my $section_title = "";
			my $separator = "";
			for (my $i = 0; $i <= $list_length-1; $i++) {	
				my $s = $racoon->{$key1}{1}[$i];
				if ($s !~ /^#|^proposal/) {
					$section_title .=  $separator . $s;
					$separator = " ";
				}
			}
			if ($section_title eq $section_name) {
				return $key1;
			}
		}
	}

}

sub already_existing_section_racoon_conf {
  my ($section_name, $racoon, $racoon_conf) = @_;
  if (-e $racoon_conf) {
	foreach my $key1 (ikeys %$racoon) {
		if (!$racoon->{$key1}{1}) {
			next;
		} elsif (find {
			my $list_length = scalar @{$racoon->{$key1}{1}};
			my $section_title = "";
			my $separator = "";
			for (my $i = 0; $i <= $list_length-1; $i++) {	
				my $s = $racoon->{$key1}{1}[$i];
				if ($s !~ /^#|^proposal/) {
					$section_title .=  $separator . $s;
					$separator = " ";
				}
			}

			$section_title eq $section_name;

			} ikeys %{$racoon->{$key1}}) {

			return "already existing";
		}
	}
  }

}

sub remove_section_racoon_conf {
	my ($section_name, $racoon, $k) = @_;
	if ($section_name =~ /^remote/) {

		delete $racoon->{$k} if $k > 1 && !$racoon->{$k-1};
		my $closing_curly_bracket = 0;
		while ($closing_curly_bracket < 2) {
			print "-->$k\n";
			$closing_curly_bracket++ if $racoon->{$k} eq "}"; 
			delete $racoon->{$k};
			$k++;
		}

	} elsif ($section_name =~ /^path/) {

		delete $racoon->{$k};
		delete $racoon->{$k+1} if $racoon->{$k+1}{1} eq "";

	} else {

		delete $racoon->{$k};
		delete $racoon->{$k+1} if $racoon->{$k+1}{1} eq "";
		delete $racoon->{$k+2} if $racoon->{$k+2}{1} eq ""; #- remove assoc } 

	}

}

#-------------------------------------------------------------------
#---------------------- configure ipsec_conf -----------------------
#-------------------------------------------------------------------

sub read_ipsec_conf {
	my ($ipsec_conf, $kernel_version) = @_;
	my %conf;
	my $nb = 0; #total number
	my $i = 0; #nb within a connexion
	my $in_a_conn = "n";
	my $line = "";
	my @line1;
	local $_;
	if ($kernel_version < 2.5) {
	#- kernel 2.4 part -------------------------------
		open(my $LIST, "< $ipsec_conf"); #or die "Can not open the $ipsec_conf file for reading";
		while (<$LIST>) {
        		chomp($_);
				$line = $_;
				$line =~ s/^\s+//;
				if (!$line) {
					$nb++;
					put_in_hash(\%conf, { $nb => $line });
					$in_a_conn = "n";
				} elsif ($line =~ /^#/) {
					if ($in_a_conn eq "y") {
						put_in_hash($conf{$nb} ||= {}, { $i => [$line] });
						$i++;
					} else {
						$nb++;
						put_in_hash(\%conf, { $nb => $line });
						$in_a_conn = "n";
					}
				} elsif ($line =~ /^conn|^config|^version/ && $in_a_conn eq "n") {
					@line1 = split /\s+/,$line;
					$i=1;
					$nb++;
					put_in_hash($conf{$nb} ||= {}, { $i => [$line1[0], $line1[1]] });
					$in_a_conn = "y" if $line !~ /^version/;
					$i++;
				} elsif ($line =~ /^conn|^config|^version/ && $in_a_conn eq "y") {
					@line1 = split /\s+/,$line;
					$i=1;
					$nb++;
					put_in_hash($conf{$nb} ||= {}, { $i => [$line1[0], $line1[1]] });
					$i++;
				} else {
					@line1 = split /=/,$line;
					put_in_hash($conf{$nb} ||= {}, { $i => [$line1[0], $line1[1]] });
					$i++;
				}
		}
	
	} else {
	#- kernel 2.6 part -------------------------------
		my @mylist;
		my $myline = "";
		open(my $LIST, "< $ipsec_conf"); #or die "Can not open the $ipsec_conf file for reading";
			while (<$LIST>) {
		        	chomp($_);
				$myline = $_;
				$myline =~ s/^\s+//;
				$myline =~ s/;$//;
				if ($myline =~ /^spdadd/) {
					@mylist = split /\s+/,$myline;
					$in_a_conn = "y";
					$nb++;
					next;
				} elsif ($in_a_conn eq "y") {
					@mylist = (@mylist, split '\s+|/',$myline);
					put_in_hash(\%conf, { $nb =>  {	command => $mylist[0],
									src_range => $mylist[1],
									dst_range => $mylist[2],
									upperspec => $mylist[3],
									flag => $mylist[4],
									direction => $mylist[5],
									ipsec => $mylist[6],
									protocol => $mylist[7],
									mode => $mylist[8],
									src_dest => $mylist[9],
									level => $mylist[10] } }); 
					$in_a_conn = "n";		
				} else {
					$nb++;
					put_in_hash(\%conf, { $nb => $myline });
				}
			}
	
		}

	\%conf;
}

sub write_ipsec_conf {
    my ($ipsec_conf, $ipsec, $kernel_version) = @_;
	if ($kernel_version < 2.5) {
	#- kernel 2.4 part -------------------------------
		open(my $ADD, "> $ipsec_conf") or die "Can not open the $ipsec_conf file for writing";
			foreach my $key1 (ikeys %$ipsec) {
				print $ADD "$ipsec->{$key1}\n" if ! $ipsec->{$key1}{1};
				foreach my $key2 (ikeys %{$ipsec->{$key1}}) {
					if ($ipsec->{$key1}{$key2}[0] =~ m/^#/) {
						print $ADD "\t$ipsec->{$key1}{$key2}[0]\n";
					} elsif ($ipsec->{$key1}{$key2}[0] =~ m/(^conn|^config|^version)/) {
						print $ADD "$ipsec->{$key1}{$key2}[0] $ipsec->{$key1}{$key2}[1]\n";
					} else {
						print $ADD "\t$ipsec->{$key1}{$key2}[0]=$ipsec->{$key1}{$key2}[1]\n" if $ipsec->{$key1}{$key2}[0] && $ipsec->{$key1}{$key2}[1];
					}
				}
			}
	} else {
	#- kernel 2.6 part -------------------------------
		my $display = "";
		foreach my $key1 (ikeys %$ipsec) {
			if (! $ipsec->{$key1}{command}) {
				$display .= "$ipsec->{$key1}\n";
			} else {
				$display .=	$ipsec->{$key1}{command} . " " .
						$ipsec->{$key1}{src_range} . " " .
						$ipsec->{$key1}{dst_range} . " " .
						$ipsec->{$key1}{upperspec} . " " .
						$ipsec->{$key1}{flag} . " " .
						$ipsec->{$key1}{direction} . " " .
						$ipsec->{$key1}{ipsec} . "\n\t" .
						$ipsec->{$key1}{protocol} . "/" .
						$ipsec->{$key1}{mode} . "/" .
						$ipsec->{$key1}{src_dest} . "/" .
						$ipsec->{$key1}{level} . ";\n";
			}
		}
		open(my $ADD, "> $ipsec_conf") or die "Can not open the $ipsec_conf file for writing";
			print $ADD $display;
		}
}

sub display_ipsec_conf {
	my ($ipsec, $kernel_version) = @_;
	my $display = "";

	if ($kernel_version < 2.5) {
	#- kernel 2.4 part -------------------------------
		foreach my $key1 (ikeys %$ipsec) {
			$display .= "$ipsec->{$key1}\n" if ! $ipsec->{$key1}{1};
			foreach my $key2 (ikeys %{$ipsec->{$key1}}) {
				if ($ipsec->{$key1}{$key2}[0] =~ m/^#/) {
					$display .= "\t$ipsec->{$key1}{$key2}[0]\n";
				} elsif ($ipsec->{$key1}{$key2}[0] =~ m/(^conn|^config|^version)/) {
					$display .= "$ipsec->{$key1}{$key2}[0] $ipsec->{$key1}{$key2}[1]\n";
				} else {
					$display .= "\t$ipsec->{$key1}{$key2}[0]=$ipsec->{$key1}{$key2}[1]\n";
				}
			}
		}

	} else {
	#- kernel 2.6 part -------------------------------
		foreach my $key1 (ikeys %$ipsec) {
			if (! $ipsec->{$key1}{command}) {
				$display .= "$ipsec->{$key1}\n";
			} else {
				$display .=	$ipsec->{$key1}{command} . " " .
						$ipsec->{$key1}{src_range} . " " .
						$ipsec->{$key1}{dst_range} . " " .
						$ipsec->{$key1}{upperspec} . " " .
						$ipsec->{$key1}{flag} . " " .
						$ipsec->{$key1}{direction} . " " .
						$ipsec->{$key1}{ipsec} . "\n\t" .
						$ipsec->{$key1}{protocol} . "/" .
						$ipsec->{$key1}{mode} . "/" .
						$ipsec->{$key1}{src_dest} . "/" .
						$ipsec->{$key1}{level} . ";\n";
			} 
		}

	}

	$display;

}

sub get_section_names_ipsec_conf {
	my ($ipsec, $kernel_version) = @_;
	my @section_names;

	if ($kernel_version < 2.5) {
	#- kernel 2.4 part -------------------------------
		foreach my $key1 (ikeys %$ipsec) {
			foreach my $key2 (ikeys %{$ipsec->{$key1}}) {
				if ($ipsec->{$key1}{$key2}[0] =~ m/(^conn|^config|^version)/) {
					push(@section_names, "$ipsec->{$key1}{$key2}[0] $ipsec->{$key1}{$key2}[1]");
				}
			}
		}

	} else {
	#- kernel 2.6 part -------------------------------
		foreach my $key1 (ikeys %$ipsec) {
				if ($ipsec->{$key1}{command} =~ m/(^spdadd)/) {
					push(@section_names, "$ipsec->{$key1}{src_range} $ipsec->{$key1}{dst_range}");
				}
		}
	}

	@section_names;

}

sub remove_section_ipsec_conf {
	my ($section_name, $ipsec, $kernel_version) = @_;
	if ($kernel_version < 2.5) {
	#- kernel 2.4 part -------------------------------
		foreach my $key1 (ikeys %$ipsec) {
			if (find {
				my $s = $ipsec->{$key1}{$_}[0];
				$s !~ /^#/ && $s =~ m/(^conn|^config|^version)/ &&
				$section_name eq "$s $ipsec->{$key1}{$_}[1]";	
			} ikeys %{$ipsec->{$key1}}) {
					delete $ipsec->{$key1};
			}
		}
	} else {
	#- kernel 2.6 part -------------------------------
		foreach my $key1 (ikeys %$ipsec) {
			if (find {
				my $s = "$ipsec->{$key1}{src_range} $ipsec->{$key1}{dst_range}";
				$s !~ /^#/ && $ipsec->{$key1}{src_range} && $section_name eq $s;
			} ikeys %{$ipsec->{$key1}}) {
				delete $ipsec->{$key1-1};
				delete $ipsec->{$key1};
			}
		}
	}
} 

sub add_section_ipsec_conf {
	my ($new_section, $ipsec) = @_;
	put_in_hash($ipsec, { max(keys %$ipsec) + 1 => '' });
	put_in_hash($ipsec, { max(keys %$ipsec) + 1 => $new_section });
}

sub already_existing_section_ipsec_conf {
	my ($section_name, $ipsec, $kernel_version) = @_;
	if ($kernel_version < 2.5) {
	#- kernel 2.4 part -------------------------------
		foreach my $key1 (ikeys %$ipsec) {
				if (find {
					my $s = $ipsec->{$key1}{$_}[0];
					$s !~ /^#/ && $s =~ m/(^conn|^config|^version)/ &&
					$section_name eq "$s $ipsec->{$key1}{$_}[1]";	
				} ikeys %{$ipsec->{$key1}}) {
					return "already existing";
				}
		}
	} else {
	#- kernel 2.6 part -------------------------------
		foreach my $key1 (ikeys %$ipsec) {
			if (find {
				my $s = "$ipsec->{$key1}{src_range} $ipsec->{$key1}{dst_range}";
				$s !~ /^#/ && $ipsec->{$key1}{src_range} &&
				$section_name eq $s;
			} ikeys %{$ipsec->{$key1}}) {
				return "already existing";
			}
		}
	}
	return "no";
}

#- returns the reference to the dynamical list for editing
sub dynamic_list {
	my ($number, $ipsec) = @_;
	my @list = 	map { { 	label   => $ipsec->{$number}{$_}[0] . "=",
					val     => \$ipsec->{$number}{$_}[1] } } ikeys %{$ipsec->{$number}};

	@list;
}

#- returns the hash key number of $section_name
sub matched_section_key_number_ipsec_conf {
	my ($section_name, $ipsec, $kernel_version) = @_;
	if ($kernel_version < 2.5) {
	#- kernel 2.4 part -------------------------------
		foreach my $key1 (ikeys %$ipsec) {
				if (find {
					my $s = $ipsec->{$key1}{$_}[0];
					$s !~ /^#/ && $s =~ m/(^conn|^config|^version)/ &&
					$section_name eq "$s $ipsec->{$key1}{$_}[1]";	
				} ikeys %{$ipsec->{$key1}}) {
					return $key1;
				}
		}
	} else {
	#- kernel 2.6 part -------------------------------
		foreach my $key1 (ikeys %$ipsec) {
			if (find {
				my $s = "$ipsec->{$key1}{src_range} $ipsec->{$key1}{dst_range}";
				$s !~ /^#/ && $ipsec->{$key1}{src_range} &&
				$section_name eq $s;
			} ikeys %{$ipsec->{$key1}}) {
				return $key1;
			}
		}
	}
}
1
