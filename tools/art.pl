#!/usr/bin/perl
# draws icon.png (512) and banner.png (1200x500) with no image library: a plain PNG writer on top of core zlib
use strict;
use warnings;
use Compress::Zlib qw(compress);
use Compress::Raw::Zlib qw(crc32);

chunk_out();
exit 0;

sub chunk {
    my ($type, $data) = @_;
    return pack("N", length $data) . $type . $data . pack("N", crc32($type . $data));
}

sub write_png {
    my ($path, $w, $h, $rows) = @_;
    open my $fh, '>:raw', $path or die "cannot write $path: $!";
    print $fh "\x89PNG\r\n\x1a\n";
    print $fh chunk("IHDR", pack("NNCCCCC", $w, $h, 8, 2, 0, 0, 0));
    my $raw = join('', map { "\x00" . $_ } @$rows);
    print $fh chunk("IDAT", compress($raw));
    print $fh chunk("IEND", "");
    close $fh;
}

sub clamp { my $v = shift; return $v < 0 ? 0 : $v > 1 ? 1 : $v }

# coverage of a point inside a triangle, from its distance to the nearest edge
sub triangle {
    my ($px, $py, $ax, $ay, $bx, $by, $cx, $cy) = @_;
    my @edges = ([$ax, $ay, $bx, $by], [$bx, $by, $cx, $cy], [$cx, $cy, $ax, $ay]);
    my (@d, $inside);
    for my $e (@edges) {
        my ($x1, $y1, $x2, $y2) = @$e;
        my $len = sqrt(($x2 - $x1)**2 + ($y2 - $y1)**2);
        next if $len == 0;
        push @d, (($x2 - $x1) * ($py - $y1) - ($y2 - $y1) * ($px - $x1)) / $len;
    }
    return 0 unless @d == 3;
    # inside means the point is on the same side of all three edges, whichever way they wind
    my $positive = grep { $_ > 0 } @d;
    return 0 unless $positive == 0 || $positive == 3;
    my $min = 1e9;
    for (@d) { my $a = abs $_; $min = $a if $a < $min }
    return clamp($min / 1.6);
}

sub blink { my ($dst, $src, $cov) = @_; return $dst * (1 - $cov) + $src * $cov }

sub icon {
    my $w = 512;
    my $h = 512;
    my @rows;
    for my $y (0 .. $h - 1) {
        my $row = '';
        for my $x (0 .. $w - 1) {
            my $t = $y / $h;
            my ($r, $g, $b) = (14 + 6 * $t, 12 + 5 * $t, 16 + 8 * $t);
            my $d = sqrt(($x - 255.5)**2 + ($y - 255.5)**2);
            my $disc = clamp(178 - $d);
            if ($disc > 0) {
                $r = blink($r, 252, $disc);
                $g = blink($g, 32, $disc);
                $b = blink($b, 48, $disc);
            }
            my $play = triangle($x, $y, 206, 160, 206, 352, 366, 256);
            if ($play > 0) {
                $r = blink($r, 255, $play);
                $g = blink($g, 255, $play);
                $b = blink($b, 255, $play);
            }
            $row .= pack("CCC", int($r), int($g), int($b));
        }
        push @rows, $row;
    }
    write_png("icon.png", $w, $h, \@rows);
    print "icon.png 512x512\n";
}

sub banner {
    my $w = 1200;
    my $h = 500;
    my @rows;
    for my $y (0 .. $h - 1) {
        my $row = '';
        for my $x (0 .. $w - 1) {
            my $t = $y / $h;
            my $u = $x / $w;
            my ($r, $g, $b) = (26 - 14 * $t - 6 * $u, 6 + 2 * $t, 9 + 4 * $t);
            # red glow behind the mark
            my $d = sqrt(($x - 380)**2 + ($y - 250)**2);
            my $glow = $d < 340 ? (1 - $d / 340)**2 : 0;
            $r = blink($r, 190, $glow * 0.55);
            $g = blink($g, 10, $glow * 0.55);
            $b = blink($b, 18, $glow * 0.55);
            # the same red disc and play mark as the icon, small
            my $disc = clamp(92 - sqrt(($x - 380)**2 + ($y - 250)**2));
            if ($disc > 0) {
                $r = blink($r, 252, $disc);
                $g = blink($g, 32, $disc);
                $b = blink($b, 48, $disc);
            }
            my $play = triangle($x, $y, 354, 200, 354, 300, 436, 250);
            if ($play > 0) {
                $r = blink($r, 255, $play);
                $g = blink($g, 255, $play);
                $b = blink($b, 255, $play);
            }
            # a soft vignette so the right side reads as empty
            my $vig = clamp((($x - 700) / $w) * 1.2);
            $r *= 1 - $vig * 0.45;
            $g *= 1 - $vig * 0.45;
            $b *= 1 - $vig * 0.45;
            $row .= pack("CCC", int($r), int($g), int($b));
        }
        push @rows, $row;
    }
    write_png("banner.png", $w, $h, \@rows);
    print "banner.png 1200x500\n";
}

sub chunk_out {
    icon();
    banner();
}
