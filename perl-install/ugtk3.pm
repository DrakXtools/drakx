package ugtk3;

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK @icon_paths $wm_icon $grab $border); #- leave it on one line, for automatic removal of the line at package creation
use locale;

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    wrappers => [ qw(gtkadd gtkadd_widget gtkappend gtkappend_page gtkappenditems gtkcombo_setpopdown_strings gtkdestroy
                     gtkentry gtkflush gtkhide gtkoverride_font gtkmove gtkpack gtkpack2 gtkpack2_
                     gtkpack2__ gtkpack_ gtkpack__ gtkpowerpack gtkput gtkradio gtkresize gtkroot
                     gtkset_active gtkset_border_width gtkset_editable gtkset_justify gtkset_alignment gtkset_layout gtkset_line_wrap
                     gtkset_markup gtkset_modal gtkset_mousecursor gtkset_mousecursor_normal gtkset_mousecursor_wait gtkset_name
                     gtkset_property gtkset_relief gtkset_selectable gtkset_sensitive gtkset_shadow_type gtkset_size_request
                     gtkset_text gtkset_tip gtkset_visibility gtksetstyle gtkshow gtksignal_connect gtksize gtktext_append
                     gtktext_insert ) ],

    helpers => [ qw(add2notebook add_icon_path escape_text_for_TextView_markup_format gtkcolor gtkcreate_img
                    gtkcreate_pixbuf gtkfontinfo gtkset_background gtktreeview_children set_back_pixmap
                    get_default_step_items set_default_step_items
                    string_size string_width) ],

    create => [ qw(create_adjustment create_box_with_title create_dialog 
                   create_hbox create_hpaned create_menu create_notebook create_okcancel create_packtable
                   create_scrolled_window create_vbox create_vpaned _create_dialog gtkcreate_frame) ],

    ask => [ qw(ask_browse_tree_info ask_browse_tree_info_given_widgets ask_dir ask_from_entry ask_okcancel ask_warn
                ask_yesorno) ],
    dialogs => [ qw(err_dialog info_dialog warn_dialog) ],

);
$EXPORT_TAGS{all} = [ map { @$_ } values %EXPORT_TAGS ];
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

use c;
use log;
use common;
use mygtk3 qw(gtknew); #- do not import gtkadd which conflicts with ugtk3 version

use Gtk3;


$border = 5;

sub wm_icon() { $wm_icon || $::Wizard_pix_up || "wiz_default_up.png" }

# -=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---
#                 wrappers
#
# Functional-style wrappers to existing Gtk functions; allows to program in
# a more functional way, and especially, first, to avoid using temp
# variables, and second, to "see" directly in the code the user interface
# you're building.

sub gtkdestroy                { mygtk3::may_destroy($_[0]) }
sub gtkflush()                { mygtk3::flush() }
sub gtkhide                   { $_[0]->hide; $_[0] }
sub gtkmove                   { $_[0]->get_window->move($_[1], $_[2]); $_[0] }
sub gtkpack                   { gtkpowerpack(1, 1, @_) }
sub gtkpack_                  { gtkpowerpack('arg', 1, @_) }
sub gtkpack__                 { gtkpowerpack(0, 1, @_) }
sub gtkpack2                  { gtkpowerpack(1, 0, @_) }
sub gtkpack2_                 { gtkpowerpack('arg', 0, @_) }
sub gtkpack2__                { gtkpowerpack(0, 0, @_) }
sub gtkput                    { $_[0]->put(gtkshow($_[1]), $_[2], $_[3]); $_[0] }
sub gtkresize                 { $_[0]->get_window->resize($_[1], $_[2]); $_[0] }
sub gtkset_active             { $_[0]->set_active($_[1]); $_[0] }
sub gtkset_border_width       { $_[0]->set_border_width($_[1]); $_[0] }
sub gtkset_editable           { $_[0]->set_editable($_[1]); $_[0] }
sub gtkset_selectable         { $_[0]->set_selectable($_[1]); $_[0] }
sub gtkset_justify            { $_[0]->set_justify($_[1]); $_[0] }
sub gtkset_alignment          { $_[0]->set_alignment($_[1], $_[2]); $_[0] }
sub gtkset_layout             { $_[0]->set_layout($_[1]); $_[0] }
sub gtkset_modal              { $_[0]->set_modal($_[1]); $_[0] }
sub gtkset_mousecursor_normal { gtkset_mousecursor('left-ptr', @_) }
sub gtkset_mousecursor_wait   { gtkset_mousecursor('watch', @_) }
sub gtkset_relief             { $_[0]->set_relief($_[1]); $_[0] }
sub gtkset_sensitive          { $_[0]->set_sensitive($_[1]); $_[0] }
sub gtkset_visibility         { $_[0]->set_visibility($_[1]); $_[0] }
sub gtkset_tip                { $_[0]->set_tooltip_text($_[1]) if $_[1]; $_[0] }
sub gtkset_shadow_type        { $_[0]->set_shadow_type($_[1]); $_[0] }
sub gtkset_style              { $_[0]->set_style($_[1]); $_[0] }
sub gtkset_size_request       { $_[0]->set_size_request($_[1], $_[2]); $_[0] }
sub gtkshow                   { $_[0]->show; $_[0] }
sub gtksize                   { $_[0]->size($_[1], $_[2]); $_[0] }
sub gtkset_markup             { $_[0]->set_markup($_[1]); $_[0] }
sub gtkset_line_wrap          { $_[0]->set_line_wrap($_[1]); $_[0] }

sub gtkadd {
    my $w = shift;
    foreach my $l (@_) {
	ref $l or $l = gtknew('WrappedLabel', text => $l);
	$w->add(gtkshow($l));
    }
    $w;
}

sub gtkadd_widget {
    my $sg = shift;
    map {
        my $l = $_;
        ref $l or $l = gtknew('WrappedLabel', text => $l);
        $sg->add_widget($l);
        $l;
    } @_;
}

sub gtkappend {
    my $w = shift;
    foreach my $l (@_) {
	ref $l or $l = gtknew('WrappedLabel', text => $l);
	$w->append(gtkshow($l));
    }
    $w;
}

sub gtkappenditems {
    my $w = shift;
    $_->show foreach @_;
    $w->append_items(@_);
    $w;
}

# append page to a notebook
sub gtkappend_page {
    my ($notebook, $page, $o_title) = @_;
    $notebook->append_page($page, $o_title);
    $notebook;
}

sub gtkentry {
    my ($o_text) = @_;
    my $e = gtknew('Entry');
    $o_text and $e->set_text($o_text);
    $e;
}

sub gtksetstyle { 
    my ($w, $s) = @_;
    $w->set_style($s);
    $w;
}

sub gtkradio {
    my $def = shift;
    my $radio;
    map {
        my $w = gtkset_active($radio = Gtk3::RadioButton->new_with_label_from_widget($radio, $_), $_ eq $def);
        $w->get_child->set_line_wrap(1);
        $w;
      } @_;
}

sub gtkroot() { mygtk3::root_window() }
sub gtkcolor { &mygtk3::rgb2color }
sub gtkset_background { &mygtk3::set_root_window_background }

sub gtkset_text {
    my ($w, $s) = @_;
    $w->set_text($s);
    $w;
}

sub gtkcombo_setpopdown_strings {
    my $w = shift;
    $w->set_popdown_strings(@_);
    $w;
}

