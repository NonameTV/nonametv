package NonameTV::Importer::ZDFkultur;

use strict;
use warnings;

=pod

Importer for data from ZDFkultur. 
One file per channel and week downloaded from their site.
The downloaded file is in xml-format.
Same format as DreiSat.

=cut

use DateTime;

use NonameTV::Log qw/d progress w error/;

use NonameTV::Importer::DreiSat;

use base 'NonameTV::Importer::DreiSat';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );

  # get first day in the given batch
  my $first = DateTime->new( year=>$year, day => 4 );
  $first->add( days => $week * 7 - $first->day_of_week - 6 );
  # adjust first day by 2
  $first->add (days => -2);
  # get last day of programme week
  my $last = $first->clone() -> add (days => 6);

  my $lastday = $last->day().".".$last->month().".".$last->year();
  my $firstday = $first->day() . ".";
  if ($first->month() != $last->month()) {
    $firstday = $firstday . $first->month() . ".";
  }
  if ($first->year() != $last->year()) {
    $firstday = $firstday . $first->year();
  }

  my $url = sprintf( "http://pressetreff.zdf.de/Public/ZDFkultur-PD/%d.KW-%s-%s.xml", $week, $firstday, $lastday );
  my $firstdayother = $first->day().'.'.$first->month().'.';
  my $lastdayother = $last->day().'.'.$last->month();
  my $urlother = sprintf( "http://pressetreff.zdf.de/Public/ZDFkultur-PD/%d.KW-%s-%s.xml", $week, $firstdayother, $lastdayother );

  # and another format, same as the first with leading zeroes
  # http://pressetreff.zdf.de/Public/ZDFkultur-PD/1.KW-1.-7.01.2011.xml
  my $lastdaythird = sprintf( "%d.%02d.%d", $last->day(), $last->month(), $last->year() );
  my $urlthird = sprintf( "http://pressetreff.zdf.de/Public/ZDFkultur-PD/%d.KW-%s-%s.xml", $week, $firstday, $lastdaythird );

  # fourth format
  # http://pressetreff.zdf.de/Public/ZDFkultur-PD/9.KW-26.02.-4.03.2011.xml
  my $firstday4 = $first->day() . ".";
  if ($first->month() != $last->month()) {
    $firstday4 .= sprintf( "%02d.",  $first->month () );
  }
  if ($first->year() != $last->year()) {
    $firstday4 = $firstday4 . $first->year();
  }
  my $url4 = sprintf( "http://pressetreff.zdf.de/Public/ZDFkultur-PD/%d.KW-%s-%s-ZDFkultur.xml", $week, $firstday4, $lastdaythird );

  # http://pressetreff.zdf.de/Public/ZDFkultur-PD/23.KW-4.-10.06.2011-ZDFkultur.xml
  # http://pressetreff.zdf.de/Public/ZDFkultur-PD/24.KW-11.-17.06.2011-ZDFkultur.xml
  # http://pressetreff.zdf.de/Public/ZDFkultur-PD/25.KW-18.-24.06.2011-ZDFkultur.xml
  # http://pressetreff.zdf.de/Public/ZDFkultur-PD/26.KW-25.06.-1.07.2011-ZDFkultur.xml
  # http://pressetreff.zdf.de/Public/ZDFkultur-PD/27.KW-2.-08.07.2011-ZDFkultur.xml
  # http://pressetreff.zdf.de/Public/ZDFkultur-PD/28.KW-9.-15.07.2011-ZDFkultur.xml
  # http://pressetreff.zdf.de/Public/ZDFkultur-PD/29.KW-16.-22.07.2011-ZDFkultur.xml

  # fifth format 27.KW-2.-08.07.2011-ZDFkultur.xml
  my $lastdayfifth = sprintf( "%02d.%02d.%d", $last->day(), $last->month(), $last->year() );
  my $url5 = sprintf( "http://pressetreff.zdf.de/Public/ZDFkultur-PD/%d.KW-%s-%s-ZDFkultur.xml", $week, $firstday, $lastdayfifth );

  # http://pressetreff.zdf.de/Public/ZDFkultur-PD/35.KW-27.08.-2.09.2011.ZDFkultur.xml # notice .ZDFkultur instead of -ZDFkultur
  my $url6 = sprintf( "http://pressetreff.zdf.de/Public/ZDFkultur-PD/%d.KW-%s-%s.ZDFkultur.xml", $week, $firstday4, $lastdaythird );

  # like 5 but with PW instead of KW
  my $url7 = sprintf( "http://pressetreff.zdf.de/Public/ZDFkultur-PD/%d.PW-%s-%s-ZDFkultur.xml", $week, $firstday, $lastdayfifth );

  d( "ZDFkultur: fetching data from $url\nor $urlother\nor $urlthird\nor$url4" );

  return( [$url7, $url5, $url6, $url4, $urlthird, $url, $urlother], undef );
}

#
# weekly programs run sat-fri instead of mon-sun
#
sub BatchPeriods { 
  my $self = shift;
  my( $shortgrab ) = @_;

  my $start_dt = DateTime->today(time_zone => 'local' );

  my $maxweeks = $shortgrab ? $self->{MaxWeeksShort} : 
    $self->{MaxWeeks};

  my @periods;

  for( my $week=0; $week <= $maxweeks; $week++ ) {
    my $dt = $start_dt->clone->add( days => $week*7+2 );

    push @periods, $dt->week_year . '-' . $dt->week_number;
  }

  return @periods;
}


1;
