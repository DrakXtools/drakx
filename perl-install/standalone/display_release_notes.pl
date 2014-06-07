#!/usr/bin/perl

# DrakBoot
# Copyright (C) 2009 Mandriva
# Thierry Vignaud
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
use lib qw(/usr/lib/libDrakX);
use interactive;
use any;
use MDK::Common;
use lang;

my $in = 'interactive'->vnew('su');
# so that we popup above drakx:
any::set_wm_hints_if_needed($in);

# Fake enough $o for retrieving the proper translation:
$::o = $in;
$::o->{locale}{lang} = $ENV{LC_ALL};
# must have a value so that we look at locale_special/ :
$::prefix = '/';
lang::set($::o->{locale});

# not very safe but we run in a restricted environment anyway:
my $release_notes = cat_utf8('/tmp/release_notes.html');
any::display_release_notes($in, $release_notes);
