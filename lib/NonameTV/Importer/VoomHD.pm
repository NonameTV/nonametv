package NonameTV::Importer::VoomHD;

use strict;
use warnings;

=pod

Import data from VoomHD web site.

Channels: Animania HD, Equator HD, Family Room HD, FilmFest HD, Gallery HD, KungFu HD, GamePlay HD,
          HDNews, Rush HD, Rave HD, Monsters HD, Treasure HD, Ultra HD, Voom HD Movies, WorldSport HD

Features:

=cut

use utf8;

use DateTime;

use NonameTV qw/MyGet norm MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

use constant {
  T_START => 0,
  T_HEAD1 => 11,
  T_HEAD2 => 12,
  T_HEAD3 => 13,
  T_SHOW => 14,
  T_DESC => 15,
  T_STOP => 16,
};

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/London" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $xmltvid ) = ( $batch_id =~ /^(.*)_.*$/ );

  # the url is the one that is specified in UrlRoot and it never changes
  my $url = $self->{UrlRoot} . "/" . $data->{grabber_info} . "/week/?tzset=14";

  progress( "VoomHD: $xmltvid: Fetching data from $url" );
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

  my $date;
  my $currdate = "x";
  my ( $hour, $min, $ampm, $time, $title, $description, $duration );

  my @lines = split( /\n/, $$cref );
  if( scalar(@lines) == 0 ) {
    error( "$batch_id: No lines found." ) ;
    return 0;
  }

  my $position = T_START;
  my $expect = T_HEAD1;
  my $inshow = 0;

  foreach my $text (@lines) {
 
#print ">$text<\n";

    if( $position eq T_START and $expect eq T_HEAD1 and $text =~ /<table class="schedule">/ ){
      $position = T_HEAD1;
      $expect = T_HEAD2;
    } elsif( $position eq T_HEAD1 and $expect eq T_HEAD2 ){
      if( isDate( $text ) ){
        $date = ParseDate( $text );

        if( $date ne $currdate ) {

          if( $currdate ne "x" ) {
            #$dsh->EndBatch( 1 );
          }

          $dsh->StartDate( $date , "00:00" );
          $currdate = $date;

          progress("VoomHD: $chd->{xmltvid}: Date is: $date");
        }

        $position = T_HEAD2;
        $expect = T_SHOW;
      }
    } elsif( $position ne T_START and $text =~ /<\/table>/ ){
      $position = T_START;
      $expect = T_HEAD1;
    } elsif( $text =~ /<!-- END CENTER CONTENT WELL -->/ ){
      $position = T_STOP;
      $expect = T_HEAD1;
    }

    if( $expect eq T_SHOW ){

      if( not $inshow and $text =~ /<tr onmouseover=/ ){
        $inshow = 1;
      } elsif( $inshow and $text =~ /<\/tr>/ ){
        $inshow = 0;
      }

      if( $inshow and $text =~ /^\s*\d+:\d+\s+(am|pm)/i ){
        ( $hour, $min, $ampm ) = ( $text =~ /^\s*(\d+):(\d+)\s+(am|pm)/i );
        if( $hour eq 12 and $ampm eq "am" ){
          $hour = 0;
        } elsif( $hour < 12 and $ampm eq "pm" ){
          $hour += 12;
        }
        $time = sprintf( "%02d:%02d", $hour, $min );
      } elsif( $text =~ /^\s*<h2>.*<\/h2>$/ ){
        ( $title ) = ( $text =~ /^\s*<h2>(.*)<\/h2>$/ );
      } else {
        $description = $text;
      }

      if( not $inshow and $time and $title ){

        progress( "VoomHD: $chd->{xmltvid}: $time - $title" );

        my $ce = {
          channel_id => $chd->{id},
          title => norm($title),
          start_time => $time,
        };

        #$ce->{description} = norm($description) if $description;

        $dsh->AddProgramme( $ce );

        $time = $title = $description = "";
      }

    }

  }
  
  return 1;
}

sub isDate
{
  my( $text ) = @_;

  # the date is in format '<div class="floatLeft">Friday, Dec. 26</div>'
  if( $text =~ /^\s*<div class="floatLeft">(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\,*\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\.*\s+\d+<\/div>$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my( $text ) = @_;

  # the date is in format '<div class="floatLeft">Friday, Dec. 26</div>'
  my( $dayname, $monthname, $day ) = ( $text =~ /^\s*<div class="floatLeft">(\S+),\s+(\S+)\.\s+(\d+)<\/div>$/i );

  my $year = DateTime->today->year;

  my $month = MonthNumber( $monthname, "en" );

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseShow
{
  my( $text ) = @_;

  # the show is in format '1800- Premiere: World Series Gold: WSOP 05: Pot Limit Hold'em ($2K) (11/32)
  my( $hour, $min, $title ) = ( $text =~ /^(\d{2})(\d{2})-\s+(.*)$/ );

  return( $hour . ":" . $min, $title );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
