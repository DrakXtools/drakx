package ugtk2;

use diagnostics;
use strict;
use vars qw(@ISA %EXPORT_TAGS @EXPORT_OK @icon_paths $wm_icon $force_center_at_pos $force_center $force_focus $grab $pop_it $border); #- leave it on one line, for automatic removal of the line at package creation
use lang;

$::o = { locale => lang::read() } if !$::isInstall;

@ISA = qw(Exporter);
%EXPORT_TAGS = (
    wrappers => [ qw(gtkadd gtkadd_widget gtkappend gtkappend_page gtkappenditems gtkcombo_setpopdown_strings gtkdestroy
                     gtkentry gtkflush gtkhide gtkmodify_font gtkmove gtkpack gtkpack2 gtkpack2_
                     gtkpack2__ gtkpack_ gtkpack__ gtkpowerpack gtkput gtkradio gtkresize gtkroot
                     gtkset_active gtkset_border_width gtkset_editable gtkset_justify gtkset_alignment gtkset_layout gtkset_line_wrap
                     gtkset_markup gtkset_modal gtkset_mousecursor gtkset_mousecursor_normal gtkset_mousecursor_wait gtkset_name
                     gtkset_property gtkset_relief gtkset_selectable gtkset_sensitive gtkset_shadow_type gtkset_size_request
                     gtkset_text gtkset_tip gtkset_visibility gtksetstyle gtkshow gtksignal_connect gtksize gtktext_append
                     gtktext_insert ) ],

    helpers => [ qw(add2notebook add_icon_path fill_tiled fill_tiled_coords gtkcolor gtkcreate_img
                    gtkcreate_pixbuf gtkfontinfo gtkset_background n_line_size set_back_pixbuf set_back_pixmap
                    string_size string_width string_height wrap_paragraph) ],

    create => [ qw(create_adjustment create_box_with_title create_dialog create_factory_menu create_factory_popup_menu
                   create_hbox create_hpaned create_menu create_notebook create_okcancel create_packtable
                   create_scrolled_window create_vbox create_vpaned _create_dialog gtkcreate_frame) ],

    ask => [ qw(ask_browse_tree_info ask_browse_tree_info_given_widgets ask_dir ask_from_entry ask_okcancel ask_warn
                ask_yesorno ) ],
    dialogs => [ qw(err_dialog info_dialog warn_dialog) ],

);
$EXPORT_TAGS{all} = [ map { @$_ } values %EXPORT_TAGS ];
@EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

use c;
use log;
use common;

use Gtk2;
use Gtk2::Gdk::Keysyms;

unless ($::no_ugtk_init) {
    !check_for_xserver() and die "Cannot be run in console mode.\n";
    $::one_message_has_been_translated and warn("N() was called from $::one_message_has_been_translated BEFORE gtk2 initialisation, replace it with a N_() AND a translate() later.\n"), c::_exit(1);

    Gtk2->init;
    c::bind_textdomain_codeset($_, 'UTF8') foreach 'libDrakX', @::textdomains;
    $::need_utf8_i18n = 1;
}
Gtk2->croak_execeptions if (!$::no_ugtk_init || $::isInstall) && 0.95 < $Gtk2::VERSION;


$border = 5;


# -=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---
#                 wrappers
#
# Functional-style wrappers to existing Gtk functions; allows to program in
# a more functional way, and especially, first, to avoid using temp
# variables, and second, to "see" directly in the code the user interface
# you're building.

sub gtkdestroy                { $_[0] and $_[0]->destroy }
sub gtkflush()                { Gtk2->main_iteration while Gtk2->events_pending }
sub gtkhide                   { $_[0]->hide; $_[0] }
sub gtkmove                   { $_[0]->window->move($_[1], $_[2]); $_[0] }
sub gtkpack                   { gtkpowerpack(1, 1, @_) }
sub gtkpack_                  { gtkpowerpack('arg', 1, @_) }
sub gtkpack__                 { gtkpowerpack(0, 1, @_) }
sub gtkpack2                  { gtkpowerpack(1, 0, @_) }
sub gtkpack2_                 { gtkpowerpack('arg', 0, @_) }
sub gtkpack2__                { gtkpowerpack(0, 0, @_) }
sub gtkput                    { $_[0]->put(gtkshow($_[1]), $_[2], $_[3]); $_[0] }
sub gtkresize                 { $_[0]->window->resize($_[1], $_[2]); $_[0] }
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
sub gtkset_tip                { $_[0]->set_tip($_[1], $_[2]) if $_[2]; $_[1] }
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
	ref $l or $l = Gtk2::WrappedLabel->new($l);
	$w->add(gtkshow($l));
    }
    $w
}

sub gtkadd_widget {
    my $sg = shift;
    map {
        my $l = $_;
        ref $l or $l = Gtk2::WrappedLabel->new($l);
        $sg->add_widget($l);
        $l;
    } @_;
}

sub gtkappend {
    my $w = shift;
    foreach my $l (@_) {
	ref $l or $l = Gtk2::WrappedLabel->new($l);
	$w->append(gtkshow($l));
    }
    $w
}

sub gtkappenditems {
    my $w = shift;
    $_->show foreach @_;
    $w->append_items(@_);
    $w
}

# append page to a notebook
sub gtkappend_page {
    my $w = shift;
    $w->append_page(@_);
    $w
}

sub gtkentry {
    my ($text) = @_;
    my $e = Gtk2::Entry->new;
    $text and $e->set_text($text);
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
    map { gtkset_active($radio = Gtk2::RadioButton->new_with_label($radio ? $radio->get_group : undef, $_), $_ eq $def) } @_;
}

sub gtkroot() {
    my $root if 0;
    $root ||= Gtk2::Gdk->get_default_root_window;
}

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
    ($w || gtkroot())->set_cursor(Gtk2::Gdk::Cursor->new($type));
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
		ref($_[0]) and die "error in packing definition\n";
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
	my $widget = ref($_[0]) ? shift : Gtk2::WrappedLabel->new(shift);
	my $pack_call = 'pack_'.($attr{pack_end} ? 'end' : 'start');
	$box->$pack_call($widget, $attr{expand}, $attr{fill}, $attr{padding});
	$widget->show;
    }
    return $box;
}

