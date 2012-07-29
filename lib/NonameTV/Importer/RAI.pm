package NonameTV::Importer::RAI;

use strict;
use warnings;

=pod

Import data from RAI's website.

Channels: RAI UNO, RAI DUE, RAI TRE

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;
use Encode qw/decode encode/;

use NonameTV qw/MyGet Html2Xml FindParagraphs norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Rome" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  # the url is in format 'http://www.rai.it/dl/portal/guidatv/14-11-2008.html'

  my( $year, $month, $day ) = ( $objectname =~ /_(\d+)-(\d+)-(\d+)$/ );
  my $dt = DateTime->new( 
                          year  => $year,
                          month => $month,
                          day   => $day 
                          );

  my $url = sprintf( "%s%02d-%02d-%04d.html", $self->{UrlRoot}, $dt->day, $dt->month, $dt->year );

  progress( "RAI: $chd->{xmltvid}: Fetching from $url" );

  return( $url, undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  # do some corrections
  # on the end of the page, after rai3 chunk there is an error: the div is closed but no div is opened before
  $$cref =~ s/<\/ul><\/div><\/div>/<\/ul>/g;

  my $doc = Html2Xml( $$cref );
  
  if( not defined $doc ) {
    return (undef, "Html2Xml failed" );
  } 

  if( not $chd->{grabber_info} ){
    error( "You must specify grabber_info for $chd->{xmltvid}" );
    return( undef, undef );
  }

  progress( "RAI: $chd->{xmltvid}: Filtering on '$chd->{grabber_info}'" );

  my $paragraphs = FindParagraphs( $doc, "//div[\@class='Main clearfix']//div[\@class='$chd->{grabber_info}']//." );

  my $str = join( "\n", @{$paragraphs} );

  # all is in one string -> split it at each time
  $str =~ s/\s(\d{2}):(\d{2})/\n$1:$2 /g;
  $str =~ s/(MATTINA)/\n$1/g;
  $str =~ s/(POMERIGGIO)/\n$1/g;
  $str =~ s/(SERA)/\n$1/g;
  $str =~ s/(NOTTE)/\n$1/g;
  
  return( \$str, undef );
}


sub ContentExtension {
  return 'html';
}

sub FilteredExtension {
  return 'txt';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  $self->{batch_id} = $batch_id;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  
  my( $date ) = ($batch_id =~ /_(.*)/);

  my $dsh = $self->{datastorehelper};

  my @paragraphs = split( /\n/, $$cref );

  if( scalar(@paragraphs) == 0 ) {
    error( "$batch_id: No paragraphs found." ) ;
    return 0;
  }

  progress( "RAI: $chd->{xmltvid}: Date is $date\n" );
  $dsh->StartDate( $date, "06:00" ); 

  foreach my $text (@paragraphs) {

#print ">$text<\n";

    # It should be possible to ignore these strings with a better
    # FilterContent, because they look slightly different in the html.
    next if $text =~/^MATTINA$/i;
    next if $text =~/^POMERIGGIO$/i;
    next if $text =~/^SERA$/i;
    next if $text =~/^NOTTE$/i;

    if( $text =~ /^\d{2}:\d{2}\s+.*/ ) {

      my( $time, $title ) = ParseShow( $text );

      progress( "RAI: $chd->{xmltvid}: $time - $title" );

      my $ce = {
        channel_id => $channel_id,
        title => $title,
        start_time => $time,
      };

      $dsh->AddProgramme( $ce );

    } else {
      #error( "$batch_id: Unexpected text: '$text'" );
    }
  }
  
  return 1;
}

sub ParseShow
{
  my( $text ) = @_;

  my( $time, $title ) = ( $text =~ /^(\d{2}:\d{2})\s+(.*)$/ );

  # don't die on wrong encoding
  eval{ $title = decode( "iso-8859-1", $title ); };
  if( $@ ne "" ){
    error( "Failed to decode $@" );
  }

  return( $time, $title );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
