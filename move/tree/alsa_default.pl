#!/usr/bin/perl

# state machine:
if (/\s*control\./) {
    ($min, $max) = (0, 0);
} elsif (/\s*name '/) {
    # skip masks
    $ignore = /\s*name '.*(3D Control|mask|Exchange DAC|Output Jack)/;
} elsif (!$ignore) {
    if (/s*comment.range '(\d+) - (\d+)'/) {
        ($min, $max) = ($1, $2);
    } elsif (/s*value/) {
        # enable switches (we should really blacklist sb live and the like):
        s/(value\w*\S*)\s* false/\1 true/;
        # set volume to 67%:
        my $val = $max*0.6;
        s/(value\w*\S*)\s* 0/\1 $val/
    }
}
