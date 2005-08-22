use MDK::Common;

BEGIN {
    @ARGV or warn(<<EOF), exit 1;
usage: $0 -pi <file.pm>

- an emacs is launched with a script fixing the closing "children => [ ...",
  simply save the file and exit this emacs
- you can replace -pi with -n to see the diff of changes without modifying the file
EOF
    @args = @ARGV;
    $re = qr/(?:[^()\[\]]*(?:\([^()]*\))?(?:\[[^\[\]]*\])?)*/;
    $assign = qr/(?:(?:my\s+)?\$\w+\s*=\s*)/;

    %pack = (gtkadd => 'children_loose', gtkpack_ => 'children', gtkpack => 'children_loose', gtkpack__ => 'children_tight');
}

$z = $_;

$once = 0;
$b = 1;

while ($b) {
    $b = 0;

    if (my ($before, $class, undef, $new, $arg, $after, $after2) = /(.*?)Gtk2::(\w+(::\w+)*)->(new\w*)(?:\(($re)\)(.*)|([^(].*))/s) {
	$after ||= $after2;
	my $s;

	my $class_ = $class eq 'WrappedLabel' ? 'Label' : $class;
	
	if ($class_ eq 'Window') {
	    if ($new eq 'new') {
		$s = $arg && $arg !~ /^['"]toplevel['"]$/ ?
		  "gtknew('$class', type => $arg)" :
		    "gtknew('$class')";
	    }
	} elsif ($class_ eq 'Dialog') {
	    if ($new eq 'new' && !$arg) {
		$s = "gtknew('$class')";
	    }
	} elsif ($class_ eq 'Image') {
	    if ($new eq 'new_from_file' && $arg) {
		$s = "gtknew('$class', file => $arg)";
	    }
	} elsif ($class_ eq 'Gdk::Pixbuf') {
	    if ($new eq 'new_from_file' && $arg) {
		$s = "gtknew('Pixbuf', file => $arg)";
	    }
	} elsif ($class_ eq 'Frame' || $class_ eq 'Label') {
	    if ($new eq 'new') {
		$s = $arg ? "gtknew('$class', text => $arg)" : "gtknew('$class')";
	    }
	} elsif ($class_ eq 'WrappedLabel') {
	    if ($new eq 'new') {
		if ($arg =~ /($re),\s*($re)/) {
		    $s = "gtknew('$class', alignment => [ $2, 0.5 ], text => $1)";
		} elsif ($arg) {
		    $s = "gtknew('$class', text => $arg)";
		} else {
		    $s = "gtknew('$class')";
		}
	    }
	} elsif ($class_ eq 'HBox' || $class_ eq 'VBox') {
	    if ($new eq 'new') {
		if ($arg =~ /($re),\s*($re)/) {
		    $s = "gtknew('$class'" . ($1 ? ", homogenous => $1" : '') . ($2 ? ", spacing => $2" : '') . ')';
		} else {
		    $s = "gtknew('$class')";
		}
		
	    }
	} elsif ($class_ eq 'ComboBox') {
	    if ($new eq 'new_text') {
		$s = "gtknew('$class')";
	    } elsif ($new eq 'new_with_strings' && $arg) {
		if (my ($l, $t) = $arg =~ /($re),\s*($re)/) {
		    if ($t !~ /\]/) {
			$s = "gtknew('$class', text => $t, list => $l)";
		    }
		} else {
		    $s = "gtknew('$class', list => $arg)";
		}
	    }
	} elsif ($class_ eq 'Button' || $class_ eq 'ToggleButton' || $class_ eq 'CheckButton') {
	    if ($new eq 'new') {
		$s = $arg ? "gtknew('$class', text => $arg)" : "gtknew('$class')";
	    } elsif ($new eq 'new_with_mnemonic' && $arg) {
		$s = "gtknew('$class', text => $arg)";
	    } elsif ($new eq 'new_with_label' && $arg) {
		$s = "gtknew('$class', mnemonic => 0, text => $arg)";
	    }
	} elsif ($class =~ /^(HSeparator|VSeparator|Notebook|HButtonBox|VButtonBox|TextView|Entry|Calendar)$/) {
	    if ($new eq 'new') {
		$s = "gtknew('$class')";
	    }
	}

	if ($s) {
	    $_ = "$before$s$after";
	    $b = 1;
	}
    }

    $b = 1 if s/create_hbox\((['"].*?['"])\)/gtknew('HButtonBox', layout => $1)/ ||
              s/create_hbox\(\)/gtknew('HButtonBox')/;

    if (my ($arg) = /create_scrolled_window\(($re)\)/) {
	my $val;
	if (my ($child, $policy) = $arg =~ /^($re)\s*,\s*($re)$/) {
	    if (my ($h, $v) = $policy =~ /^\[\s*($re)\s*,\s*($re)\s*\]$/) {
		foreach ($h, $v) {
		    $_ = /never/i ? 'never' : /always/ ? 'always' : '';
		}
		$val = join(', ', if_($h, "h_policy => '$h'"), if_($v, "v_policy => '$v'"), "child => $child");
	    } else {
		#- ???
	    }
	} else {
	    $val = "child => $arg";
	}
	$b = 1 if $val && s/create_scrolled_window\($re\)/gtknew('ScrolledWindow', $val)/;
    }

    $b = 1 if s/create_packtable\(\{($re)\},/my $s = prepost_chomp($1); "gtknew('Table', " . ($s ? "$s, " : '') . "children => ["/e;

    $b = 1 if s/gtkcreate_img\(($re)\)/gtknew('Image', file => $1)/;
    $b = 1 if s/gtkcreate_pixbuf\(($re)\)/gtknew('Pixbuf', file => $1)/;

    $b = 1 if s/(gtkadd|gtkpack_{0,2})\(($assign?gtknew\('[HV](?:Button)?Box'$re)\),/"$2, " . $pack{$1} . " => ["/e;

    $b = 1 if s/(\$\w+)->set_label\(($re)\)/gtkset($1, text => $2)/;

    while (dorepl_new()) {
	$b = 1;
    }
    while (dorepl()) {
	$b = 1;
    }
    $once ||= $b;
}

sub dorepl_new {
    if (my ($before, $f, $gtk, $arg, $after) = /(.*?)(gtk\w+)\(($assign?gtk(?:new|set))\(($re)\)\s*,[ \t]*(.*)/s) {
	my $s;
	my $class;
	if ($gtk =~ /gtknew$/) {
	    ($class) = $arg =~ /^'(.*?)'/ or return;
	}
	my $class_ = $class eq 'WrappedLabel' ? 'Label' : $class;
	my $pre = "$gtk($arg";

	if ($f eq 'gtksignal_connect') {
	    if ($class_ eq 'Button' || !$class) {
		$s = "$pre, ";
	    }
	} elsif ($f eq 'gtkadd') {
	    if ($class_ eq 'Frame' || !$class) {
		$s = "$pre, child => ";
	    }
	} elsif ($f eq 'gtkset_justify') {
	    if ($class_ eq 'Label' || !$class) {
		$s = "$pre, justify => ";
	    }
	} elsif ($f eq 'gtkset_markup') {
	    if ($class_ eq 'Label' || !$class) {
		$s = "$pre, text_markup => ";
	    }
	} elsif ($f eq 'gtkmodify_font') {
	    if ($class_ eq 'Label' || !$class) {
		$s = "$pre, font => ";
	    }
	} elsif ($f eq 'gtktext_insert') {
	    if ($class_ eq 'TextView' || !$class) {
		$s = "$pre, text => ";
	    }
	} elsif ($f eq 'gtkset_text') {
	    if ($class_ eq 'Entry' || !$class) {
		$s = "$pre, text => ";
	    }
	}

	if (!$s) {
	    if ($f =~ /^gtkset_(relief|sensitive|shadow_type|modal|border_width|layout|editable)$/) {
		$s = "$pre, $1 => ";
	    } elsif ($f eq 'gtkset_name') {
		$s = "$pre, widget_name => ";
	    } elsif ($f eq 'gtkset_size_request') {
		if ($after =~ /($re)\s*,\s*($re)\)(.*)/s) {
		    $s = $pre . ($1 && $1 ne '-1' ? ", width => $1" : '') . ($2 && $2 ne '-1' ? ", height => $2" : '') . ')';
		    $after = $3;
		}
	    }
	}
	if ($s) {
	    $_ = "$before$s$after";
	}
	$s;
    }
}

sub dorepl {
    s/gtkdestroy\(/mygtk2::may_destroy(/ ||
    s/gtkset_background\(/mygtk2::set_root_window_background(/ ||
    s/gtkset_tip\($re,\s*($re),\s*($re)\)/gtkset($1, tip => $2)/ ||
    s/gtkset_size_request\(($re),\s*($re), ($re)\)/"gtkset($1" . ($2 && $2 ne '-1' ? ", width => $2" : '') . ($3 && $3 ne '-1'  ? ", height => $3" : '') . ')'/e ||
    s/gtkset_(modal)\(($re),\s*($re)\)/gtkset($2, $1 => $3)/ ||
      0;
}

sub prepost_chomp {
    my ($s) = @_;
    $s =~ s/^\s*//;
    $s =~ s/\s*$//;
    $s;
}

print STDERR "-$z+$_" if $once;

END {
    if (defined $^I) {
	foreach (@args) {
	    warn "$_: closing children using emacs\n";
	    (my $el = $0) =~ s/\.pl$/.el/ or die ".el missing";
	    system('emacs', '-q', '-l', $el, $_, '-f', 'my-close-children') 
	}
    }
}
