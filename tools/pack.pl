#!/usr/bin/perl
# packs the module into a zip: manifest.json at the root, plus its pictures
use strict;
use warnings;
use IO::Compress::Zip qw($ZipError);

my $out = shift @ARGV or die "usage: pack.pl <out.zip>\n";
my @files = qw(manifest.json icon.png banner.png);

my $zip = IO::Compress::Zip->new($out, Name => $files[0], Minimal => 1)
    or die "cannot write $out: $ZipError\n";
for my $i (0 .. $#files) {
    $zip->newStream(Name => $files[$i]) or die "cannot add $files[$i]: $ZipError\n" if $i > 0;
    open my $fh, '<:raw', $files[$i] or die "cannot read $files[$i]: $!\n";
    local $/;
    my $data = <$fh>;
    close $fh;
    print $zip $data;
}
$zip->close or die "cannot finish $out: $ZipError\n";
printf "%s: %d files, %d bytes\n", $out, scalar @files, -s $out;