sub gtkset_mousecursor {
    my ($type, $w) = @_;
    ($w || gtkroot())->set_cursor(Gtk3::Gdk::Cursor->new($type));
    $w;
}

sub gtksignal_connect {
    my $w = shift;
    $w->signal_connect(@_);
    $w;
}

sub gtkset_name {
    my ($widget, $name) = @_;
    $widget->set_name($name);
    $widget;
}


sub gtkpowerpack {
    #- Get Default Attributes (if any). 2 syntaxes allowed :
    #- gtkpowerpack( {expand => 1, fill => 0}, $box...) : the attributes are picked from a specified hash ref
    #- gtkpowerpack(1, 0, 1, $box, ...) : the attributes are picked from the non-ref list, in the order (expand, fill, padding, pack_end).
    my @attributes_list = qw(expand fill padding pack_end);
    my $default_attrs = {};
    if (ref($_[0]) eq 'HASH') {
	$default_attrs = shift;
    } elsif (!ref($_[0])) {
	foreach (@attributes_list) {
	    ref($_[0]) and last;
	    $default_attrs->{$_} = shift;
	}
    }
    my $box = shift;

    while (@_) {
	#- Get attributes (if specified). 4 syntaxes allowed (default values are undef ie. false...) :
	#- gtkpowerpack({defaultattrs}, $box, $widget1, $widget2, ...) : the attrs are picked from the default ones (if they exist)
	#- gtkpowerpack($box, {fill=>1, expand=>0, ...}, $widget1, ...) : the attributes are picked from a specified hash ref
	#- gtkpowerpack($box, [1,0,1], $widget1, ...) : the attributes are picked from the array ref : (expand, fill, padding, pack_end).
	#- gtkpowerpack({attr=>'arg'}, $box, 1, $widget1, 0, $widget2, etc...) : the 'arg' value will tell gtkpowerpack to always read the 
	#- attr value directly in the arg list (avoiding confusion between value 0 and Gtk::Label("0"). That can simplify some writings but
	#- this arg(s) MUST then be present...
	my (%attr, $attrs);
	ref($_[0]) eq 'HASH' || ref($_[0]) eq 'ARRAY' and $attrs = shift;
	foreach (@attributes_list) {
	    if (($default_attrs->{$_} || '') eq 'arg') {
		ref($_[0]) and internal_error "error in packing definition\n";
		$attr{$_} = shift;
		ref($attrs) eq 'ARRAY' and shift @$attrs;
	    } elsif (ref($attrs) eq 'HASH' && defined($attrs->{$_})) {
		$attr{$_} = $attrs->{$_};
	    } elsif (ref($attrs) eq 'ARRAY') {
		$attr{$_} = shift @$attrs;
	    } elsif (defined($default_attrs->{$_})) {
		$attr{$_} = int $default_attrs->{$_};
	    } else {
		$attr{$_} = 0;
	    }
	}
	#- Get and pack the widget (create it if necessary to  a label...)
	my $widget = ref($_[0]) ? shift : gtknew('WrappedLabel', text => shift);
	my $pack_call = 'pack_' . ($attr{pack_end} ? 'end' : 'start');
	$box->$pack_call($widget, $attr{expand}, $attr{fill}, $attr{padding});
	$widget->show;
    }
    return $box;
}

sub gtktreeview_children {
    my ($model, $iter) = @_;
    my @l;
    $model or return;
    my $p = $model->iter_children($iter);
    $p or return;
    while ($model->iter_next($p)) {
	push @l, $p->copy;
    }
    @l;
}



# -=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---
#                 create
#
# Helpers that allow omitting common operations on common widgets
# (e.g. create widgets with good default properties)

sub create_pixbutton {
    my ($label, $pix, $reverse_order) = @_;
    my @label_and_pix = (0, $label, if_($pix, 0, $pix));
    gtkadd(gtknew('Button'),
	   gtknew('HBox', spacing => 3, children => [
		    1, "",
		    $reverse_order ? reverse(@label_and_pix) : @label_and_pix,
		    1, "",
		]));
}

sub create_adjustment {
    my ($val, $min, $max) = @_;
    Gtk3::Adjustment->new($val, $min, $max + 1, 1, ($max - $min + 1) / 10, 1);
}

sub create_scrolled_window {
    my ($W, $o_policy, $o_viewport_shadow) = @_;
    gtknew('ScrolledWindow', ($o_policy ? (h_policy => $o_policy->[0], v_policy => $o_policy->[1]) : ()),
               child => $W, if_($o_viewport_shadow, shadow_type => $o_viewport_shadow));
}

sub n_line_size {
    my ($nbline, $type, $widget) = @_;
    my $spacing = ${{ text => 3, various => 17 }}{$type};
    my %fontinfo = gtkfontinfo($widget);
    round($nbline * ($fontinfo{ascent} + $fontinfo{descent} + $spacing) + 8);
}

# Glib::Markup::escape_text() if no use for us because it'll do extra
# s/X/&foobar;/ (such as s/'/&apos;/) that are suitable for
# Gtk3::Labels but are not for Gtk3::TextViews, resulting in
# displaying the raw enriched text instead...
#
sub escape_text_for_TextView_markup_format {
    my ($str) = @_;
    my %rules = ('&' => '&amp;',
               '<' => '&lt;',
               '>' => '&gt;',
           );
    eval { $str =~ s!([&<>])!$rules{$1}!g }; #^(&(amp|lt|gt);)!!) {
    if (my $err = $@) {
           internal_error("$err\n$str");
    }
    $str;
}

sub markup_to_TextView_format {
    my ($s, $o_default_attrs) = @_;
    require interactive;
    my $l = interactive::markup_parse($s) or return $s;
    
    foreach (@$l) {
	my ($_txt, $attrs) = @$_;
	if ($attrs) {
         $attrs->{weight} eq 'bold' and $attrs->{weight} = 'bold';
         $attrs->{size} eq 'larger' and do {
             $attrs->{scale} = 1.4399999999999; # PANGO_SCALE_X_LARGE: equivalent to Label's size => 'larger'
             delete $attrs->{size};
         };
     }
	#- nb: $attrs may be empty, need special handling if $o_default_attrs is used
	add2hash_($_->[1] ||= {}, $o_default_attrs) if $o_default_attrs;
    }
    $l;
}

