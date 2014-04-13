package NonameTV::Importer::HorseAndCountry;

use strict;
use warnings;

=pod

Imports data for H&C TV.
The files have seperate XML-container for programinfo (title, season and episode) and
airtimes (start, duration).

=cut

use utf8;

use DateTime;
use XML::LibXML;
use IO::Scalar;
use Data::Dumper;

use NonameTV qw/norm ParseXml AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  # use augment
  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  }


  return;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "H&C: $chd->{xmltvid}: Processing XML $file" );

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "H&C: $file: Failed to parse xml" );
    return;
  }

  my @epis;

  my $currdate = "x";
  my $column;

  #  episodes
  my $rows = $doc->findnodes( "//ProgramInformation" );

  if( $rows->size() == 0 ) {
    error( "H&C: $chd->{xmltvid}: No ProgramInformations found" ) ;
    return;
  }

  foreach my $row ($rows->get_nodelist) {
     my $progid = $row->findvalue( './@programId' );

     my $title  = norm($row->findvalue( './/BasicDescription/Title[type=main]' ));
     my $desc   = norm($row->findvalue( './/BasicDescription/Synopsis' ));

     my $ce = {
        title => $title,
        description => $desc,
     };

     @epis->{$progid} = $ce;

  } # next row

  print Dumper(@epis);


  #  AIRTIMES
  my $rows2 = $doc->findnodes( "//ScheduleEvent" );

  if( $rows2->size() == 0 ) {
    error( "H&C: $chd->{xmltvid}: No ScheduleEvents found" ) ;
    return;
  }

  foreach my $row2 ($rows2->get_nodelist) {

     #progress( "H&C: $chd->{xmltvid}: $start - $title" );
     #$dsh->AddProgramme( $ce );

  } # next row

  $dsh->EndBatch( 1 );

  return 1;
}


sub create_dt
{
  my $self = shift;
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second, $timezone_hour, $timezone_minute ) =
      ($str =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)\+(\d+):(\d+)$/ );



  my $dt = DateTime->new( year      => $year,
                          month     => $month,
                          day       => $day,
                          hour      => $hour,
                          minute    => $minute,
                          time_zone => 'Europe/Helsinki'
                          );

  $dt->set_time_zone( "UTC" );

  #$dt->subtract( hours => $timezone_hour ); # Remove the timezone they add, so it become an UTC time

  return $dt;
}

sub split_text
{
  my( $t ) = @_;

  return () if not defined( $t );

  # Remove any trailing whitespace
  $t =~ s/\s*$//;

  # Replace strange dots.
  $t =~ tr/\x2e/./;

  # We might have introduced some errors above. Fix them.
  $t =~ s/([\?\!])\./$1/g;

  # Replace ... with ::.
  $t =~ s/\.{3,}/::./g;

  # Lines ending with a comma is not the end of a sentence
#  $t =~ s/,\s*\n+\s*/, /g;

# newlines have already been removed by norm()
  # Replace newlines followed by a capital with space and make sure that there
  # is a dot to mark the end of the sentence.
#  $t =~ s/([\!\?])\s*\n+\s*([A-Z���])/$1 $2/g;
#  $t =~ s/\.*\s*\n+\s*([A-Z���])/. $1/g;

  # Turn all whitespace into pure spaces and compress multiple whitespace
  # to a single.
  $t =~ tr/\n\r\t \xa0/     /s;

  # Mark sentences ending with '.', '!', or '?' for split, but preserve the
  # ".!?".
  $t =~ s/([\.\!\?])\s+([A-Z���])/$1;;$2/g;

  my @sent = grep( /\S\S/, split( ";;", $t ) );

  if( scalar( @sent ) > 0 )
  {
    # Make sure that the last sentence ends in a proper way.
    $sent[-1] =~ s/\s+$//;
    $sent[-1] .= "."
      unless $sent[-1] =~ /[\.\!\?]$/;
  }

  return @sent;
}

# Join a number of sentences into a single paragraph.
# Performs the inverse of split_text
sub join_text
{
  my $t = join( " ", grep( /\S/, @_ ) );
  $t =~ s/::/../g;

  return $t;
}

sub parse_person_list
{
  my( $str ) = @_;

  # Remove all variants of m.fl.
  $str =~ s/\s*m[\. ]*fl\.*\b//;

  # Remove trailing '.'
  $str =~ s/\.$//;

  $str =~ s/\boch\b/,/;
  $str =~ s/\bsamt\b/,/;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    # The Cast-entry is sometimes cutoff, which means that the
    # character name might be missing a trailing ).
    s/\s*\(.*$//;
    s/.*\s+-\s+//;
  }

  return join( ", ", grep( /\S/, @persons ) );
}


1;