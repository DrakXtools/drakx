#!/usr/bin/perl -pi

# state machine:
if (/\s*control\./) {
    ($min, $max) = (0, 0);
} elsif (/\s*name '/) {
    # skip masks and blacklist sb live and the like:
    $ignore = /\s*name '.*(3D Control|AC97 Playback Volume|Audigy Analog\/Digital Output Jack|External Amplifier Power Down|Exchange DAC|IEC958 input monitor|IEC958 Capture Monitor|IEC958 Playback Switch|mask|Mic Boost \(\+20dB\)|Mic Playback Switch|Output Jack|Surround down mix)/i;
} elsif (!$ignore) {
    if (/s*comment.range '(\d+) - (\d+)'/) {
        ($min, $max) = ($1, $2);
    } elsif (/s*value/) {
        # enable switches:
        s/(value\w*\S*)\s* false/\1 true/;
        # set volume to 80%:
        my $val = int($max*0.8);
        s/(value\w*\S*)\s* \d+/\1 $val/;
    }
}
