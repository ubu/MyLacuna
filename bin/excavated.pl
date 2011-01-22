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
    'excavatedfile=s'  => \$conf{excavated_file},
    'help'    => \$do_help,
);

usage() if $do_help;
usage() unless $conf{config_file} and -f $conf{config_file};

my $lacuna = Games::Lacuna::Client->new(
    cfg_file => $conf{config_file},
    #debug => 1,
);

my @excavated = ();

my $empire  = $lacuna->empire->get_status->{empire};

warn Dumper( $empire );

my $body_data = YAML::Any::LoadFile( $conf{body_file} ) || die "Couldn't load body data from YAML file $conf{body_file}";

my $planet = $lacuna->body( id => 170190 );

my $buildings = $planet->get_buildings->{buildings};
my $spaceport_id = first { $buildings->{$_}->{name} eq 'Space Port' } keys %$buildings;

my $spaceport = $lacuna->building( id => $spaceport_id, type => 'SpacePort' );

my $spaceport_meta = $spaceport->view;

unless (defined( $spaceport_meta->{docked_ships}->{excavator} )) {
    die "The planet you select must have at least one Excavator docked and ready to send.";
}

my @distances = distance_map( $planet, $body_data );

@distances = reverse @distances;
foreach my $pair (@distances) {

    my $unavailable = $spaceport->get_ships_for( 170190, { body_id => $pair->[1]}  )->{unavailable};

    if ( grep{ $_->{ship}->{type} eq 'excavator' && $_->{reason}->[0] == 1010 && $_->{reason}->[1] =~ /You have already sent an Excavator/ } @{$unavailable} ) {
        push @excavated, $pair->[1];
    }
}

if ( defined( $conf{excavated_file} )) {
    YAML::Any::DumpFile($conf{excavated_file}, \@excavated );
}
else {
    print YAML::Any::Dump( \@excavated );
}

exit(0);


sub distance_map {
    my $from_planet = shift;
    my $body_list = shift;

    my $from_planet_extra = $from_planet->get_status->{body};

    my @temp = ();
    foreach my $body ( @{$body_list} ) {
        # don't drill inhabited planets
        next if defined $body->{empire};

        # don't drill Space Stations and other oddities
        next unless $body->{type} =~ /^(habitable|asteroid)/;

        # thank you Pythagoras!
        my $distance = sqrt( ($from_planet_extra->{'x'} - $body->{'x'})**2 + ($from_planet_extra->{'y'} - $body->{'y'})**2 );

        #warn sprintf "Body %s of type %s is %s from %s\n", $body->{name}, $body->{type}, $distance, $from_planet_extra->{name};
        push @temp, [ $distance, $body->{id} ],
    }
    my @distances = sort { $a->[0] <=> $b->[0] } @temp;
    return @distances;
}

sub usage {
  die <<"END_USAGE";
Usage: $0 [options]
       --conf       The path to your empire's YAML config file.
       --bodyfile   Path to the YAML file holding the list of avialable bodies.
       --furthest   Send excavators to the furthest available body
                    (default is nearest)
END_USAGE
}