sub create_box_with_title {
    my ($o, @l) = @_;

    my $nbline = sum(map { round(length($_) / 60 + 1/2) } map { split "\n" } @l);
    my $box = gtknew('VBox');
    if ($nbline == 0) {
	$o->{box_size} = 0;
	return $box;
    }
    $o->{box_size} = n_line_size($nbline, 'text', $box);
    if (@l <= 2 && $nbline > 4) {
	$o->{icon} && !$::isWizard and 
	  eval { gtkpack__($box, gtknew('HBox', border_width => 5, children_loose => [ gtkcreate_img($o->{icon}) ])) };
	my $wanted = $o->{box_size};
	$o->{box_size} = min(200, $o->{box_size});
	my $has_scroll = $o->{box_size} < $wanted;

	chomp(my $text = join("\n", @l));
	my $wtext = gtknew('TextView', text => markup_to_TextView_format($text));
	$wtext->set_justification('fill');
	$wtext->set_left_margin(12);
	$wtext->set_right_margin(12);
	$wtext->set_can_focus($has_scroll);
	my $width = 400;
	my $scroll = gtknew('ScrolledWindow', child => $wtext, width => $width, height => 200);
	$scroll->signal_connect(realize => sub {
                                my $layout = $wtext->create_pango_layout($text);
                                $layout->set_width(Pango::units_from_double($width - 10));
                                $wtext->set_size_request($width,  min(200, second($layout->get_pixel_size) + 10));
                                $scroll->set_size_request($width, min(200, second($layout->get_pixel_size) + 10));
                                $o->{rwindow}->queue_resize;
                            });
	gtkpack_($box, $o->{box_allow_grow} || 0, $scroll);
    } else {
     my $new_label = sub {
         my ($txt) = @_;
         ref($txt) ? $txt : gtknew('WrappedLabel', text_markup => $txt,
                                   # workaround infamous 6 years old gnome bug #101968:
                                   width => mygtk3::get_label_width());
     };
	    gtkpack__($box,
		      if_($::isWizard, gtknew('Label', height => 10)),
		      (map {
			  my $w = $new_label->($_);
			  $::isWizard ? gtknew('HBox', children_tight => [ gtknew('Label', width => 20), $w ])
			              : $w;
		      } @l),
		      if_($::isWizard, gtknew('Label', height => 15)),
		     );
    }
}

sub _create_dialog {
    my ($title, $o_options) = @_;
    my $options = $o_options || {};

    #- keep compatibility with "transient" now called "transient_for"
    $options->{transient_for} = delete $options->{transient} if $options->{transient};

    gtknew('Dialog', title => $title, 
	   position_policy => 'center-on-parent', # center-on-parent does not work
	   modal => 1,
	   if_(!$::isInstall, icon_no_error => wm_icon()),
	   %$options, allow_unknown_options => 1,
       );
}


# drakfloppy / drakfont / harddrake2 / mcc
sub create_dialog {
    my ($title, $label, $o_options) = @_;
    my $ret = 0;
    $o_options ||= {};
    $o_options->{transient_for} = $::main_window if !$o_options->{transient_for} && $::main_window;

    my $dialog =  gtkset_border_width(_create_dialog($title, $o_options), 10);
    $dialog->set_border_width(10);
    my $text = ref($label) ? $label : $o_options->{use_markup} ? gtknew('WrappedLabel', text_markup => $label) : gtknew('WrappedLabel', text => $label);
    gtkpack($dialog->get_child,
            gtknew('HBox', children => [
                     if_($o_options->{stock},
                         0, Gtk3::Image->new_from_stock($o_options->{stock} || '', 'dialog'),
                         0, gtknew('Label', text => "   "),
                        ),
                     1, $o_options->{scroll} ? create_scrolled_window($text, [ 'never', 'automatic' ]) : $text,
                    ]),
           );

    if ($o_options->{cancel}) {
	$dialog->get_action_area->pack_start(
	    gtknew('Button', text => N("Cancel"),
		   clicked => sub { $ret = 0; $dialog->destroy; Gtk3->main_quit },
		   can_default => 1), 
	    1, 1, 0);
    }

    my $button = gtknew('Button', text => N("Ok"), can_default => 1,
			clicked => sub { $ret = 1; $dialog->destroy; Gtk3->main_quit });
    $dialog->get_action_area->pack_start($button, 1, 1, 0);
    $button->grab_default;

    $dialog->show_all;
    Gtk3->main;
    $ret;
}

sub info_dialog {
    my ($title, $label, $o_options) = @_;
    $o_options ||= { };
    add2hash_($o_options, { stock => 'gtk-dialog-info' });
    create_dialog($title, $label, $o_options);
}

sub warn_dialog {
    my ($title, $label, $o_options) = @_;
    $o_options ||= { };
    add2hash_($o_options, { stock => 'gtk-dialog-warning', cancel => 1 });
    create_dialog($title, $label, $o_options);
}

sub err_dialog {
    my ($title, $label, $o_options) = @_;
    $o_options ||= { };
    add2hash_($o_options, { stock => 'gtk-dialog-error' });
    create_dialog($title, $label, $o_options);
}

sub create_hbox { gtknew('HButtonBox', layout => $_[0]) }
sub create_vbox { gtknew('VButtonBox', layout => $_[0]) }

sub create_menu {
    my $title = shift;
    my $w = Gtk3::MenuItem->new($title);
    $w->set_submenu(gtkshow(gtkappend(Gtk3::Menu->new, @_)));
    $w;
}

sub create_notebook {
    my $book = gtknew('Notebook');
    while (@_) {
	my ($page, $title) = splice(@_, 0, 2);
	gtkappend_page($book, $page, $title);
    }
    $book;
}

sub create_packtable {
    my ($options, @l) = @_;
    my $w = Gtk3::Table->new(0, 0, $options->{homogeneous} || 0);
    add2hash_($options, { xpadding => 5, ypadding => 0 });
    each_index {
	my ($i, $l) = ($::i, $_);
	each_index {
	    my $j = $::i;
	    if ($_) {
		ref $_ or $_ = gtknew('WrappedLabel', text => $_);
		$j != $#$l && !$options->{mcc} ?
		  $w->attach($_, $j, $j + 1, $i, $i + 1,
			     'fill', 'fill', $options->{xpadding}, $options->{ypadding}) :
		  $w->attach($_, $j, $j + 1, $i, $i + 1,
			     ['expand', 'fill'], ref($_) eq 'Gtk3::ScrolledWindow' || $_->get_data('must_grow') ? ['expand', 'fill'] : [], 0, 0);
		$_->show;
	    }
	} @$l;
    } @l;
    $w->set_col_spacings($options->{col_spacings} || 0);
    $w->set_row_spacings($options->{row_spacings} || 0);
    gtkset_border_width($w, $::isInstall ? 3 : 10);
}

