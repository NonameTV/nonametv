package NonameTV::Importer;

use strict;
use warnings;

use File::Copy;
use IO::Scalar;

use Data::Dumper;

use NonameTV qw/CompareArrays/;

=head1 NAME

NonameTV::Importer

=head1 DESCRIPTION

Abstract base-class for the NonameTV::Importer::* classes.

A package derived from NonameTV::Importer can be used to import
data from different datasources into the NonameTV programming
database.

NonameTV::Importer::*-objects are instantiated from the nonametv.conf
configuration file. To instantiate an object, add an entry in the
'Importers'-hash. Each entry consists of a hash with configuration
parameters for the importer. The following keys are common to all
importers: 

Type - The class-name for the importer, i.e. the instantiated object
will be of class NonameTV::Importer::$Type.

Channels - The channels that this importer shall import data for. The
value shall be another hash with xmltvids as keys and arrays as
values. The array shall contain the following data in this order:

  display_name, grabber_info, sched_lang, empty_ok, def_pty,
  def_cat, url, chgroup 

The fields def_pty, def_cat, url, and chgroup are optional and can be
omitted.

A sample entry for an importer can look like this:

    Aftonbladet_http => {
      Type => 'Aftonbladet_http',
      MaxWeeks => 4,
      UrlRoot => "http://www.aftonbladet.se/atv/pressrum/tabla",
      Channels => {
        "tv7.aftonbladet.se" => 
           [ "Aftonbladet TV7", "", "sv", 0, "", "", "", "" ],
        },
      },

The MaxWeeks and UrlRoot parameters are implemented by the classes
deriving from Importer.

=head1 METHODS

=over 4

=cut

=item new

The constructor for the object. Called with a hashref as the first parameter.
This is a ref to the configuration for the object from the nonametv.conf-
file. The second parameter is a NonameTV::DataStore object.

=cut

sub new {
  my $class = ref( $_[0] ) || $_[0];

  my $self = { }; 
  bless $self, $class;

  # Copy the parameters supplied in the constructor.
  foreach my $key (keys(%{$_[1]})) {
      $self->{$key} = ($_[1])->{$key};
  }

  $self->{datastore} = $_[2];

  return $self;
}

=item Import

Import is called from the nonametv-import executable. It takes a hashref as 
the only parameter. The hashref 
points to a hash with the command-line parameters decoded by Getopt::Long 
using the $NonameTV::Importer::*::Options arrayref as format specification.

=cut

sub Import {
  my( $self, $param ) = @_;
  
  $self->ImportData( $param );
}

=item ImportData

ImportData is called from Import. It takes a hashref as the only
parameter. The hashref points to a hash with the command-line
parameters decoded by Getopt::Long using the
$NonameTV::Importer::*::Options arrayref as format specification.

The ImportData method must be overridden in classes inheriting from
NonameTV::Importer.

=cut

sub ImportData {
  my( $self, $param ) = @_;
  
  die "You must override ImportData in your own class";
}

sub FetchData {
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my $root = "/var/local/nonametv/override";
  my $code = 0;
  my $content;

  if( -f( "$root/new/$batch_id" ) ) {
    move( "$root/new/$batch_id", "$root/data/$batch_id" );
    $code = 1;
  }

  if( -f( "$root/data/$batch_id" ) ) {
    # Check if the data on site has changed
    my( $site_content, $site_code ) = 
      $self->FetchDataFromSite( $batch_id, $data );

    print STDERR "$batch_id New data available for override.\n"
      if( $site_code );
    
    $site_content = undef;

    # Load data from file
    {
      local( $/ ) ;
      open( my $fh, "$root/data/$batch_id" ) 
        or die "Failed to read form $root/data/$batch_id: $@";
      $content = <$fh>;
    }
  }
  else {
    ( $content, $code ) = $self->FetchDataFromSite( $batch_id, $data );
    if( -f( "$root/delete/$batch_id" ) ) {
      # Delete the old override and force update from site.
      unlink( "$root/delete/$batch_id" );
      $code = 1;
    }
  }
  
  return ($content, $code);
}


=item ImportFile

Import the content from a single file.

=cut

sub ImportFile {
  my $self = shift;
  my( $contentname, $filename, $p ) = @_;

  my $content;

  # Load data from file
  {
    local( $/ ) ;
    open( my $fh, "$filename" ) 
        or die "Failed to read from $filename: $@";
    $content = <$fh>;
  }

  return $self->ImportContent( $contentname, \$content, $p );
}

sub UpdateChannels {
  my $self = shift;

  return if defined $self->{_ChannelsUpdated};

  if( not defined( $self->{Channels} ) ) {
    $self->LoadChannelsFromDb();
  }
  else {
    $self->SyncChannelsToDb();
  }

  $self->{_ChannelsUpdated} = 1;
}

=item ListChannels

Return an arrayref with one entry per channnel configured for this
grabber. Each entry is a hash with information about the channel.

