#!/usr/bin/perl

# DrakBoot
# $Id: display_release_notes 242795 2008-05-29 15:38:07Z tv $
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

# so that we popup above drakx:
BEGIN { $::isInstall = 1 }

use lib qw(/usr/lib/libDrakX);
use interactive;
use any;
use MDK::Common;

my $in = 'interactive'->vnew('su');
# not very safe but we run in a restricted environment anyway:
my $release_notes = cat_utf8('/tmp/release_notes.html');
any::display_release_notes($in, $release_notes);