my $wm_is_kde;
sub create_okcancel {
    my ($w, $o_ok, $o_cancel, $_o_spread, @other) = @_;
    # @other is a list of extra buttons (usually help (eg: XFdrake/drakx caller) or advanced (eg: interactive caller) button)
    # extra buttons have the following structure [ label, handler, is_first, pack_right ]
    local $::isWizard = $::isWizard && !$w->{pop_it};
    my $cancel;
    if (defined $o_cancel || defined $o_ok) {
        $cancel = $o_cancel;
    } elsif (!$::Wizard_no_previous) {
        $cancel = $::isWizard ? N("Previous") : N("Cancel");
    }
    my $ok = defined $o_ok ? $o_ok : $::isWizard ? ($::Wizard_finished ? N("Finish") : N("Next")) : N("Ok");
    my $bok = $ok && ($w->{ok} = gtknew('Button', text => $ok, clicked => $w->{ok_clicked} || sub { $w->{retval} = 1; Gtk3->main_quit }));
    my $bprev;
    if ($cancel) {
        $bprev = $w->{cancel} = gtknew('Button', text => $cancel, clicked => $w->{cancel_clicked} || 
                                   sub { log::l("default cancel_clicked"); undef $w->{retval}; Gtk3->main_quit });
    }
    $w->{wizcancel} = gtknew('Button', text =>  ($::Wizard_skip ? N("Skip") : N("Cancel")), clicked => sub { die 'wizcancel' }) if $::isWizard && !$::isInstall && !$::Wizard_no_cancel;
    if (!defined $wm_is_kde) {
        require any;
        my $wm = any::running_window_manager();
        $wm_is_kde = !$::isInstall && ($wm eq "kwin" || $wm eq "compiz" && fuzzy_pidofs(qr/\bkde-window-decorator\b/)) || 0;
    }
    my $f = sub { $w->{buttons}{$_[0][0]} = ref($_[0][0]) =~ /Gtk3::Button/ ?
                    $_[0][0] :
                    gtknew('Button', text => $_[0][0], clicked => $_[0][1]) };
    my @left  = ((map { $f->($_) } grep {  $_->[2] && !$_->[3] } @other),
                  map { $f->($_) } grep { !$_->[2] && !$_->[3] } @other);
    my @right = ((map { $f->($_) } grep {  $_->[2] &&  $_->[3] } @other),
                  map { $f->($_) } grep { !$_->[2] &&  $_->[3] } @other);
    # we put space to group buttons in two packs (but if there's only one when not in wizard mode)
    # but in the installer where all windows run in wizard mode because of design even when not in a wizard step
    $bprev = gtknew('Label') if !$cancel && $::Wizard_no_previous && !@left && !@right;
    if ($::isWizard || $w->{pop_it}) {
        # wizard mode: order is cancel/left_extras/white/right_extras/prev/next
        unshift @left, $w->{wizcancel} if $w->{wizcancel};
        push @right, $bprev, $bok;
    } else { 
        # normal mode: cancel/ok button follow GNOME's HIG
        unshift @left, ($wm_is_kde ? $bok : $bprev);
        push @left, gtknew('Label') if $ok && $cancel; # space buttons but if there's only one button
        push @right, ($wm_is_kde ? $bprev : $bok);
    }

    gtknew('VBox', spacing => 5, children_loose => [
	    gtknew('HBox', height => 5),
            gtknew('HSeparator'),
            gtknew('HBox', children_loose => [
                   map {
		       gtknew('HButtonBox', spacing => 5, layout => $_->[1],
			      children_loose => [
				  map {
				      $_->set_can_default(to_bool($::isWizard));
				      $_;
				  } grep { $_ } @{$_->[0]} 
			      ]);
                    } ([ \@left, 'start' ],
                       [ \@right,  'end' ],
                      )
                    ]),
           ]);
}

sub _setup_paned {
    my ($paned, $child1, $child2, %options) = @_;
    foreach ([ 'resize1', 0 ], [ 'shrink1', 1 ], [ 'resize2', 1 ], [ 'shrink2', 1 ]) {
        $options{$_->[0]} = $_->[1] unless defined($options{$_->[0]});
    }
    $paned->pack1(gtkshow($child1), $options{resize1}, $options{shrink1});
    $paned->pack2(gtkshow($child2), $options{resize2}, $options{shrink2});
    gtkshow($paned);
}

sub create_vpaned {
    _setup_paned(Gtk3::VPaned->new, @_);
}

sub create_hpaned {
    _setup_paned(Gtk3::HPaned->new, @_);
}

sub gtkcreate_frame {
    my ($label) = @_;
    gtknew('Frame', text => $label, border_width => 5);
}


# -=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---
#                 helpers
#
# Functions that do typical operations on widgets, that you may need in
# several places of your programs.

sub _find_imgfile {
    my ($name) = @_;

    if ($name =~ m|/| && -f $name) {
	$name;
    } else {
	foreach my $path (icon_paths()) {
	    foreach ('', '.png', '.xpm') {
		my $file = "$path/$name$_";
		-f $file and return $file;
	    }
	}
    }
}

# use it if you want to display an icon/image in your app
sub gtkcreate_img {
    my ($file, $o_size) = @_;
    gtknew('Image', file => $file, if_($o_size, size => $o_size));
}

# use it if you want to draw an image onto a drawingarea
sub gtkcreate_pixbuf {
    my ($file, $o_size) = @_;
    gtknew('Pixbuf', file => $file, if_($o_size, size => $o_size));
}

sub gtktext_append { gtktext_insert(@_, append => 1) }

sub may_set_icon {
    my ($w, $name) = @_;
    if (my $f = $name && _find_imgfile($name)) {
	$w->set_icon(gtkcreate_pixbuf($f));
    }
}

sub gtktext_insert { &mygtk3::_text_insert }
sub icon_paths { &mygtk3::_icon_paths }
sub add_icon_path { &mygtk3::add_icon_path }

sub set_main_window_size { 
    my ($o) = @_;
    mygtk3::set_main_window_size($o->{rwindow});
}

# extracts interesting font metrics for a given widget
sub gtkfontinfo {
    my ($widget) = @_;
    my $context = $widget->get_pango_context;
    my $metrics = $context->get_metrics($context->get_font_description, $context->get_language);
    my %fontinfo;
    foreach (qw(ascent descent approximate_char_width approximate_digit_width)) {
	no strict;
	my $func = "get_$_";
	$fontinfo{$_} = Pango::units_to_double($metrics->$func);
    }
    %fontinfo;
}

sub gtkoverride_font {
    my ($w, $arg) = @_;
    $w->override_font(ref($arg) ? $arg : Pango::FontDescription->from_string($arg));
    $w;
}

sub gtkset_property {
    my ($w, $property, $value) = @_;
    $w->set_property($property, $value);
    $w;
}

sub set_back_pixmap {
    my ($w) = @_;
    return if !$w->get_realized;
    my $window = $w->get_window;
    my $pixmap = $w->{back_pixmap} ||= Gtk3::Gdk::Pixmap->new($window, 1, 2, $window->get_depth);

    my $style = $w->get_style;
    $pixmap->draw_points($style->bg_gc('normal'), 0, 0);
    $pixmap->draw_points($style->base_gc('normal'), 0, 1);
    $window->set_back_pixmap($pixmap);
}

sub add2notebook {
    my ($n, $title, $book) = @_;
    $n->append_page($book, gtkshow(gtknew('Label', text => $title)));
    $book->show;
}

sub string_size {
    my ($widget, $text) = @_;
    my $layout = $widget->create_pango_layout($text);
    my @size = $layout->get_pixel_size;
    @size;
}

sub string_width {
    my ($widget, $text) = @_;
    my ($width, undef) = string_size($widget, $text);
    $width;
}


my ($def_step_title);
sub set_default_step_items {
    $def_step_title = translate($_[0]);
}

sub get_default_step_items { ($def_step_title) }

# -=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---
#                 toplevel window creation helper
#
# Use the 'new' function as a method constructor and then 'main' on it to
# launch the main loop. Use $o->{retval} to indicate that the window needs
# to terminate.
# Set $::isWizard to have a wizard appearance.
# Set $::isEmbedded and $::XID so that the window will plug.

