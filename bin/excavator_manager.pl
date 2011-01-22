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
    'furthest'    => \$conf{furthest_first},
    'help'    => \$do_help,
);

usage() if $do_help;
usage() unless $conf{config_file} and -f $conf{config_file};

my $lacuna = Games::Lacuna::Client->new(
    cfg_file => $conf{config_file},
    #debug => 1,
);

my $empire  = $lacuna->empire->get_status->{empire};

my $excavated_bodies = [];

my $body_data = YAML::Any::LoadFile( $conf{body_file} ) || die "Couldn't load body data from YAML file $conf{body_file}";

if ( defined( $conf{excavated_file}) && -f $conf{excavated_file} ) {
    $excavated_bodies = YAML::Any::LoadFile( $conf{excavated_file} )
}

# cull the list of available bodies to keep the number of API calls to a dull roar.

if ( scalar( @{$excavated_bodies} )) {
    my @temp = ();
    foreach my $body ( @{$body_data} ) {
        next if grep { $_ == $body->{id} } @{$excavated_bodies};
        push @temp, $body;
    }
    $body_data = \@temp;
}

die "No bodies available to excavate. Probe more stars!\n" unless scalar( @{$body_data} );

foreach my $planet_id ( keys %{ $empire->{planets} } ) {
    my $planet    = $lacuna->body( id => $planet_id );
    my $buildings = $planet->get_buildings->{buildings};


    my $spaceport_id = first { $buildings->{$_}->{name} eq 'Space Port' } keys %$buildings;

    next unless $spaceport_id;

    my $spaceport = $lacuna->building( id => $spaceport_id, type => 'SpacePort' );

    my $spaceport_meta = $spaceport->view;

    # first, see if we even have an Excavator to send
    if (defined( $spaceport_meta->{docked_ships}->{excavator} )) {
        my $docked_count = $spaceport_meta->{docked_ships}->{excavator};

        my @distances = distance_map( $planet, $body_data );

        @distances = reverse @distances if defined $conf{furthest_first};

        # cycle the sorted (by distance) bodies and send the excavator(s)
        # to the first available.

        for ( 1 ... $docked_count) {
            foreach my $pair ( @distances ) {
                my $sendable_ships = $spaceport->get_ships_for( $planet_id, { body_id => $pair->[1]}  )->{available};

                next unless scalar @{$sendable_ships};
                my $excavator = first { $_->{type} eq 'excavator' } @{$sendable_ships};

                if ( $excavator ) {
                    $spaceport->send_ship( $excavator->{id}, { body_id => $pair->[1] } );
                    push @{$excavated_bodies}, $pair->[1];
                    last;
                }
            }
        }
    }

    # now, queue up new Excavators

    my @shipyard_ids = grep { $buildings->{$_}->{name} eq 'Shipyard' } keys %$buildings;

    next unless scalar @shipyard_ids;

    foreach my $shipyard_id ( @shipyard_ids ) {

        my $shipyard = $lacuna->building( id => $shipyard_id, type => 'Shipyard' );

        # make sure we can even build an Excavator here.
        my $buildable = $shipyard->get_buildable;
        next unless $buildable->{docks_available} > 0;
        next unless $buildable->{buildable}->{excavator}->{can} == 1;

        # don't start building if we already have an Excavator in the hopper.
        my $currently_building = $shipyard->view_build_queue->{ships_building};
        next if grep { $_->{type} eq 'excavator' } @{$currently_building};

        # finally, if we make it here, build the darn ship already.
        $shipyard->build_ship('excavator');
    }

}

if ( defined( $conf{excavated_file}) && -f $conf{excavated_file} ) {
    YAML::Any::DumpFile($conf{excavated_file}, $excavated_bodies );
}

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
       --conf           The path to your empire's YAML config file.
       --bodyfile       Path to the YAML file holding the list of available
                        bodies.
       --excavatedfile  Path to the YAML file holding the list of previously
                        excavated bodies.
       --furthest       Send excavators to the furthest available body
                        (default is nearest)
END_USAGE
}
