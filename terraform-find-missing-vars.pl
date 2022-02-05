#!/usr/bin/env perl
use strict;
use warnings;

@ARGV > 0 || die "Usage: $0 VARIABLES-TF-FILE [TF-FILE ..]\n";

my %v;

open( my $vfd, shift @ARGV ) || die "Error: $!";
my @vfd = <$vfd>;
close($vfd);

unless ( @ARGV ) {
    @ARGV = glob "*.tf"
}

for my $f ( @ARGV ) {

    open( my $fd, $f ) || die "Error: $!";
    while ( <$fd> ) { 
        while ( /var\.([a-zA-Z0-9_-]+)/g ) {
            $v{$1}++
        }
    }
    close($fd);

}

for my $v (sort keys %v) {
    unless ( grep( /variable\s+"$v"/, @vfd ) ) {
        print "variable \"$v\" {}\n"
    }
}