sub new {
    my ($type, $title, %opts) = @_;

    my $o = bless { %opts }, $type;
    while (my $e = shift @tempory::objects) { $e->destroy }

    my $icon = find { _find_imgfile($_) } $::isInstall ? 'empty-banner' : $opts{icon};
    my $banner_title = $opts{banner_title};
    $o->{transient} ||= $::main_window if $::main_window && !$opts{do_not_track_main_window};
    my $window = gtknew(
	'MagicWindow',
	title => $title || '',
	pop_it => $o->{pop_it},
	$::isInstall ? (banner => gtknew('Install_Title', text => $title || get_default_step_items())) : (),
	$::isStandalone && $banner_title && $icon ? (banner => Gtk3::Banner->new($icon, $banner_title)) : (),
	width => $opts{width}, height => $opts{height}, default_width => $opts{default_width}, default_height => $opts{default_height}, 
	modal => (!$o->{pop_it} && !$::isInstall) && ($opts{modal} || $grab || $o->{grab}) || $o->{modal},
	no_Window_Manager => exists $opts{no_Window_Manager} ? $opts{no_Window_Manager} : !$::isStandalone,
	if_(!$::isInstall, icon_no_error => wm_icon()),
	if_($o->{transient}, transient_for => $o->{transient}), 
    );
    mygtk3::register_main_window($window->{real_window}) if !$opts{do_not_track_main_window};
    $window->set_border_width(10) if !$window->{pop_it} && !$::noborderWhenEmbedded;

    $o->{rwindow} = $o->{window} = $window;
    $o->{real_window} = $window->{real_window};
    $o->{pop_it} = $window->{pop_it};

    $o;
}

sub main {
    my ($o, $o_completed, $o_canceled) = @_;
    gtkset_mousecursor_normal();

    $o->show;
    mygtk3::main($o->{rwindow},
		 sub { $o->{retval} ? !$o_completed || $o_completed->() : !$o_canceled || $o_canceled->() });
    $o->{retval};
}
sub show($) {
    my ($o) = @_;
    $o->{rwindow}->show;
}
sub destroy($) {
    my ($o) = @_;
    $o->{rwindow}->destroy;
    flush();
}
sub DESTROY { goto &destroy }
sub sync {
    my ($o) = @_;
    show($o);
    flush();
}
sub flush() { gtkflush() }
sub shrink_topwindow {
    my ($o) = @_;
    $o->{real_window}->resize(1, 1);
}
sub exit {
    gtkset_mousecursor_normal(); #- for restoring a normal in any case
    flush();
    if ($::isStandalone) {
        require standalone;
        standalone::__exit($_[1]); #- workaround
    } else {
        c::_exit($_[1]); #- workaround
    }
}

#- in case "exit" above was not called by the program
END { &exit() }

# -=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---
#                 ask
#
# Full UI managed functions that will return to you the value that the
# user chose.

sub ask_warn       { my $w = ugtk3->new(shift @_, grab => 1); $w->_ask_warn(@_); main($w) }
sub ask_yesorno    { my $w = ugtk3->new(shift @_, grab => 1); $w->_ask_okcancel(@_, N("Yes"), N("No")); main($w) }
sub ask_okcancel   { my $w = ugtk3->new(shift @_, grab => 1); $w->_ask_okcancel(@_, N("Is this correct?"), N("Ok"), N("Cancel")); main($w) }
sub ask_from_entry { my $w = ugtk3->new(shift @_, grab => 1); $w->_ask_from_entry(@_); main($w) }
sub ask_dir        { my $w = ugtk3->new(shift @_, grab => 1); $w->_ask_dir(@_); main($w) }

sub _ask_from_entry($$@) {
    my ($o, @msgs) = @_;
    my $entry = gtknew('Entry');
    my $f = sub { $o->{retval} = $entry->get_text; Gtk3->main_quit };
    $o->{ok_clicked} = $f;
    $o->{cancel_clicked} = sub { undef $o->{retval}; Gtk3->main_quit };

    gtkadd($o->{window},
	  gtkpack($o->create_box_with_title(@msgs),
		 gtksignal_connect($entry, 'activate' => $f),
		 ($o->{hide_buttons} ? () : create_okcancel($o))),
	  );
    $entry->grab_focus;
}

sub _ask_warn($@) {
    my ($o, @msgs) = @_;
    gtkadd($o->{window},
	  gtkpack($o->create_box_with_title(@msgs),
		  my $w = gtknew('Button', text => N("Ok"), clicked => sub { Gtk3->main_quit }),
		 ),
	  );
    $w->grab_focus;
}

sub _ask_okcancel($@) {
    my ($o, @msgs) = @_;
    my ($ok, $cancel) = splice @msgs, -2;

    gtkadd($o->{window},
	   gtkpack(create_box_with_title($o, @msgs),
		   create_okcancel($o, $ok, $cancel),
		 )
	 );
    $o->{ok}->grab_focus;
}

sub create_file_selector {
    my (%opts) = @_;
    my $w = ugtk3->new(delete $opts{title}, modal => 1);
    my ($message, $save, $want_a_dir) = (delete $opts{message}, delete $opts{save}, delete $opts{want_a_dir});
    my $action = $want_a_dir ? ($save ? 'create_folder' : 'select_folder') : ($save ? 'save' : 'open');
    add2hash(\%opts, { width => 480, height => 250 });
    gtkadd($w->{window},
	   gtkpack_(create_box_with_title($w, $message),
		    1, $w->{chooser} = gtknew('FileChooser', action => $action, %opts),
		    0, create_okcancel($w),
		 ));
    $w->{chooser}->signal_connect(file_activated => sub { $w->{ok}->clicked });
    $w;
}

sub file_selected_check {
    my ($save, $want_a_dir, $file) = @_;

    if (!$file) {
	N("No file chosen");
    } elsif (-f $file && $want_a_dir) {
	N("You have chosen a file, not a directory");
    } elsif (-d $file && !$want_a_dir) {
	N("You have chosen a directory, not a file");
    } elsif (!-e $file && !$save) {
	$want_a_dir ? N("No such directory") : N("No such file");
    } else {
	'';
    }
}

sub _ask_file {
    my ($o, $title, $path) = @_;

    my $w = create_file_selector(title => $title, want_a_dir => 0, directory => $path);
    put_in_hash($o, $w);

    $w->{ok}->signal_connect(clicked => sub { $o->{retval} = $w->{chooser}->get_filename });
}
sub _ask_dir {
    my ($o, $title, $path) = @_;

    my $w = create_file_selector(title => $title, want_a_dir => 1, directory => $path);
    put_in_hash($o, $w);

    $w->{ok}->signal_connect(clicked => sub { $o->{retval} = $w->{chooser}->get_filename });
}

