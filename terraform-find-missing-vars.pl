#!/usr/bin/env perl
# terraform-find-missing-vars.pl - Find missing variable definitions in a Terraform module

use strict;
use warnings;

@ARGV > 0 || die "Usage: $0 VARIABLES-TF-FILE [TF-FILE ..]\n";

my (%vars, %variables);

open( my $vfdata, shift @ARGV ) || die "Error: $!";
my @vfdata = map { chomp; /^\s*#/ ? () : $_ } <$vfdata>;
close($vfdata);

unless ( @ARGV ) {
    @ARGV = glob "*.tf"
}

for my $f ( @ARGV ) {

    open( my $fd, $f ) || die "Error: $!";
    while ( <$fd> ) {
        chomp;
        next if /^\s*#/;
        $vars{$1}++ while ( /var\.([a-zA-Z0-9_-]+)/g );
    }
    close($fd);

}

for (@vfdata) { # i'm terrible at regex apparently
    if ( /variable\s+("([a-zA-Z0-9_-]+)"|([a-zA-Z0-9_-]+))\s/ ) {
        $variables{defined $2 ? $2 : $1}++
    }
}

for my $v (sort keys %vars) {
    print "variable \"$v\" {}\n" unless exists $variables{$v};
}

for my $v (sort keys %variables) {
    print "# unused variable: $v\n" unless exists $vars{$v};
}