sub gtktreeview_children {
    my ($model, $iter) = @_;
    my @l;
    $model && $iter or return;
    for (my $p = $model->iter_children($iter); $p; $p = $model->iter_next($p)) {
	push @l, $p;
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
    gtkadd(Gtk2::Button->new,
	   gtkpack_(Gtk2::HBox->new(0, 3),
		    1, "",
		    $reverse_order ? reverse(@label_and_pix) : @label_and_pix,
		    1, ""));
}

sub create_adjustment {
    my ($val, $min, $max) = @_;
    Gtk2::Adjustment->new($val, $min, $max + 1, 1, ($max - $min + 1) / 10, 1);
}

sub create_scrolled_window {
    my ($W, $o_policy, $o_viewport_shadow) = @_;
    my $w = Gtk2::ScrolledWindow->new(undef, undef);
    $w->set_policy($o_policy ? @$o_policy : ('automatic', 'automatic'));
    if (member(ref($W), qw(Gtk2::Layout Gtk2::Text Gtk2::TextView Gtk2::TreeView))) {
	$w->add($W)
    } else {
	$w->add_with_viewport($W);
    }
    $o_viewport_shadow and gtkset_shadow_type($w->child, $o_viewport_shadow);
    $W->can('set_focus_vadjustment') and $W->set_focus_vadjustment($w->get_vadjustment);
    $W->show;
    if (ref($W) =~ /Gtk2::TextView|Gtk2::TreeView/) {
    	gtkadd(gtkset_shadow_type(Gtk2::Frame->new, 'in'), $w)
    } else {
	$w
    }
}

sub n_line_size {
    my ($nbline, $type, $widget) = @_;
    my $spacing = ${{ text => 3, various => 17 }}{$type};
    my %fontinfo = gtkfontinfo($widget);
    round($nbline * ($fontinfo{ascent} + $fontinfo{descent} + $spacing) + 8);
}

sub create_box_with_title {
    my $o = shift;

    my $nbline = sum(map { round(length($_) / 60 + 1/2) } map { split "\n" } @_);
    my $box = Gtk2::VBox->new(0,0);
    if ($nbline == 0) {
	$o->{box_size} = 0;
	return $box;
    }
    $o->{box_size} = n_line_size($nbline, 'text', $box);
    if (@_ <= 2 && $nbline > 4) {
	$o->{icon} && !$::isWizard and 
	  eval { gtkpack__($box, gtkset_border_width(gtkpack_(Gtk2::HBox->new(0,0), 1, gtkcreate_img($o->{icon})),5)) };
	my $wanted = $o->{box_size};
	$o->{box_size} = min(200, $o->{box_size});
	my $has_scroll = $o->{box_size} < $wanted;

	my $wtext = Gtk2::TextView->new;
	$wtext->set_left_margin(3);
	$wtext->can_focus($has_scroll);
	$wtext->signal_connect(button_press_event => sub { 1 }); #- disable selecting text and popping the contextual menu (GUI team says it's *horrible* to be able to do select text!)
	chomp(my $text = join("\n", @_));
	my $scroll = create_scrolled_window(gtktext_insert($wtext, $text));
     my $width = 400;
     $scroll->signal_connect(realize => sub {
                                my $layout = $wtext->create_pango_layout($text);
                                $layout->set_width(($width - 10) * Gtk2::Pango->scale);
                                $wtext->set_size_request($width,  min(200, ($layout->get_pixel_size)[1] + 10));
                                $scroll->set_size_request($width, min(200, ($layout->get_pixel_size)[1] + 10));
                                $o->{rwindow}->queue_resize;
                            });
     $scroll->set_size_request($width, 200);
	gtkpack_($box, 0, $scroll);
    } else {
	my $a = !$::no_separator;
	undef $::no_separator;
     my $new_label = sub {
         my ($txt) = @_;
         my $w = ref($txt) ? $txt : Gtk2::WrappedLabel->new($txt);
         gtkset_name($w, "Title");
     };
	if ($o->{icon} && (!$::isWizard || $::isInstall)) {
	    gtkpack__($box,
		      gtkpack_(Gtk2::HBox->new(0,0),
			       0, gtkset_size_request(Gtk2::VBox->new(0,0), 15, 0),
			       0, eval { gtkcreate_img($o->{icon}) },
			       0, gtkset_size_request(Gtk2::VBox->new(0,0), 15, 0),
			       1, gtkpack_($o->{box_title} = Gtk2::VBox->new(0,0),
					   1, Gtk2::HBox->new(0,0),
					   (map {
					       my $w = $new_label->($_);
					       $::isWizard and $w->set_justify("left");
					       (0, $w);
					   } @_),
					   1, Gtk2::HBox->new(0,0),
					  )
			      ),
		      if_($a, Gtk2::HSeparator->new)
		     )
	} else {
	    gtkpack__($box,
		      if_($::isWizard, gtkset_size_request(Gtk2::Label->new, 0, 10)),
		      (map {
			  my $w = $new_label->($_);
			  $::isWizard ? gtkpack__(Gtk2::HBox->new(0,0), gtkset_size_request(Gtk2::Label->new, 20, 0), $w)
			              : $w
		      } @_),
		      if_($::isWizard, gtkset_size_request(Gtk2::Label->new, 0, 15)),
		      if_($a, Gtk2::HSeparator->new)
		     )
	}
    }
}

sub _create_dialog {
    my ($title, $o_options) = @_;
    my $dialog = Gtk2::Dialog->new;
    $dialog->set_title($title);
    $dialog->set_position('center-on-parent');  # center-on-parent doesn't work
    may_set_icon($dialog, $wm_icon || $::Wizard_pix_up || "wiz_default_up.png");
    $dialog->set_size_request($o_options->{width} || -1, $o_options->{height} || -1);
    $dialog->set_modal(1);
    $dialog->set_transient_for($o_options->{transient}) if $o_options->{transient};
    $dialog;
}


# drakfloppy / drakfont / harddrake2 / mcc
sub create_dialog {
    my ($title, $label, $o_options) = @_;
    my $ret = 0;
    my $dialog = _create_dialog($title, $o_options);
    $dialog->set_border_width(10);
    my $text = ref($label) ? $label : $o_options->{use_markup} ? gtkset_markup(Gtk2::WrappedLabel->new, $label) : Gtk2::WrappedLabel->new($label);
    gtkpack($dialog->vbox,
            gtkpack_(Gtk2::HBox->new,
                     if_($o_options->{stock}, 0, Gtk2::Image->new_from_stock($o_options->{stock}, 'dialog')),
                     1, $o_options->{scroll} ? create_scrolled_window($text, [ 'never', 'automatic' ]) : $text,
                    ),
           );

    if ($o_options->{cancel}) {
	my $button2 = Gtk2::Button->new(N("Cancel"));
	$button2->signal_connect(clicked => sub { $ret = 0; $dialog->destroy; Gtk2->main_quit });
	$button2->can_default(1);
	$dialog->action_area->pack_start($button2, 1, 1, 0);
    }

    my $button = Gtk2::Button->new(N("Ok"));
    $button->can_default(1);
    $button->signal_connect(clicked => sub { $ret = 1; $dialog->destroy; Gtk2->main_quit });
    $dialog->action_area->pack_start($button, 1, 1, 0);
    $button->grab_default;

    $dialog->show_all;
    Gtk2->main;
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

sub create_hbox { gtkset_layout(gtkset_border_width(Gtk2::HButtonBox->new, 3), $_[0] || 'spread') }
sub create_vbox { gtkset_layout(Gtk2::VButtonBox->new, $_[0] || 'spread') }

sub create_factory_menu_ {
    my ($type, $name, $window, @menu_items) = @_;
    my $widget = Gtk2::ItemFactory->new($type, $name, my $accel_group = Gtk2::AccelGroup->new);
    $widget->create_items($window, @menu_items);
    $window->add_accel_group($accel_group);
    ($widget->get_widget($name), $widget);
}

sub create_factory_popup_menu { create_factory_menu_("Gtk2::Menu", '<main>', @_) }
sub create_factory_menu { create_factory_menu_("Gtk2::MenuBar", '<main>', @_) }

sub create_menu {
    my $title = shift;
    my $w = Gtk2::MenuItem->new($title);
    $w->set_submenu(gtkshow(gtkappend(Gtk2::Menu->new, @_)));
    $w
}

sub create_notebook {
    my $n = Gtk2::Notebook->new;
    while (@_) {
	my ($title, $book) = splice(@_, 0, 2);
	add2notebook($n, $title, $book);
    }
    $n
}

sub create_packtable {
    my ($options, @l) = @_;
    my $w = Gtk2::Table->new(0, 0, $options->{homogeneous} || 0);
    add2hash_($options, { xpadding => 5, ypadding => 0 });
    each_index {
	my ($i, $l) = ($::i, $_);
	each_index {
	    my $j = $::i;
	    if ($_) {
		ref $_ or $_ = Gtk2::WrappedLabel->new($_);
		$j != $#$l && !$options->{mcc} ?
		  $w->attach($_, $j, $j + 1, $i, $i + 1,
			     'fill', 'fill', $options->{xpadding}, $options->{ypadding}) :
		  $w->attach($_, $j, $j + 1, $i, $i + 1,
			     ['expand', 'fill'], ref($_) eq 'Gtk2::ScrolledWindow' || $_->get_data('must_grow') ? ['expand', 'fill'] : [], 0, 0);
		$_->show;
	    }
	} @$l;
    } @l;
    $w->set_col_spacings($options->{col_spacings} || 0);
    $w->set_row_spacings($options->{row_spacings} || 0);
    $w
}

sub create_okcancel {
    my ($w, $o_ok, $o_cancel, $o_spread, @other) = @_;
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
    my $bok = $ok && gtksignal_connect($w->{ok} = Gtk2::Button->new($ok), clicked => $w->{ok_clicked} || sub { $w->{retval} = 1; Gtk2->main_quit });
    my $bprev;
    if ($cancel) {
        $bprev = gtksignal_connect($w->{cancel} = Gtk2::Button->new($cancel), clicked => $w->{cancel_clicked} || 
                                   sub { log::l("default cancel_clicked"); undef $w->{retval}; Gtk2->main_quit });
    }
    $w->{wizcancel} = gtksignal_connect(Gtk2::Button->new(N("Cancel")), clicked => sub { die 'wizcancel' }) if $::isWizard && !$::isInstall;
    my $f = sub { $w->{buttons}{$_[0][0]} = gtksignal_connect(Gtk2::Button->new($_[0][0]), clicked => $_[0][1]) };
    my @left  = ((map { $f->($_) } grep {  $_->[2] && !$_->[3] } @other),
                  map { $f->($_) } grep { !$_->[2] && !$_->[3] } @other);
    my @right = ((map { $f->($_) } grep {  $_->[2] &&  $_->[3] } @other),
                  map { $f->($_) } grep { !$_->[2] &&  $_->[3] } @other);
    # we put space to group buttons in two packs (but if there's only one when not in wizard mode)
    # but in the installer where all windows run in wizard mode because of design even when not in a wizard step
    $bprev = Gtk2::Label->new if !$cancel && $::Wizard_no_previous && !@left && !@right;
    if ($::isWizard) {
        # wizard mode: order is cancel/left_extras/white/right_extras/prev/next
        unshift @left, $w->{wizcancel} if !$::isInstall;
        push @right, $bprev, $bok;
    } else { 
        # normal mode: cancel/ok button follow GNOME's HIG
        unshift @left, $bprev;
        push @left, Gtk2::Label->new if $ok && $cancel; # space buttons but if there's only one button
        push @right, $bok;
    }

    gtkpack(Gtk2::VBox->new,
            Gtk2::HSeparator->new,
            gtkpack(Gtk2::HBox->new,
                    (map {
                        gtkpack(
                                create_hbox($_->[1]),
                                (map {
                                    $_->can_default($::isWizard);
                                    $_;
                                } grep { $_ } @{$_->[0]})
                               )
                    } ([ \@left, 'start' ],
                       [ \@right,  'end' ],
                      )
                    )
                   ),
           );
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
    _setup_paned(Gtk2::VPaned->new, @_);
}

sub create_hpaned {
    _setup_paned(Gtk2::HPaned->new, @_);
}

sub gtkcreate_frame {
    my ($label) = @_;
    gtkset_border_width(Gtk2::Frame->new($label), 5);
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
    return Gtk2::Image->new_from_file(_find_imgfile(@_) || internal_error("can't find $_[0]"));
}

# use it if you want to draw an image onto a drawingarea
sub gtkcreate_pixbuf {
    return Gtk2::Gdk::Pixbuf->new_from_file(_find_imgfile(@_) || internal_error("can't find $_[0]"));
}

sub gtktext_append { gtktext_insert(@_, append => 1) }

sub may_set_icon {
    my ($w, $name) = @_;
    if (my $f = $name && _find_imgfile($name)) {
	$w->set_icon(gtkcreate_pixbuf($f));
    }
}

# choose one of the two styles:
# - gtktext_insert($textview, "My text..");
# - gtktext_insert($textview, [ [ 'first text',  { 'foreground' => 'blue', 'background' => 'green', ... } ],
#			        [ 'second text' ],
#		                [ 'third', { 'font' => 'Serif 15', ... } ],
#                               ... ]);
sub gtktext_insert {
    my ($textview, $t, %opts) = @_;
    my $buffer = $textview->get_buffer;
    if (ref($t) eq 'ARRAY') {
        $opts{append} or $buffer->set_text('');
        foreach my $token (@$t) {
            my $iter1 = $buffer->get_end_iter;
            if ($token->[0] =~ /^Gtk2::Gdk::Pixbuf/) {
                $buffer->insert_pixbuf($iter1, $token->[0]);
                next;
            }
            if ($token->[1]) {
                $buffer->insert_with_tags($iter1, $token->[0], $buffer->create_tag(undef, %{$token->[1]}));
            } else {
                $buffer->insert($iter1, $token->[0]);
            }
        }
    } else {
        $buffer->set_text($t);
    }
    #- the following line is needed to move the cursor to the beginning, so that if the
    #- textview has a scrollbar, it won't scroll to the bottom when focusing (#3633)
    $buffer->place_cursor($buffer->get_start_iter);
    $textview->set_wrap_mode($opts{wrap_mode} || 'word');
    $textview->set_editable($opts{editable} || 0);
    $textview->set_cursor_visible($opts{visible} || 0);
    $textview;
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
	$fontinfo{$_} = Gtk2::Pango->pixels($metrics->$func);
    }
    %fontinfo;
}

sub gtkmodify_font {
    my ($w, $arg) = @_;
    $w->modify_font(ref($arg) ? $arg : Gtk2::Pango::FontDescription->from_string($arg));
    $w;
}

sub gtkset_property {
    my ($w, $property, $value) = @_;
    $w->set_property($property, $value);
    $w;
}

sub set_back_pixbuf {
    my ($widget, $pixbuf) = @_;
    my $window = $widget->window;
    my ($width, $height) = ($pixbuf->get_width, $pixbuf->get_height);
    my $pixmap = Gtk2::Gdk::Pixmap->new($window, $width, $height, $window->get_depth);
    $pixbuf->render_to_drawable($pixmap, $widget->style->fg_gc('normal'), 0, 0, 0, 0, $width, $height, 'none', 0, 0);
    $window->set_back_pixmap($pixmap, 0);
}

sub set_back_pixmap {
    my ($w) = @_;
    return if !$w->realized;
    my $window = $w->window;
    my $pixmap = $w->{back_pixmap} ||= Gtk2::Gdk::Pixmap->new($window, 1, 2, $window->get_depth);

    my $style = $w->get_style;
    $pixmap->draw_points($style->bg_gc('normal'), 0, 0);
    $pixmap->draw_points($style->base_gc('normal'), 0, 1);
    $window->set_back_pixmap($pixmap);
}

sub fill_tiled_coords {
    my ($widget, $pixbuf, $x_back, $y_back, $width, $height) = @_;
    my ($x2, $y2) = (0, 0);
    while (1) {
	$x2 = 0;
	while (1) {
	    $pixbuf->render_to_drawable($widget->window, $widget->style->fg_gc('normal'),
					0, 0, $x2, $y2, $x_back, $y_back, 'none', 0, 0);
	    $x2 += $x_back;
	    $x2 >= $width and last;
	}
	$y2 += $y_back;
	$y2 >= $height and last;
    }
}

sub fill_tiled {
    my ($widget, $pixbuf) = @_;
    my ($window_width, $window_height) = $widget->window->get_size;
    fill_tiled_coords($widget, $pixbuf, $pixbuf->get_width, $pixbuf->get_height, $window_width, $window_height);
}

sub add2notebook {
    my ($n, $title, $book) = @_;
    $n->append_page($book, gtkshow(Gtk2::Label->new($title)));
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

sub string_height {
    my ($widget, $text) = @_;
    my (undef, $height) = string_size($widget, $text);
    $height;
}

sub get_text_coord {
    my ($text, $widget4style, $max_width, $currentx, $currenty, $o_wrap_char) = @_;
    my $wrap_char = $o_wrap_char || ' ';
    my @lines;
    my $current_text;
    my @t = split($wrap_char, $text);
    my @t2;
    if ($::isInstall && $::o->{locale}{lang} =~ /ja|zh/) {
	@t = map { $_ . $wrap_char } @t;
	$wrap_char = '';
	foreach (@t) {
	    my @c = split('');
	    my $i = 0;
	    my $el = '';
	    while (1) {
		$i >= @c and last;
		$el .= $c[$i];
		if (ord($c[$i]) >= 128) { $el .= $c[$i+1]; $i++; push @t2, $el; $el = '' }
		$i++;
	    }
	    $el ne '' and push @t2, $el;
	}
    } else {
	@t2 = @t;
    }
    my $add_line = sub {
        my ($w, $h) = string_size($widget4style, $current_text);
        push @lines, { text => $current_text, width => $w, height => $h + 1, 'x' => $currentx, 'y' => $currenty };
    };
    my $width;
    foreach my $word (@t2) {
	my $w = string_width($widget4style, $word . $wrap_char);
	if ($currentx + $width + $w > $max_width) {
            $add_line->();
            $current_text = $word;
	    $width = $w;
            $currentx = 0;
            $currenty += $lines[-1]{height};
	} else {
            $current_text .= ($current_text ne '' ? $wrap_char : '') . $word;
            $width += $w;
        }
    }
    #- if wrap_char was at the end, don't forget it, for cases when bold/nonbold text follows
    $text =~ /$wrap_char$/ and $current_text .= $wrap_char;
    $add_line->();

    return @lines;
}

sub wrap_paragraph {
    my ($text, $widget4style, $border, $max_width) = @_;

    $max_width -= 2*$border;
    my @lines;
    my $ydec;

    foreach my $paragraph (@$text) {
        my @paragraph_lines;
        my $center;
        if (ref($paragraph) eq 'ARRAY') {
            my ($text, %options) = @$paragraph;
            $center = $options{center};
            $paragraph = $text;
        }
        if ($paragraph ne '') {
            my @elements;
            while ($paragraph =~ m|(.*?)<b>(.*?)</b>(.*)|) {
                $1 ne '' and push @elements, [ $1, bold => 0 ];
                push @elements, [ $2, bold => 1 ];
                $paragraph = $3;
            }
            $paragraph ne '' and push @elements, [ $paragraph, bold => 0 ];

            my $currentx;
            foreach (@elements) {
                my ($text, %options) = @$_;
                #- hack :( if ' ' is at the beginning, don't forget it, substitute
                #- with an unbreakable space because gtk allocates too much space otherwise
                $text =~ /^ (.*)/ and $text = " $1";
                my @newlines = get_text_coord($text, $widget4style, $max_width, $currentx, $ydec);
                $currentx = $newlines[-1]{'x'} + $newlines[-1]{width};
                $ydec = $newlines[-1]{'y'};
                $options{bold} and $currentx++;
                $_->{options} = \%options foreach @newlines;
                push @paragraph_lines, @newlines;
            }
            $ydec = $paragraph_lines[-1]{'y'} + $paragraph_lines[-1]{height};
        }
        if ($center) {
            my %widths;
            $widths{$_->{'y'}} ||= $_->{x} + $_->{width} foreach reverse @paragraph_lines;
            $_->{x} += ($max_width - $widths{$_->{'y'}})/2 foreach @paragraph_lines;
        }
        $_->{x} += $border foreach @paragraph_lines;
        push @lines, @paragraph_lines;
    }

    return @lines;
}

sub gtkcolor {
    my ($r, $g, $b) = @_;
    my $color = Gtk2::Gdk::Color->new($r, $g, $b);
    gtkroot()->get_colormap->rgb_find_color($color);
    $color;
}

sub gtkset_background {
    my ($r, $g, $b) = @_;
    my $root = gtkroot();
    my $gc = Gtk2::Gdk::GC->new($root);
    my $color = gtkcolor($r, $g, $b);
    $gc->set_rgb_fg_color($color);
    $root->set_background($color);
    my ($w, $h) = $root->get_size;
    $root->draw_rectangle($gc, 1, 0, 0, $w, $h);
}

sub add_icon_path { push @icon_paths, @_ }
sub icon_paths() {
   (@icon_paths, (exists $ENV{SHARE_PATH} ? ($ENV{SHARE_PATH}, "$ENV{SHARE_PATH}/icons", "$ENV{SHARE_PATH}/libDrakX/pixmaps") : ()),
    "/usr/lib/libDrakX/icons", "pixmaps", 'standalone/icons', '/usr/share/rpmdrake/icons');
}  
add_icon_path(@icon_paths,
	      exists $ENV{SHARE_PATH} ? "$ENV{SHARE_PATH}/libDrakX/pixmaps" : (),
	      '/usr/lib/libDrakX/icons', 'standalone/icons');



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

    $o->{isWizard} ||= $::isWizard;
    $o->{isEmbedded} ||= $::isEmbedded;
    $o->{wm_icon} ||= $wm_icon || $::Wizard_pix_up || "wiz_default_up.png";

    $o->{pop_it} ||= $pop_it || !$o->{isWizard} && !$o->{isEmbedded} || $::WizardTable && do {
	#- don't take into account the DrawingArea
	any { !$_->isa('Gtk2::DrawingArea') && $_->visible } $::WizardTable->get_children;
    };

    if ($o->{pop_it}) {
	$o->{rwindow} = _create_window($title);
	may_set_icon($o->{rwindow}, $o->{wm_icon});
	$o->{rwindow}->set_position('center-on-parent');

	if ($::isInstall) {
	    gtkadd($o->{rwindow}, 
		   gtkadd(gtkset_shadow_type(Gtk2::Frame->new(undef), 'out'),
			  $o->{window} = gtkset_border_width(gtkset_shadow_type(Gtk2::Frame->new(undef), 'none'), 3)
			 ));
	} else {
	    $o->{window} = $o->{rwindow};
	}
	$o->{rwindow}->set_position('center_always') if $force_center || $o->{force_center};
	$o->{rwindow}->set_modal(1) if $grab || $o->{grab} || $o->{modal};
	$o->{rwindow}->set_transient_for($o->{transient}) if $o->{transient} && $o->{transient} =~ /Gtk2::Window/;

    } else {
	$o->{rwindow} = $o->{window} = Gtk2::VBox->new(0,0);
	$o->{window}->set_border_width($::Wizard_splash ? 0 : 10);
	set_main_window_size($o);

	$::WizardTable ||= Gtk2::VBox->new(0, 0);

	if (!$::Plug && $o->{isEmbedded}) {
	    $::Plug = $::WizardWindow = gtkshow(Gtk2::Plug->new($::XID));
	    may_set_icon($::Plug, $o->{wm_icon});
	    flush();
	    gtkadd($::Plug, $::WizardTable);
	} elsif (!$::WizardWindow) {
	    $::WizardWindow = _create_window($title);
	    gtkadd($::WizardWindow, gtkadd(gtkset_shadow_type(Gtk2::Frame->new, 'out'), $::WizardTable));

	    if ($::isInstall) {
		$::WizardWindow->signal_connect(key_press_event => sub {
		    my (undef, $event) = @_;
		    my $d = ${{ $Gtk2::Gdk::Keysyms{F2} => 'screenshot' }}{$event->keyval};
		    if ($d eq 'screenshot') {
			common::take_screenshot();
		    } elsif (chr($event->keyval) eq 'e' && member('mod1-mask', @{$event->state})) {  #- alt-e
			log::l("Switching to " . ($::expert ? "beginner" : "expert"));
			$::expert = !$::expert;
		    }
		    0;
		});
	    } elsif (!$o->{isEmbedded}) {
		$::WizardWindow->set_position('center_always') if !$::isStandalone;
		gtkpack__($::WizardTable, Gtk2::Banner->new($::Wizard_pix_up || "wiz_default_up.png", $::Wizard_title));
		may_set_icon($::WizardWindow, $o->{wm_icon});
	    }
	    $::WizardWindow->show;
	}
	$::WizardWindow->set_title($title || '');
	gtkpack($::WizardTable, $o->{window});
    }
    $o->{rwindow}->signal_connect(destroy => sub { $o->{destroyed} = 1 });

    $o;
}
sub set_main_window_size {
    my ($o) = @_;
    my ($width, $height) = $::isInstall ? ($::real_windowwidth, $::real_windowheight) : $o->{isWizard} ? (540, 360) : (600, 400);
    $o->{window}->set_size_request($width, $height);
}

sub main {
    my ($o, $o_completed, $o_canceled) = @_;
    gtkset_mousecursor_normal();
    my $timeout = Glib::Timeout->add(1000, sub { gtkset_mousecursor_normal(); 1 });
    my $_b = MDK::Common::Func::before_leaving { $o->destroy; Glib::Source->remove($timeout) };
    $o->show;

    do {
	Gtk2->main;
    } while (!$o->{destroyed} && ($o->{retval} ? $o_completed && !$o_completed->() : $o_canceled && !$o_canceled->()));
    $o->destroy;
    $o->{retval}
}
sub show($) {
    my ($o) = @_;
    $o->{window}->show;
    $o->{rwindow}->show;
}
sub destroy($) {
    my ($o) = @_;
    $o->{rwindow}->destroy if !$o->{destroyed};
    gtkset_mousecursor_wait();
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
    if ($Gtk2::VERSION < 1.040) {
        $o->{rwindow}->signal_emit('size_allocate', Gtk2::Allocation->new(-1, -1, -1, -1));
    } else {
        $o->{rwindow}->signal_emit('size_allocate', Gtk2::Gdk::Rectangle->new(-1, -1, -1, -1));
    }
}
sub exit {
    gtkset_mousecursor_normal(); #- for restoring a normal in any case
    flush();
    c::_exit($_[1]) #- workaround 
}

#- in case "exit" above was not called by the program
END { &exit() }

sub _create_window {
    my ($title) = @_;
    my $w = Gtk2::Window->new('toplevel');

    $w->set_name("Title");
    $w->set_title($title || '');

    if ($force_focus) {
	(my $previous_current_window, $ugtk2::current_window) = ($ugtk2::current_window, $w);
	$w->signal_connect(expose_event => \&_XSetInputFocus);
	$w->signal_connect(destroy => sub { $ugtk2::current_window = $previous_current_window });
    }
    $w->signal_connect(delete_event => sub { 
	if ($::isWizard) {
	    $w->destroy; 
	    die 'wizcancel';
	} else { 
	    Gtk2->main_quit;
	} 
    });

    if ($::isInstall && $::o->{mouse}{unsafe}) {
	$w->add_events('pointer-motion-mask');
	my $signal;  #- don't make this line part of next one, signal_disconnect won't be able to access $signal value
	$signal = $w->signal_connect(motion_notify_event => sub {
	    delete $::o->{mouse}{unsafe};
	    log::l("unsetting unsafe mouse");
	    $w->signal_handler_disconnect($signal);
	});
    }

    if ($force_center_at_pos) {
	my ($wi, $he);

	$w->signal_connect(size_allocate => sub {
	    my (undef, $event) = @_;
	    my @w_size = $event->values;
	    return if $w_size[2] == $wi && $w_size[3] == $he; #BUG
	    (undef, undef, $wi, $he) = @w_size;
	    
	    my ($X, $Y, $Wi, $He) = @$force_center_at_pos;
            $w->set_uposition(max(0, $X + ($Wi - $wi) / 2), max(0, $Y + ($He - $he) / 2));
	});
    }

    $w;
}

sub _XSetInputFocus {
    my ($w) = @_;
    if ($ugtk2::current_window == $w) {
	$w->window->XSetInputFocus;
    } else {
	log::l("not XSetInputFocus since already done and not on top");
    }
    0;
}


# -=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---=-=---
#                 ask
#
# Full UI managed functions that will return to you the value that the
# user chose.

sub ask_warn       { my $w = ugtk2->new(shift @_, grab => 1); $w->_ask_warn(@_); main($w) }
sub ask_yesorno    { my $w = ugtk2->new(shift @_, grab => 1); $w->_ask_okcancel(@_, N("Yes"), N("No")); main($w) }
sub ask_okcancel   { my $w = ugtk2->new(shift @_, grab => 1); $w->_ask_okcancel(@_, N("Is this correct?"), N("Ok"), N("Cancel")); main($w) }
sub ask_from_entry { my $w = ugtk2->new(shift @_, grab => 1); $w->_ask_from_entry(@_); main($w) }
sub ask_dir        { my $w = ugtk2->new(shift @_, grab => 1); $w->_ask_dir(@_); main($w) }

sub _ask_from_entry($$@) {
    my ($o, @msgs) = @_;
    my $entry = Gtk2::Entry->new;
    my $f = sub { $o->{retval} = $entry->get_text; Gtk2->main_quit };
    $o->{ok_clicked} = $f;
    $o->{cancel_clicked} = sub { undef $o->{retval}; Gtk2->main_quit };

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
		 gtksignal_connect(my $w = Gtk2::Button->new(N("Ok")), "clicked" => sub { Gtk2->main_quit }),
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


sub _ask_file {
    my ($o, $title, $path) = @_;
    my $f = Gtk2::FileSelection->new($title);
    if ($o->{rwindow}->isa('Gtk2::Window')) {
	my ($modality, $position) = ($o->{rwindow}->get_modal, $o->{rwindow}->get('window-position'));
	$f->set_modal($modality);
	$f->set_position($position);
    }
    my $bg = $o->{window};
    $o->{rwindow} = $o->{window} = $f;
    $f->set_filename($path) if $path;
    $f->signal_connect(destroy => sub { eval { $bg->destroy } });
    $f->ok_button->signal_connect(clicked => sub { $o->{retval} = $f->get_filename; Gtk2->main_quit });
    $f->cancel_button->signal_connect(clicked => sub { Gtk2->main_quit });
    $f->grab_focus;
    $f;
}

sub _ask_dir {
    my ($o) = @_;
    my $f = &_ask_file;
    $f->file_list->get_parent->hide;
    $f->selection_entry->get_parent->hide;
    $f->ok_button->signal_connect(clicked => sub {
				      my ($model, $iter) = $f->dir_list->get_selection->get_selected;
				      $o->{retval} .= '/'.$model->get($iter, 0) if $model;
				  });
}

sub ask_browse_tree_info {
    my ($common) = @_;

    my $w = ugtk2->new($common->{title});

    my $tree_model = Gtk2::TreeStore->new("Glib::String", "Gtk2::Gdk::Pixbuf", "Glib::String");
    my $tree = Gtk2::TreeView->new_with_model($tree_model);
    $tree->get_selection->set_mode('browse');
    $tree->append_column(my $textcolumn = Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, 'text' => 0));
    $tree->append_column(my $pixcolumn  = Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererPixbuf->new, 'pixbuf' => 1));
    $tree->append_column(Gtk2::TreeViewColumn->new_with_attributes(undef, Gtk2::CellRendererText->new, 'text' => 2));
    $tree->set_headers_visible(0);
    $tree->set_rules_hint(1);
    $textcolumn->set_min_width(200);
    $textcolumn->set_max_width(200);

    gtkadd($w->{window}, 
	   gtkpack_(Gtk2::VBox->new(0,5),
		    0, $common->{message},
		    1, gtkpack(Gtk2::HBox->new(0,0),
			       create_scrolled_window($tree),
			       gtkadd(Gtk2::Frame->new(N("Info")),
				      create_scrolled_window(my $info = Gtk2::TextView->new),
				     )),
		    0, my $box1 = Gtk2::HBox->new(0,15),
		    0, my $box2 = Gtk2::HBox->new(0,10),
		   ));
    #gtkpack__($box2, my $toolbar = Gtk2::Toolbar->new('horizontal', 'icons'));
    gtkpack__($box2, my $toolbar = Gtk2::Toolbar->new);

    my @l = ([ $common->{ok}, 1 ], if_($common->{cancel}, [ $common->{cancel}, 0 ]));
    @l = reverse @l if !$::isInstall;
    my @buttons = map {
	my ($t, $val) = @$_;
	$box2->pack_end(my $w = gtksignal_connect(Gtk2::Button->new($t), clicked => sub {
						      $w->{retval} = $val;
						      Gtk2->main_quit;
						  }), 0, 1, 20);
	$w;
    } @l;
    @buttons = reverse @buttons if !$::isInstall;    

    gtkpack__($box2, gtksignal_connect(Gtk2::Button->new(N("Help")), clicked => sub {
					   ask_warn(N("Help"), $common->{interactive_help}->())
				       })) if $common->{interactive_help};

    if ($common->{auto_deps}) {
	gtkpack__($box1, gtksignal_connect(gtkset_active(Gtk2::CheckButton->new($common->{auto_deps}), $common->{state}{auto_deps}),
					clicked => sub { invbool \$common->{state}{auto_deps} }));
    }
    $box1->pack_end(my $status = Gtk2::Label->new, 0, 1, 20);

    $w->{window}->set_size_request(map { $_ - 2 * $border - 4 } $::windowwidth, $::windowheight) if !$::isInstall;
    $buttons[0]->grab_focus;
    $w->{rwindow}->show_all;

    #- TODO: $tree->queue_draw is a workaround to a bug in gtk-2.2.1; submit it in their bugzilla
    my @toolbar = (ftout  =>  [ N("Expand Tree"), sub { $tree->expand_all; $tree->queue_draw } ],
		   ftin   =>  [ N("Collapse Tree"), sub { $tree->collapse_all } ],
		   reload =>  [ N("Toggle between flat and group sorted"), sub { invbool(\$common->{state}{flat}); $common->{rebuild_tree}->() } ]);
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
	$toolbar->append_item(undef, $toolbar{$_}[0], undef, gtkcreate_img("$_.png"), $toolbar{$_}[1]);
    }

    $pixcolumn->{is_pix} = 1;
    $common->{widgets} = { w => $w, tree => $tree, tree_model => $tree_model, textcolumn => $textcolumn, pixcolumn => $pixcolumn,
                           info => $info, status => $status };
    ask_browse_tree_info_given_widgets($common);
}