sub ask_browse_tree_info {
    my ($common) = @_;

    my $w = ugtk3->new($common->{title});

    my $tree_model = Gtk3::TreeStore->new("Glib::String", "Gtk3::Gdk::Pixbuf", "Glib::String");
    my $tree = Gtk3::TreeView->new_with_model($tree_model);
    $tree->get_selection->set_mode('browse');
    $tree->append_column(my $textcolumn = Gtk3::TreeViewColumn->new_with_attributes("", Gtk3::CellRendererText->new, 'text' => 0));
    $tree->append_column(my $pixcolumn  = Gtk3::TreeViewColumn->new_with_attributes("", Gtk3::CellRendererPixbuf->new, 'pixbuf' => 1));
    $tree->append_column(Gtk3::TreeViewColumn->new_with_attributes("", Gtk3::CellRendererText->new, 'text' => 2));
    $tree->set_headers_visible(0);
    $tree->set_rules_hint(1);
    $textcolumn->set_min_width(200);
    $textcolumn->set_max_width(200);

    gtkadd($w->{window}, 
	   gtknew('VBox', spacing => 5, children => [
		    0, gtknew('Title2', label => $common->{message},
                              # workaround infamous 6 years old gnome bug #101968:
                              width => mygtk3::get_label_width()),
		    1, gtknew('VBox', children => [
			       1, gtknew('ScrolledWindow', child => $tree),
			       0, gtknew('Frame', text => N("Info"), child =>
				      gtknew('ScrolledWindow', child => my $info = gtknew('TextView', editable => 0, height => 100)),
				     ) ]),
		    0, Gtk3::HSeparator->new,
		    0, my $status = gtknew('Label'),
		    ($common->{auto_deps} ?
		        (0, gtknew('CheckButton', text => $common->{auto_deps}, active_ref => \$common->{state}{auto_deps})) : ()
		    ),
		    0, Gtk3::HSeparator->new,
		    0, my $box2 = gtknew('HBox', spacing => 10),
		   ]));

    gtkpack__($box2, gtknew(($::isInstall ? 'Install_Button' : 'Button'), text => N("Help"),
                            clicked => $common->{interactive_help})) if $common->{interactive_help};

    #gtkpack__($box2, my $toolbar = Gtk3::Toolbar->new('horizontal', 'icons'));
    gtkpack__($box2, my $toolbar = Gtk3::Toolbar->new);

    my @l = ([ $common->{ok}, 1 ], if_($common->{cancel}, [ $common->{cancel}, 0 ]));
    @l = reverse @l if !$::isInstall;
    my @buttons = map {
	my ($t, $val) = @$_;
	$box2->pack_end(my $w = gtknew('Button', text => $t, clicked => sub {
					   $w->{retval} = $val;
					   Gtk3->main_quit;
				       }), 0, 1, 20);
	$w->show;
	$w;
    } @l;
    @buttons = reverse @buttons if !$::isInstall;    

    $status->show;

    $w->{window}->set_size_request(map { $_ - 2 * $border - 4 } $w->{windowwidth}, $w->{windowheight}) if !$::isInstall;
    $buttons[0]->grab_focus;
    $w->{rwindow}->show;

    my @toolbar;
    foreach my $ic (@{$common->{icons} || []}) {
	push @toolbar, ($ic->{icon} => [ $ic->{help}, sub {
					     if ($ic->{code}) {
						 my $_w = $ic->{wait_message} && $common->{wait_message}->('', $ic->{wait_message});
						 $ic->{code}();
						 $common->{rebuild_tree}->();
					     }
					 } ]);
    }
    my %toolbar = @toolbar;
    foreach (grep_index { $::i % 2 == 0 } @toolbar) {
	my $t = gtknew('ToolButton', tooltip => $toolbar{$_}[0], file => "$_.png", clicked => $toolbar{$_}[1]);
	$toolbar->insert($t, -1);
    }

    $pixcolumn->{is_pix} = 1;
    $common->{widgets} = { w => $w, tree => $tree, tree_model => $tree_model,
                           info => $info, status => $status };
    ask_browse_tree_info_given_widgets($common);
}

