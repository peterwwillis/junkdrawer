#!/usr/bin/env perl
use strict;
use warnings;

@ARGV > 0 || die "Usage: $0 VARIABLES-TF-FILE [TF-FILE ..]\n";

my (%vars, %variables);

open( my $vfdata, shift @ARGV ) || die "Error: $!";
my @vfdata = <$vfdata>;
close($vfdata);

unless ( @ARGV ) {
    @ARGV = glob "*.tf"
}

for my $f ( @ARGV ) {

    open( my $fd, $f ) || die "Error: $!";
    while ( <$fd> ) { 
        $vars{$1}++ while ( /var\.([a-zA-Z0-9_-]+)/g );
    }
    close($fd);

}

for (@vfdata) {
    $variables{$1}++ if ( /variable\s+"?([^\s"]+)"?/ );
}

for my $v (sort keys %vars) {
    print "variable \"$v\" {}\n" unless exists $variables{$v};
}

for my $v (sort keys %variables) {
    print "# unused variable: $v\n" unless exists $vars{$v};
}
