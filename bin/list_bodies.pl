#!/usr/bin/perl
use strict;
use warnings;
use Games::Lacuna::Client;
use Data::Dumper;
use YAML::Any;
use Getopt::Long qw(GetOptions);
use List::Util qw(first);

my %conf = ();
my $do_help = undef;

GetOptions(
    'conf=s'      => \$conf{config_file},
    'bodyfile=s'  => \$conf{body_file},
    'help'        => \$do_help,
);

usage() if $do_help;
usage() unless $conf{config_file} and -f $conf{config_file};

my $lacuna = Games::Lacuna::Client->new(
  cfg_file => $conf{config_file},
  #debug => 1,
);

my $empire  = $lacuna->empire->get_status->{empire};

my @data = ();

foreach my $planet_id ( keys %{ $empire->{planets} } ) {
    my $planet    = $lacuna->body( id => $planet_id );
    my $buildings = $planet->get_buildings->{buildings};

    my $observatory_id = first { $buildings->{$_}->{name} eq 'Observatory' } keys %$buildings;

    next unless $observatory_id;

    my $observatory = $lacuna->building( id => $observatory_id, type => 'Observatory' );

    my $stars = $observatory->get_probed_stars->{stars};

    foreach my $star ( @$stars ) {
        my $bodies = $star->{bodies};
        next unless $bodies && ref $bodies eq 'ARRAY';
        push @data, @$bodies;
    }
}

if ( defined( $conf{body_file} )) {
    YAML::Any::DumpFile($conf{body_file}, \@data );
}
else {
    print YAML::Any::Dump( \@data );
}

exit(0);

sub usage {
  die <<"END_USAGE";
Usage: $0 [options]
       --conf       The path to your empire's YAML config file (required).
       --bodyfile   Optional file path to save the generated body data to.
                    If not given, the script will print them to STDOUT.
END_USAGE
}