sub ask_browse_tree_info_given_widgets {
    my ($common) = @_;
    my $w = $common->{widgets};

    my ($curr, $prev_label, $idle, $mouse_toggle_pending);
    my (%wtree, %ptree, %pix, %node_state, %state_stats);
    my $update_size = sub {
	if ($w->{status}) {
	    my $new_label = $common->{get_status}();
	    $prev_label ne $new_label and $w->{status}->set($prev_label = $new_label);
	}
    };
    
    my $set_node_state_flat = sub {
	my ($iter, $state) = @_;
	$state eq 'XXX' and return;
        $pix{$state} ||= gtkcreate_pixbuf($state);
        $w->{tree_model}->set($iter, 1 => $pix{$state});
    };
    my $set_node_state_tree; $set_node_state_tree = sub {
	my ($iter, $state) = @_;
	my $iter_str = $w->{tree_model}->get_path_str($iter);
	$state eq 'XXX' and return;
        $pix{$state} ||= gtkcreate_pixbuf($state);
	if ($node_state{$iter_str} ne $state) {
	    my $parent;
	    if (!$w->{tree_model}->iter_has_child($iter) && ($parent = $w->{tree_model}->iter_parent($iter))) {
		my $parent_str = $w->{tree_model}->get_path_str($parent);
		my $stats = $state_stats{$parent_str} ||= {}; $stats->{$node_state{$iter_str}}--; $stats->{$state}++;
		my @list = grep { $stats->{$_} > 0 } keys %$stats;
		my $new_state = @list == 1 ? $list[0] : 'semiselected';
		$node_state{$parent_str} ne $new_state and $set_node_state_tree->($parent, $new_state);
	    }
            $w->{tree_model}->set($iter, 1 => $pix{$state});
	    $node_state{$iter_str} = $state;  #- cache for efficiency
	}
    };
    my $set_node_state = $common->{state}{flat} ? $set_node_state_flat : $set_node_state_tree;

    my $set_leaf_state = sub {
	my ($leaf, $state) = @_;
	$set_node_state->($_, $state) foreach @{$ptree{$leaf}};
    };
    my $add_parent; $add_parent = sub {
	my ($root, $state) = @_;
	$root or return undef;
	if (my $w = $wtree{$root}) { return $w }
	my $s; foreach (split '\|', $root) {
	    my $s2 = $s ? "$s|$_" : $_;
	    $wtree{$s2} ||= do {
		my $iter = $w->{tree_model}->append_set($s ? $add_parent->($s, $state) : undef, [ 0 => $_ ]);
		$iter;
	    };
	    $s = $s2;
	}
	$set_node_state->($wtree{$s}, $state); #- use this state by default as tree is building.
	$wtree{$s};
    };
    my $add_node = sub {
	my ($leaf, $root, $options) = @_;
	my $state = $common->{node_state}($leaf) or return;
	if ($leaf) {
	    my $iter = $w->{tree_model}->append_set($add_parent->($root, $state), [ 0 => $leaf ]);
	    $set_node_state->($iter, $state);
	    push @{$ptree{$leaf}}, $iter;
	} else {
	    my $parent = $add_parent->($root, $state);
	    #- hackery for partial displaying of trees, used in rpmdrake:
	    #- if leaf is void, we may create the parent and one child (to have the [+] in front of the parent in the ctree)
	    #- though we use '' as the label of the child; then rpmdrake will connect on tree_expand, and whenever
	    #- the first child has '' as the label, it will remove the child and add all the "right" children
	    $options->{nochild} or $w->{tree_model}->append_set($parent, [ 0 => '' ]);
	}
    };
    my $clear_all_caches = sub {
	foreach (values %ptree) {
	    foreach my $n (@$_) {
		delete $node_state{$w->{tree_model}->get_path_str($n)};
	    }
	}
	foreach (values %wtree) {
	    my $iter_str = $w->{tree_model}->get_path_str($_);
	    delete $node_state{$iter_str};
	    delete $state_stats{$iter_str};
	}
	%ptree = %wtree = ();
    };
    $common->{delete_all} = sub {
	$clear_all_caches->();
	$w->{tree_model}->clear;
    };
    $common->{rebuild_tree} = sub {
	$common->{delete_all}->();
	$set_node_state = $common->{state}{flat} ? $set_node_state_flat : $set_node_state_tree;
	$common->{build_tree}($add_node, $common->{state}{flat}, $common->{tree_mode});
	&$update_size;
    };
    $common->{delete_category} = sub {
	my ($cat) = @_;
	exists $wtree{$cat} or return;
	foreach (keys %ptree) {
	    my @to_remove;
	    foreach my $node (@{$ptree{$_}}) {
		my $category;
		my $parent = $node;
		my @parents;
		while ($parent = $w->{tree_model}->iter_parent($parent)) {    #- LEAKS
		    my $parent_name = $w->{tree_model}->get($parent, 0);
		    $category = $category ? "$parent_name|$category" : $parent_name;
		    $_->[1] = "$parent_name|$_->[1]" foreach @parents;
		    push @parents, [ $parent, $category ];
		}
		if ($category =~ /^\Q$cat/) {
		    push @to_remove, $node;
		    foreach (@parents) {
			next if $_->[1] eq $cat || !exists $wtree{$_->[1]};
			delete $wtree{$_->[1]};
			delete $node_state{$w->{tree_model}->get_path_str($_->[0])};
			delete $state_stats{$w->{tree_model}->get_path_str($_->[0])};
		    }
		}
	    }
	    foreach (@to_remove) {
		delete $node_state{$w->{tree_model}->get_path_str($_)};
	    }
	    @{$ptree{$_}} = difference2($ptree{$_}, \@to_remove);
	}
	if (exists $wtree{$cat}) {
	    my $iter_str = $w->{tree_model}->get_path_str($wtree{$cat});
	    delete $node_state{$iter_str};
	    delete $state_stats{$iter_str};
	    $w->{tree_model}->remove($wtree{$cat});
	    delete $wtree{$cat};
	}
	&$update_size;
    };
    $common->{add_nodes} = sub {
	my (@nodes) = @_;
	$add_node->($_->[0], $_->[1], $_->[2]) foreach @nodes;
	&$update_size;
    };
    
    $common->{display_info} = sub { gtktext_insert($w->{info}, $common->{get_info}($curr)); 0 };
    my $children = sub { map { $w->{tree_model}->get($_, 0) } gtktreeview_children($w->{tree_model}, $_[0]) };
    my $toggle = sub {
	if (ref($curr) && !$_[0]) {
	    $w->{tree}->toggle_expansion($w->{tree_model}->get_path($curr));
	} else {
	    if (ref $curr) {
		my @l = $common->{grep_allowed_to_toggle}($children->($curr)) or return;
		my @unsel = $common->{grep_unselected}(@l);
		my @p = @unsel ?
		  #- not all is selected, select all if no option to potentially override
		  (exists $common->{partialsel_unsel} && $common->{partialsel_unsel}->(\@unsel, \@l) ? difference2(\@l, \@unsel) : @unsel)
		  : @l;
		$common->{toggle_nodes}($set_leaf_state, @p);
		&$update_size;
	    } else {
		$common->{check_interactive_to_toggle}($curr) and $common->{toggle_nodes}($set_leaf_state, $curr);
		&$update_size;
	    }
	}
    };

    $w->{tree}->signal_connect(key_press_event => sub {
	my $c = chr($_[1]->keyval & 0xff);
	if ($_[1]->keyval >= 0x100 ? $c eq "\r" || $c eq "\x8d" : $c eq ' ') {
	    $toggle->(0);
	}
	0;
    });

    $w->{tree}->get_selection->signal_connect(changed => sub {
	my ($model, $iter) = $_[0]->get_selected;
	$model && $iter or return;
	Glib::Source->remove($idle) if $idle;
	
	if (!$model->iter_has_child($iter)) {
	    $curr = $model->get($iter, 0);
	    $idle = Glib::Timeout->add(100, $common->{display_info});
	} else {
	    $curr = $iter;
	}
	#- the following test for equality is because we can have a button_press_event first, then
	#- two changed events, the first being on a different row :/ (is it a bug in gtk3?) - that
	#- happens in rpmdrake when doing a "search" and directly trying to select a found package
	if ($mouse_toggle_pending eq $model->get($iter, 0)) {
	    $toggle->(1);
            $mouse_toggle_pending = 0;
	}
	0;
    });
    $w->{tree}->signal_connect(button_press_event => sub {  #- not too good, but CellRendererPixbuf does not have the needed signals :(
	my (undef, $event) = @_;
	return if $event =~ /Gtk3::Gdk::Event=/;
	my ($path, $column) = $w->{tree}->get_path_at_pos($event->x, $event->y);
	if ($path && $column) {
	    $column->{is_pix} and $mouse_toggle_pending = $w->{tree_model}->get($w->{tree_model}->get_iter($path), 0);
	}
        0;
    });
    $common->{rebuild_tree}->();
    &$update_size;
    $common->{initial_selection} and $common->{toggle_nodes}($set_leaf_state, @{$common->{initial_selection}});
    my $_b = before_leaving { $clear_all_caches->() };
    $common->{init_callback}->() if $common->{init_callback};
    $w->{w}->main;
}

sub gtk_set_treelist {
    my ($treelist, $l) = @_;

    my $list = $treelist->get_model;
    $list->clear;
    $list->append_set([ 0 => $_ ]) foreach @$l;
}


sub gtk_TextView_get_log {
    my ($log_w, $command, $filter_output, $when_command_is_over) = @_;

    my $pid = open(my $F, "$command |") or return;
    common::nonblock($F);

    my $gtk_buffer = $log_w->get_buffer;
    $log_w->signal_connect(destroy => sub { 
	kill 9, $pid if $pid; #- we do not continue in background
	$pid = $gtk_buffer = ''; #- ensure $gtk_buffer is valid when its value is non-null
    });

    Glib::Timeout->add(100, sub {
        if ($gtk_buffer) {
	    my $end = $gtk_buffer->get_end_iter;
	    while (defined (my $s = <$F>)) {
		$gtk_buffer->insert($end, $filter_output->($s));
	    }
	    $log_w->{to_bottom}->();
	}
	if (waitpid($pid, c::WNOHANG()) > 0) {
	    #- we do not call $when_command_is_over if $gtk_buffer does not exist anymore
	    #- since it is not a normal case
	    $when_command_is_over->($gtk_buffer) if $when_command_is_over && $gtk_buffer;
	    $pid = '';
	    0;
	} else {
	    to_bool($gtk_buffer);
	}
    });
    $pid; #- $pid becomes invalid after $when_command_is_over is called
}

sub gtk_new_TextView_get_log {
    my ($command, $filter_output, $when_command_is_over) = @_;

    my $log_w = gtknew('TextView', editable => 0);
    my $log_scroll = gtknew('ScrolledWindow', child => $log_w, to_bottom => 1);
    my $pid = gtk_TextView_get_log($log_w, $command, $filter_output, $when_command_is_over) or return;
    $log_scroll, $pid;
}

# misc helpers:

package Gtk3::TreeStore;
sub append_set {
    my ($model, $parent, @values) = @_;
    # compatibility:
    @values = @{$values[0]} if @values == 1 && ref($values[0]) eq 'ARRAY';
    my $iter = $model->append($parent);
    $model->set($iter, @values);
    return $iter;
}


package Gtk3::ListStore;
# Append a new row, set the values, return the TreeIter
sub append_set {
    my ($model, @values) = @_;
    # compatibility:
    @values = @{$values[0]} if @values == 1 && ref($values[0]) eq 'ARRAY';
    my $iter = $model->append;
    $model->set($iter, @values);
    return $iter;
}


