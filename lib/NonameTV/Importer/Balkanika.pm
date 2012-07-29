package NonameTV::Importer::Balkanika;

use strict;
use warnings;

=pod

Import data from Balkanika website (www.balkanika.tv).

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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Zagreb" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my $today = DateTime->today();
  $today =~ s/-//g;
  $today =~ s/T.*//g;

  my $day = $batch_id;
  $day =~ s/.*_//;
  $day =~ s/-//g;

  if( $day lt $today ){
    progress( "Balkanika: $batch_id: Skipping day in the past $day" );
    return( 0, 0 );
  }

  my( $tyear, $tmonth, $tday ) = ( $batch_id =~ /_(\d+)-(\d+)-(\d+)$/ );
  my $dt = DateTime->new( year   => $tyear,
                          month  => $tmonth,
                          day    => $tday,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/Zagreb',
                          );

  my $dayname = $dt->day_name;

  # the url is the one that is specified in UrlRoot and it never changes
  my $url = $self->{UrlRoot} . "/" . lc($dayname) . ".htm";

  my( $content, $code ) = MyGet( $url );

  return( $content, $code );
}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $dsh = $self->{datastorehelper};

  my $doc = Html2Xml( $$cref );
  if( not defined $doc ) {
    return (undef, "Html2Xml failed" );
  }

  my $paragraphs = FindParagraphs( $doc, "//table//table//table//." );

  my $str = join( "\n", @{$paragraphs} );

  if( scalar(@{$paragraphs}) == 0 ) {
    error( "$batch_id: No paragraphs found." ) ;
    return 0;
  }

  my $date =  $batch_id;
  $date =~ s/$chd->{xmltvid}_//;
  $dsh->StartDate( $date , "00:00" );
  progress("Balkanika: $chd->{xmltvid}: Date is: $date");

  my @ces;
  my $ce;

  foreach my $text (@{$paragraphs}) {

#print ">$text<\n";

    if( $text =~ /^\d{2}:\d{2}$/ ){

      # push ce if we have it
      if( $ce ){
        push( @ces , $ce );
        undef $ce;
      }

      $ce = {
        channel_id => $chd->{id},
        start_time => $text,
      };

    } elsif( not $ce->{title} ){
      $ce->{title} = $text if( $ce );
    } elsif( not $ce->{description} ){
      $ce->{description} = $text if( $ce );
    }
  }

  push( @ces , $ce ) if $ce;

  FlushData( $chd, $dsh, @ces );
  
  return 1;
}

sub FlushData
{
  my ( $chd, $dsh , @data ) = @_;

  if( @data ){
    foreach my $element (@data) {
      progress("Balkanika: $chd->{xmltvid}: $element->{start_time} - $element->{title}");
      $dsh->AddProgramme( $element );
    }
  }
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
