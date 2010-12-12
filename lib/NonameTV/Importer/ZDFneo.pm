package NonameTV::Importer::ZDFneo;

use strict;
use warnings;

=pod

Importer for data from ZDFneo. 
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

  my $url = sprintf( "http://pressetreff.zdf.de/Public/ZDFneo-PD/%d.KW-%s-%s.xml", $week, $firstday, $lastday );
  my $firstdayother = $first->day().'.'.$first->month().'.';
  my $lastdayother = $last->day().'.'.$last->month();
  my $urlother = sprintf( "http://pressetreff.zdf.de/Public/ZDFneo-PD/%d.KW-%s-%s.xml", $week, $firstdayother, $lastdayother );

  # and another format, same as the first with leading zeroes
  # http://pressetreff.zdf.de/Public/ZDFneo-PD/1.KW-1.-7.01.2011.xml
  my $lastdaythird = sprintf( "%d.%02d.%d", $last->day(), $last->month(), $last->year() );
  my $urlthird = sprintf( "http://pressetreff.zdf.de/Public/ZDFneo-PD/%d.KW-%s-%s.xml", $week, $firstday, $lastdaythird );

  d( "ZDF: fetching data from $url\nor $urlother\nor $urlthird" );

  return( [$url, $urlother, $urlthird], undef );
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