package Gtk3::TreeModel;
# gets the string representation of a TreeIter
sub get_path_str {
    my ($self, $iter) = @_;
    my $path = $self->get_path($iter);
    $path or return;
    $path->to_string;
}

sub iter_each_children {
    my ($model, $iter, $f) = @_;
    my $child = $model->iter_children($iter);
    while ($child = $model->iter_next($child)) {
	$f->($child);
    }
}

package Gtk3::TreeView;
# likewise gtk-1.2 function
sub toggle_expansion {
    my ($self, $path, $b_open_all) = @_;
    if ($self->row_expanded($path)) {
	$self->collapse_row($path);
    } else {
	$self->expand_row($path, $b_open_all || 0);
    }
}

package Gtk3::ComboBox;
use MDK::Common;

# try to get combox <==> option menu mapping
sub set_popdown_strings {
    my ($w, @strs) = @_;
    my $model = $w->get_model;
    return if !$model;
    $w->get_model->clear;
    # keep string list around for ->set_text compatibilty helper
    $w->{strings} = \@strs;
    $w->append_text($_) foreach @strs;
    $w;
}

sub new_with_strings {
    my ($class, $strs, $o_val) = @_;
    my $w = $class->new;
    $w->set_popdown_strings(@$strs);
    $w->set_text($o_val) if $o_val;
    $w;
}

sub entry {
    my ($w) = @_;
    return $w;
}

sub get_text {
    my ($w) = @_;
    $w->get_active == -1 ? '' : $w->{strings}[$w->get_active];
}

sub set_text {
    my ($w, $val) = @_;
    eval { 
	my $val_index = find_index { $_ eq $val } @{$w->{strings}};
	$w->set_active($val_index);
    };
    # internal_error(qq(impossible to lookup "$val":\n\t) . chomp_($@)) if $@;
}


package Gtk3::ComboBoxText;

# try to get combox <==> option menu mapping
*new_with_strings    = *Gtk3::ComboBox::new_with_strings;
*set_popdown_strings = *Gtk3::ComboBox::set_popdown_strings;
*get_text = *Gtk3::ComboBox::get_text;
*set_text = *Gtk3::ComboBox::set_text;


package Gtk3::Label;
sub set {
    my ($label, $text) = @_;
    mygtk3::gtkset($label, text => $text);
}


package Gtk3::WrappedLabel;
sub new {
    my ($_type, $o_text, $o_align) = @_;
    mygtk3::gtknew('WrappedLabel', text => $o_text || '', alignment => [ $o_align || 0, 0.5 ]);
}


package Gtk3::Entry;
sub new_with_text {
    my ($_class, $o_text) = @_;
    mygtk3::gtknew('Entry', text => $o_text);
}


package Gtk3::Banner;

use MDK::Common;
use mygtk3 qw(gtknew);
use ugtk3 qw(:helpers :wrappers);

sub set_style {
   my ($w) = @_;
   my $pl = Gtk3::CssProvider->new;
   $pl->load_from_data("Layout, GtkLabel {font: 15px; background-color: #ffffff }");
   $w->{label}->get_style_context->add_provider($pl, Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION);
   my $p = Gtk3::CssProvider->new;
   $w->get_style_context->add_provider($p, Gtk3::STYLE_PROVIDER_PRIORITY_APPLICATION);
}

# used by install::steps_gtk::installPackages()
sub update_text {
    my ($banner, $new_text) = @_;
    $banner->{label}->set_text($new_text);
    $banner->{label}->queue_draw;
}

sub new {
    my ($_class, $icon, $text, $o_options) = @_;

    mygtk3::import_style_ressources();
    my $icon = eval { ugtk3::gtkcreate_pixbuf($icon) };
    $icon ||= ugtk3::gtkcreate_pixbuf(ugtk3::wm_icon());
    my $is_rtl = mygtk3::text_direction_rtl();
    my $blue_part = eval { gtknew('Pixbuf', file => 'banner-blue-part', flip => $is_rtl) };

    my $d_height = $blue_part->get_height;
    

    my $img = gtknew('Image', pixbuf => $blue_part, alignment => [ 0, 0 ]);

    my $label = gtknew('Label', text => $text, padding => [ 100, 0 ], alignment => [ 0, 0.5 ]); # for update_text()
    my $w = gtknew('Overlay', height => $d_height, widget_name => 'Banner', main_child => $label, children => [
		       gtknew('Overlay', main_child => $img, children => [
				  my $icon_img = gtknew('Image', pixbuf => $icon, alignment => [ 0, 0 ]),
			      ])
		   ]);

    # fix Icon position:
    if ($is_rtl) {
	$icon_img->set_margin_right(12);
    } else {
	$icon_img->set_margin_left(12);
    }
    $icon_img->set_margin_top(($blue_part->get_height-$icon->get_height)/2-4);

    $w->{label} = $label;
    $w->set_size_request(-1, $d_height);

    $w->signal_connect(realize => \&set_style);
    $w->signal_connect("style-updated" => \&set_style);
    $w->show_all;
    return $w;
}


package Gtk3::Notify::Queue;

sub new {
    my ($class, $statusicon) = @_;

    require Gtk3::Notify;

    my $self = bless {
        queue => [],
        statusicon => $statusicon,
        display => 5000,
        delay => 500,
    }, $class;
    $self;
}

sub process_next {
    my ($self) = @_;
    shift @{$self->{queue}};
    #- wait for some time so that the new notification is noticeable
    @{$self->{queue}} and Glib::Timeout->add($self->{delay}, sub { $self->show; 0 });
}

sub add {
    my ($self, $info) = @_;
    push @{$self->{queue}}, $info;
    # We don't always receive the 'closed' signal (especially when not clicked)
    # and in those case we'll never show the next notifications:
    #@{$self->{queue}} == 1 and
    $self->show;
}

sub show {
    my ($self) = @_; # perl_checker: $self = Gtk3::Notify::Notification->new
    my $info = $self->{queue}[0];
    my $notification = Gtk3::Notify::Notification->new($info->{title}, $info->{message}, $self->{statusicon});
    $notification->set_icon_from_pixbuf($info->{pixbuf}) if $info->{pixbuf};
    $notification->set_urgency($info->{urgency}) if $info->{urgency};
    foreach my $a (@{$info->{actions} || []}) {
        $notification->add_action(
            $a->{action}, $a->{label},
            sub {
                $info->{processed} = 1;
                #- $a->{callback} has to call $selft->process_next when done
                $a->{callback}->();
            });
    }
    $notification->signal_connect(closed => sub {
                                        $info->{processed} and return;
                                        $info->{timeout}->() if $info->{timeout};
                                        $self->process_next;
                                    });
    eval { $notification->show };
}

1;


package Gtk3::GUI_Update_Guard;

use MDK::Common::Func qw(before_leaving);
use ugtk3;

sub new {
    my ($_class) = @_; # prevent a perl_checker warning in callers
    my $old_signal = $SIG{ALRM};
    $SIG{ALRM} = sub {
        ugtk3::gtkflush();
        alarm(1);
    };
    alarm(1);
    return before_leaving {
        alarm(0);
        $SIG{ALRM} = $old_signal || 'DEFAULT';   # restore default action
    };
}

1;
