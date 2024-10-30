#!/usr/bin/env perl
# terraform-split-parts.pl - extract blocks from terraform configs and put them into separate files

$|=1;
use strict;
use warnings;

use Getopt::Std;
use Data::Dumper;

sub usage {
    print <<EOUSAGE;
Usage: $0 [OPTIONS] TF-FILE [..]

Takes Terraform configs, parses the root-level blocks, and dumps them into files.

Appends to files in the current directory, so make sure you move to a temporary 
directory before running this.

EOUSAGE
    exit(1);
}

sub process_backend {

    my $data = shift;

    my $start_tf_block = 0;
    my $new_block = 0;
    my $block_name;
    my $block_args;
    my @entry;
    my @block_list;

    for ( @$data ) {

        #print STDERR "LINE: '$_' start_tf_block $start_tf_block new_block $new_block\n";
        if ( $start_tf_block == 0 ) {
            if ( /^\s*(\w+)\s+(("[\w_-]+"\s+){0,})(\s*=\s*)?\{\s*$/ ) {
                print STDERR "Starting block $1\n";
                $start_tf_block = 1;
                $new_block++;
                $block_name = $1;
                if (defined $2) {
                    my $tmp = $2;
                    my @list;
                    while ( $tmp =~ s/^"([^"]+)"\s+// ) {
                        push @list, $1;
                    }
                    $block_args = [ @list ];
                }
                next;
            }
        } else {
            if ( /{\s*$/ ) {
                $new_block++;
            }
        }
        if ( $start_tf_block ) {
            print STDERR "adding '$_' to entry\n";
            push @entry, $_;

            if ( /^\s*}\s*$/ ) {
                $new_block--;
                if ( $new_block == 0 ) {
                    $start_tf_block = 0;
                    push @block_list, { 'name' => $block_name, 'args' => [ @$block_args ], 'data' => [ @entry ] };
                    @entry = ();
                }
            }
        }
    }

    return \@block_list;
}

sub process_file {

    open( my $vfdata, shift @_ ) || die "Error: $!";
    my @vfdata = map { chomp; /^\s*#/ ? () : $_ } <$vfdata>;
    close($vfdata);

    process_backend(\@vfdata);
}


my %opts;
#getopts('o:', \%opts);
#if ( defined $opts{'o'} ) {
#    $OUTPUT_FORMAT = $opts{'o'};
#}

@ARGV || usage();

foreach my $arg (@ARGV) {
    my $list = process_file($arg);
    foreach my $block ( @$list ) {
        print Dumper($block);
        die "Error: undefined block" unless defined $block;
        die "Error: no name for block" unless exists $block->{'name'} and defined $block->{'name'};
        open( my $fh, '>>', "$block->{'name'}.tf" ) || die "Error: could not open file '$block->{'name'}.tf' for append";
        print $fh "\n";
        print $fh $block->{'name'} . 
            " " . 
            join(" ", 
                (map { "\"$_\"" } @{$block->{'args'}} )
            ) .
            " {\n";
        print $fh join("\n", @{$block->{'data'}});
        print $fh "\n\n";
        close($fh);
    }
}
