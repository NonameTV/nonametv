package NonameTV::Importer::Tiji;

use strict;
use warnings;

=pod

Import data from CSV-files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Encode;
use Text::CSV;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, 'Europe/Paris' );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.csv$/i );
  progress( "Tiji: $xmltvid: Processing $file" );

  my $date;
  my $currdate = "x";

  open my $CSVFILE, "<", $file or die $!;

  my $csv = Text::CSV->new( {
    sep_char => ';',
    allow_whitespace => 1,
    blank_is_undef => 1,
    binary => 1,
  } );

  # get the column names from the first line
  my @columns = $csv->column_names( $csv->getline( $CSVFILE ) );
#foreach my $cl (@columns) {
#print "$cl\n";
#}

  # main loop
  while( my $row = $csv->getline_hr( $CSVFILE ) ){

    # Date
    next if not $row->{'DATE'};
    $date = ParseDate( $row->{'DATE'} );
    next if not $date;

    if( $date ne $currdate ){

      if( $currdate ne "x" ) {
        $dsh->EndBatch( 1 );
      }

      my $batch_id = $xmltvid . "_" . $date;
      $dsh->StartBatch( $batch_id , $channel_id );
      $dsh->StartDate( $date , "05:00" );
      $currdate = $date;

      progress( "Tiji: $xmltvid: Date is $date" );
    }

    # Time
    my $time = $row->{'HEURE'};
    next if not $time;
    next if ( $time !~ /^\d\d\:\d\d$/ );

    # Title
    my $title = $row->{'TITRE ORIGINAL'};
    next if not $title;
    $title = decode( "iso-8859-1", $title );

    # Subtitle
    my $subtitle = $row->{'SOUS-TITRE / THEME'};
    $subtitle = decode( "iso-8859-1", $subtitle );

    # Genre
    my $genre = $row->{'FORMAT'};

    # Episode
    my $episode = $row->{'EPISODE'};

    # Presenters
    my $presenters = $row->{'PRESENTATEUR'};

    # Description
    my $description = $row->{'SYNOPSIS/CONCEPT'};
    $description = decode( "iso-8859-1", $description );

    progress( "Tiji: $xmltvid: $time - $title" );

    my $ce = {
      channel_id => $channel_id,
      title => $title,
      start_time => $time,
    };

    $ce->{subtitle} = $subtitle if $subtitle;

    if( $genre ) {
      my($program_type, $category ) = $ds->LookupCat( "Tiji", $genre );
      AddCategory( $ce, $program_type, $category );
    }

    if( $episode ){
      $ce->{episode} = sprintf( ". %d .", $episode-1 );
    }

    $ce->{presenters} = $presenters if $presenters;

    $ce->{description} = $description if $description;

    $dsh->AddProgramme( $ce );
  }

  $dsh->EndBatch( 1 );

  return;
}

sub ParseDate {
  my( $text ) = @_;
  my( $day , $month , $year );

  return undef if( ! $text );

  if( $text =~ /^\d\d\/\d\d\/\d\d\d\d/ ){
    ( $day , $month , $year ) = ( $text =~ /^(\d\d)\/(\d\d)\/(\d\d\d\d)/ );
  }

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
