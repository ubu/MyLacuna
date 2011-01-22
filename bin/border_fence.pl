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

    my $intel_id = first { $buildings->{$_}->{name} eq 'Intelligence Ministry' } keys %$buildings;

    next unless $intel_id;

    my $intel_min = $lacuna->building( id => $intel_id, type => 'Intelligence' );

    my $spies = $intel_min->view_spies->{spies};

    next unless $spies and scalar @{$spies};
    foreach my $spy ( @{$spies} ) {
        # make sure the spy is available, local, and idle
        next unless $spy->{is_available} == 1;
        next unless $spy->{assignment} eq 'Idle';
        next unless $spy->{assigned_to}->{body_id} == $planet_id;
        next unless grep { $_->{task} eq 'Security Sweep' } @{$spy->{possible_assignments}};

        $intel_min->assign_spy( $spy->{id}, 'Security Sweep' );
    }
}

exit(0);

sub usage {
  die <<"END_USAGE";
Usage: $0 [options]
       --conf       The path to your empire's YAML config file (required).
END_USAGE
}