=cut

sub ListChannels {
  my $self = shift;

  $self->UpdateChannels();

  return $self->{_ChannelData};
}

sub LoadChannelsFromDb {
  my $self = shift;

  $self->{_ChannelData} = $self->{datastore}->FindGrabberChannels( 
     $self->{ConfigName} );
}

sub defdef {
  my( $value, $default ) = @_;

  return defined $value ? $value : $default;
}

sub isequal {
  my( $conf, $db ) = @_;

  return 0 if $conf->{display_name} ne $db->{display_name};
  return 0 if $conf->{sched_lang} ne $db->{sched_lang};
  return 0 if $conf->{empty_ok} ne $db->{empty_ok};
  return 0 if $conf->{def_pty} ne $db->{def_pty};
  return 0 if $conf->{def_cat} ne $db->{def_cat};
  return 0 if defdef($conf->{url}, "") ne defdef( $db->{url}, "");
  return 0 if defdef($conf->{chgroup}, "") ne defdef($db->{chgroup}, "");

  return 0 if $conf->{grabber_info} ne $db->{grabber_info};

  return 1;
}

sub SyncChannelsToDb {
  my $self = shift;

  # 1. Convert Channels to _ChannelData. Order by xmltvid.
  # 2. Iterate through _ChannelData and FindGrabberChannels.

  $self->{_ChannelData} = [];

  foreach my $xmltvid (sort keys %{$self->{Channels}}) {
    my $e = $self->{Channels}->{$xmltvid};
    my $ce = {
      xmltvid => $xmltvid,
      display_name => $e->[0],
      grabber_info => defdef( $e->[1], "" ),
      sched_lang => $e->[2],
      empty_ok => defdef( $e->[3], 0 ),
      def_pty => defdef( $e->[4], "" ),
      def_cat => defdef( $e->[5], "" ),
      url => $e->[6],
      chgroup => defdef( $e->[7], "" ),
    };
    
    push @{$self->{_ChannelData}}, $ce;
  }

  my $db = $self->{datastore}->FindGrabberChannels( $self->{ConfigName} );
  my $conf = $self->{_ChannelData};

  CompareArrays( $conf, $db, {
    cmp => sub { $_[0]->{xmltvid} cmp $_[1]->{xmltvid} },
    added => sub {       
      print STDERR "Adding channel info for $_[0]->{xmltvid}\n";
      $self->AddChannel( $_[0] );
    },
    deleted => sub {
      print STDERR "Deleting channel info for $_[0]->{xmltvid}\n";
      $self->{datastore}->ClearChannel( $_[0]->{id} );
      $self->{datastore}->sa->Delete( "channels", { id => $_[0]->{id} } );
    },
    equal => sub {
      # The channel id only exists in the database.
      $_[0]->{id} = $_[1]->{id};

      if( not isequal( $_[0], $_[1] ) ) {
	print STDERR "Updating channel info for $_[0]->{xmltvid}\n";
	$self->UpdateChannel( $_[0] );
      }
    },
    max => { xmltvid => "zzzzzzz" },
                 } );
}

sub UpdateChannel {
  my $self = shift;
  my( $cc ) = @_;

  my $data = {
    xmltvid => $cc->{xmltvid},
    display_name => $cc->{display_name},
    grabber => $self->{ConfigName},
    grabber_info => $cc->{grabber_info},
    sched_lang => $cc->{sched_lang},
    empty_ok => $cc->{empty_ok},
    def_pty => $cc->{def_pty},
    def_cat => $cc->{def_cat},
    url => $cc->{url},
    chgroup => $cc->{chgroup},
  };

  $self->{datastore}->sa->Update( 'channels', {id => $cc->{id}}, $data );
}

sub AddChannel {
  my $self = shift;
  my( $cc ) = @_;

  my $data = {
    xmltvid => $cc->{xmltvid},
    display_name => $cc->{display_name},
    grabber => $self->{ConfigName},
    grabber_info => $cc->{grabber_info},
    sched_lang => $cc->{sched_lang},
    empty_ok => $cc->{empty_ok},
    def_pty => $cc->{def_pty},
    def_cat => $cc->{def_cat},
    url => $cc->{url},
    chgroup => $cc->{chgroup},
    export => 1,
  };

  $self->{datastore}->sa->Add( 'channels', $data );
  my $id = $self->{datastore}->sa->Lookup( 'channels', 
    { xmltvid => $cc->{xmltvid},
      grabber => $self->{ConfigName} },
    "id" );

  $cc->{id} = $id;	 
}

=head1 CLASS VARIABLES

=item $OptionSpec, $OptionDefaults

Format specifications and default values for Getopt::Long.

our $OptionSpec = [ qw/force-update/ ];
our %OptionDefaults = ( 
                        'force-update' => 0,
                        );

 
=head1 COPYRIGHT

Copyright (C) 2004-2008 Mattias Holmlund.

=cut

1;