sub ask_browse_tree_info_given_widgets {
    my ($common) = @_;
    my $w = $common->{widgets};

    my ($curr, $prev_label, $idle, $mouse_toggle_pending);
    my (%wtree, %ptree, %pix, %node_state, %state_stats);
    my $update_size = sub {
	my $new_label = $common->{get_status}();
	$prev_label ne $new_label and $w->{status}->set($prev_label = $new_label);
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
    my $children = sub { map { my $v = $w->{tree_model}->get($_, 0); $v } gtktreeview_children($w->{tree_model}, $_[0]) };
    my $toggle = sub {
	if (ref($curr) && !$_[0]) {
	    $w->{tree}->toggle_expansion($w->{tree_model}->get_path($curr));
	} else {
	    if (ref $curr) {
		my @_a = $children->($curr);
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
	#- two changed events, the first being on a different row :/ (is it a bug in gtk2?) - that
	#- happens in rpmdrake when doing a "search" and directly trying to select a found package
	if ($mouse_toggle_pending eq $model->get($iter, 0)) {
	    $toggle->(1);
            $mouse_toggle_pending = 0;
	}
	0;
    });
    $w->{tree}->signal_connect(button_press_event => sub {  #- not too good, but CellRendererPixbuf doesn't have the needed signals :(
	my ($path, $column) = $w->{tree}->get_path_at_pos($_[1]->x, $_[1]->y);
	if ($path && $column) {
	    $column->{is_pix} and $mouse_toggle_pending = $w->{tree_model}->get($w->{tree_model}->get_iter($path), 0);
	}
        0;
    });
    $common->{rebuild_tree}->();
    &$update_size;
    $common->{initial_selection} and $common->{toggle_nodes}($set_leaf_state, @{$common->{initial_selection}});
    my $_b = before_leaving { $clear_all_caches->() };
    $w->{w}->main;
}

sub gtk_set_treelist {
    my ($treelist, $l) = @_;

    my $list = $treelist->get_model;
    $list->clear;
    $list->append_set([ 0 => $_ ]) foreach @$l;
}


sub gtk_TextView_get_log {
    my ($log_w, $log_scroll, $command, $filter_output, $when_command_is_over) = @_;

    my $pid = open(my $F, "$command |") or return;
    fcntl($F, c::F_SETFL(), c::O_NONBLOCK()) or die "can't fcntl F_SETFL: $!";

    my $gtk_buffer = $log_w->get_buffer;
    $log_w->signal_connect(destroy => sub { 
	kill 9, $pid if $pid; #- we do not continue in background
	$pid = $gtk_buffer = ''; #- ensure $gtk_buffer is valid when its value is non-null
    });

    my ($prev_scroll, $want_scroll_down) = (0, 1);
    Glib::Timeout->add(100, sub {
        if ($gtk_buffer) {
	    my $end = $gtk_buffer->get_end_iter;
	    while (defined (my $s = <$F>)) {
		$gtk_buffer->insert($end, $filter_output->($s));
	    }
	    my $new_scroll = $log_scroll->get_vadjustment->get_value;
	    $want_scroll_down &&= $new_scroll >= $prev_scroll;
	    $prev_scroll = $new_scroll;
	    $log_w->scroll_to_iter($end, 0, 0, 0, 0) if $want_scroll_down;
	}
	if (waitpid($pid, c::WNOHANG()) > 0) {
	    #- we do not call $when_command_is_over if $gtk_buffer doesn't exist anymore
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

    my $log_w = gtkset_editable(Gtk2::TextView->new, 0);
    my $log_scroll = create_scrolled_window($log_w);  #- $log_scroll is a frame, not a ScrolledWindow, so giving $log_scroll->child
    my $pid = gtk_TextView_get_log($log_w, $log_scroll->child, $command, $filter_output, $when_command_is_over) or return;
    $log_scroll, $pid;
}

# misc helpers:

package Gtk2::TreeStore;
sub append_set {
    my ($model, $parent, @values) = @_;
    # compatibility:
    @values = @{$values[0]} if @values == 1 && ref($values[0]) eq 'ARRAY';
    my $iter = $model->append($parent);
    $model->set($iter, @values);
    return $iter;
}


package Gtk2::ListStore;
# Append a new row, set the values, return the TreeIter
sub append_set {
    my ($model, @values) = @_;
    # compatibility:
    @values = @{$values[0]} if @values == 1 && ref($values[0]) eq 'ARRAY';
    my $iter = $model->append;
    $model->set($iter, @values);
    return $iter;
}


package Gtk2::TreeModel;
# gets the string representation of a TreeIter
sub get_path_str {
    my ($self, $iter) = @_;
    my $path = $self->get_path($iter);
    $path or return;
    $path->to_string;
}

sub iter_each_children {
    my ($model, $iter, $f) = @_;
    for (my $child = $model->iter_children($iter); $child; $child = $model->iter_next($child)) {
	$f->($child);
    }
}

package Gtk2::TreeView;
# likewise gtk-1.2 function
sub toggle_expansion {
    my ($self, $path, $b_open_all) = @_;
    if ($self->row_expanded($path)) {
	$self->collapse_row($path);
    } else {
	$self->expand_row($path, $b_open_all || 0);
    }
}


# With GTK+, for more GUIes coherency, GtkOptionMenu is recommended instead of a
# combo if the user is selecting from a fixed set of options.
#
# That is, non-editable combo boxes are not encouraged. GtkOptionMenu is much
# easier to use than GtkCombo as well. Use GtkCombo only when you need the
# editable text entry.
#
# GtkOptionMenu is a much better-implemented widget and also the right UI for
# noneditable sets of choices.)
#
# GtkCombo is deprecated in 2.4.x because it still uses deprecated
# GtkList. GtkOption menu is deprecated in order to have an unified widget.
#
# GtkComBox widget replaces GtkOption menu whereas GtkComBoxEntry replaces GtkCombo.
#
#
# This layer try to make OptionMenu and ComboBox look being api
# compatible with Combo since its API is quite nice.

package Gtk2::OptionMenu;
use common;

# try to get combox <==> option menu mapping
sub set_popdown_strings {
    my ($w, @strs) = @_;
    my $menu = Gtk2::Menu->new;
    # keep string list around for ->set_text compatibilty helper
    $w->{strings} = \@strs;
    #$w->set_menu((ugtk2::create_factory_menu($window, [ "File", (undef) x 3, '<Branch>' ], map { [ "File/" . $_, (undef) x 3, '<Item>' ] } @strs))[0]);
    $menu->append(ugtk2::gtkshow(Gtk2::MenuItem->new_with_label($_))) foreach @strs;
    $w->set_menu($menu);
    $w
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
    $w->{strings}[$w->get_history];
}

sub set_text {
    my ($w, $val) = @_;
    each_index {
        if ($_ eq $val) {
            $w->set_history($::i);
            return;
        }
    } @{$w->{strings}};
}




package Gtk2::ComboBox;
use common;

# try to get combox <==> option menu mapping
sub set_popdown_strings {
    my ($w, @strs) = @_;
    # keep string list around for ->set_text compatibilty helper
    $w->{strings} = \@strs;
    $w->append_text($_) foreach @strs;
    $w
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
    $w->{strings}[$w->get_active];
}

sub set_text {
    my ($w, $val) = @_;
    eval { 
	my $val_index = find_index { $_ eq $val } @{$w->{strings}};
	$w->set_active($val_index);
    };
}


package Gtk2::Label;
sub set {
    my ($label) = shift;
    $label->set_label(@_);
}


package Gtk2::WrappedLabel;
sub new {
    my ($_type, $o_text, $o_align) = @_;
    ugtk2::gtkset_alignment(ugtk2::gtkset_line_wrap(Gtk2::Label->new($o_text || ''), 1), $o_align || 0, 0.5);
}


package Gtk2::Entry;
sub new_with_text {
    my ($_class, @text) = @_;
    my $entry = Gtk2::Entry->new;
    @text and $entry->set_text(@text);
    return $entry;
}


package Gtk2::Banner;

use ugtk2 qw(:helpers :wrappers);

sub set_pixmap {
    my ($darea) = @_;
    return if !$darea->realized;
    ugtk2::set_back_pixmap($darea);
    $darea->{layout} = $darea->create_pango_layout($darea->{text});
}


sub new {
    my ($_class, $icon, $text, $o_options) = @_;

    my $darea = Gtk2::DrawingArea->new;
    $darea->set_size_request(-1, 75);
    $darea->modify_font(Gtk2::Pango::FontDescription->from_string(common::N("_banner font:\nSans 14")));
    $darea->{icon} = ugtk2::gtkcreate_pixbuf($icon);
    $darea->{text} = $text;

    $darea->signal_connect(realize => \&set_pixmap);
    $darea->signal_connect("style-set" => \&set_pixmap);
    $darea->signal_connect(expose_event => sub {
                               my $style = $darea->get_style;
                               my $height = $darea->{icon}->get_height;
                               $darea->{icon}->render_to_drawable($darea->window, $style->bg_gc('normal'),
                                                                  0, 0, 10, 10, -1, -1, 'none', 0, 0);
                               $darea->window->draw_layout($style->text_gc('normal'), $height + 20, $o_options->{txt_ypos} || 25,
                                                           $darea->{layout});
                               1;
                           });
                               
    return $darea;
}

1;

