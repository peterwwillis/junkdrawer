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

If the block is a 'resource', dumps into a filename of the name of the resource.
(you can combine them later if you want, ex: \`cat aws_*.tf > resource.tf\`)

Appends to files in the current directory, so make sure you move to a temporary 
directory before running this.

EOUSAGE
    exit(1);
}


# Yes, this is a horribe cludge and needs to be turned into real Perl OO.
# I'm lazy.
sub process_backend {

    my $data = shift;
    my %state = (
        start_tf_block => 0,
        new_block => 0,
        block_name => "",
        block_args => [],
        entry => [],
        block_list => []
    );

    my $handle_start = sub {
        my ($self, $word1, $quotwords1, $rsname, $four, $five) = @_;
        print STDERR "  Starting block $word1\n";
        print STDERR "    word1 '$word1' quotwords1 '$quotwords1' rsname '$rsname' four '$four' five '$five'\n";
        $self->{start_tf_block} = 1;
        $self->{new_block}++;
        $self->{block_name} = $word1;
        if (defined $quotwords1) {
            my $tmp = $quotwords1;
            my @list;
            # Trying changing \s+ to \s+? to handle 'module' blocks
            while ( $tmp =~ s/^"([^"]+)"\s+// ) {
                push @list, $1;
            }
            $self->{block_args} = [ @list ];
            print STDERR "      block_args (@{$self->{block_args}})\n";
        }
    };

    my $handle_end = sub {
        my ($self) = @_;
        print STDERR "  Examining block end\n";
        $self->{new_block}--;

        if ( $self->{new_block} == 0 ) {

            print STDERR "    Ending block $self->{block_name}\n";
            $self->{start_tf_block} = 0;

            push( @{$self->{block_list}}, {
                'name' => $self->{block_name},
                'args' => [ @{$self->{block_args}} ],
                'data' => [ @{$self->{entry}} ]
            });

            @{$self->{entry}} = ();
        }
    };

    for ( @$data ) {

        print STDERR "        Data: '$_'\n        start_tf_block $state{start_tf_block} new_block $state{new_block}\n";

        if ( $state{start_tf_block} == 0 ) {
            if ( /^\s*(\w+)\s+(("[\w_-]+"\s+){0,})(\s*=\s*)?\{\s*(\})?\s*$/ ) {
                $handle_start->(\%state, $1, $2, $3, $4, $5);
                # Block with no contents found; finish now
                if ( defined $5 and $5 eq "}" ) {
                    push @{$state{entry}}, "}";
                    $handle_end->(\%state);
                }
                next;
            }
        }

        elsif ( $state{start_tf_block} ) {
            if ( ! /^\s*#/ && /{\s*$/ ) {
                $state{new_block}++;
            }

            print STDERR "            adding Data entry\n";
            push @{$state{entry}}, $_;

             # allow other chars after the '}', for example in a variable def with '})'
            if ( /^\s*}/ ) {
                $handle_end->(\%state);
            }
        }
    }

    return $state{block_list};
}

sub dump_file {
    my $block = shift;
    my $fname;

    print Dumper($block);
    die "Error: undefined block" unless defined $block;
    die "Error: no name for block" unless exists $block->{'name'} and defined $block->{'name'};

    # Change the filename based on block type and args
    if ( exists $block->{'args'} and length( $block->{'args'} ) > 0 ) {

        # If block is a 'resource', make filename be the first argument (provider/resource name)
        if ( $block->{'name'} eq "resource" ) {
            $fname = $block->{'args'}->[0] . ".tf";

        # If block is a 'module', prepend 'module_', and then use the module name
        } elsif ( $block->{'name'} eq "module" ) {
            $fname = "module_" . $block->{'args'}->[0] . ".tf";
        }

    }
    if ( !defined $fname ) {
        $fname = $block->{'name'} . ".tf";
    }

    open( my $fh, '>>', $fname ) || die "Error: could not open file '$fname' for append";

    print $fh "\n";

    my $startline = "$block->{'name'} ";
    $startline .= join(" ", (map { "\"$_\"" } @{$block->{'args'}}) );
    $startline .= " {\n";
    print $fh $startline;

    print $fh join("\n", @{$block->{'data'}});
    print $fh "\n\n";

    close($fh);
}

sub process_file {

    open( my $vfdata, shift @_ ) || die "Error: $!";
    #my @vfdata = map { chomp; /^\s*#/ ? () : $_ } <$vfdata>;
    my @vfdata = map { chomp; $_ } <$vfdata>;
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
        dump_file($block);
    }
}
