#!/usr/bin/env perl
# terraform-extract-backend.pl - extract backend configuration from terraform module
#
# Options:
#   -o FORMAT               Output format (flat, json)
#

$|=1;
use strict;
use warnings;

use JSON;
use Getopt::Std;
use Data::Dumper;

my (%vars, %variables);

my $OUTPUT_FORMAT = "flat"; # flat, json

sub print_backend {
    my ($type, $map) = @_;

    if ( $OUTPUT_FORMAT eq "flat" ) {

        my $printstr = join " ", map { "$_='$map->{$_}'" } keys %$map;
        print "type='$type' $printstr\n";

    } elsif ( $OUTPUT_FORMAT eq "json" ) {

        my $newdict = { %$map };
        $newdict->{'backend_type'} = $type;

        my $json = JSON->new->allow_nonref;
        $json->canonical(1);
        print $json->encode($newdict), "\n";

    } else {

        die "Error: invalid output format '$OUTPUT_FORMAT'";

    }
}

sub process_backend {

    my $data = shift;

    my $start_tf_block = 0;
    my $new_block = 0;
    my $backend_type = "";
    my %backend_map = ();

    for ( @$data ) { # i'm terrible at regex apparently

        if ( /^\s*terraform\s+{\s*$/ ) {
            $start_tf_block = 1;
            $new_block = 1;
            next;
        }
        if ( $start_tf_block ) {
            if ( /\s+{\s*$/ ) {
                $new_block++;
            }
            if ( /^\s*backend\s+"([^"]+)"\s+{\s*$/ ) {
                $backend_type = $1;
                next;
            }
            if ( length $backend_type > 0 ) {
                if ( /^\s*([a-zA-Z0-9_]+)\s*=\s*"([^"]+)"\s*$/ ) {
                    $backend_map{$1} = $2;
                    next;
                }
            }
        }
        if ( /^\s*}\s*$/ ) {
            $new_block--;
            if ( $new_block == 0 ) {
                $start_tf_block = 0;
                if ( length $backend_type > 0 ) {
                    print_backend($backend_type, \%backend_map);
                }
                $backend_type = "";
                %backend_map = ();
            }
        }
    }

}

sub process_file {

    open( my $vfdata, shift @_ ) || die "Error: $!";
    my @vfdata = map { chomp; /^\s*#/ ? () : $_ } <$vfdata>;
    close($vfdata);

    process_backend(\@vfdata);
}

sub usage {
    print <<EOUSAGE;
Usage: $0 [OPTIONS] TF-FILE [..]

Pass a Terraform .tf file.
Prints the Terraform provider backend configuration.

Options:
    -o FORMAT           Output format (flat, json)
EOUSAGE
    exit(1);
}


my %opts;
getopts('o:', \%opts);

if ( defined $opts{'o'} ) {
    $OUTPUT_FORMAT = $opts{'o'};
}

@ARGV || usage();

foreach my $arg (@ARGV) {
    process_file($arg);
}
