package NonameTV::Importer::TechnoBaseFM;

use strict;
use warnings;

=pod

Sample importer for http-based sources.
See xxx for instructions. 

=cut

use HTML::Entities;
use HTML::TableExtract;
use HTML::Parse;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;
use Unicode::String;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/p w f/;

use NonameTV qw/Html2Xml norm/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $xmltvid, $year, $month, $day ) = ( $objectname =~ /^(.+)_(\d+)-(\d+)-(\d+)$/ );


  # Day=0 today, Day=1 tomorrow etc. Yesterday = yesterday

  my $dt = DateTime->new( 
                          year  => $year,
                          month => $month,
                          day   => $day 
                          );

  my $today = DateTime->today( time_zone=>'local' );
  my $day_diff = $dt->subtract_datetime( $today )->delta_days;

  if ($day_diff == -1) {
    $day_diff = "yesterday";
  }
 
  my $url = "http://www.$xmltvid/showplan.php?day=$day_diff";

  # Only one url to look at and no error
  return ([$url], undef);
}

sub FilterContent {
  my $self = shift;
  my( $gzcref, $chd ) = @_;
  my $cref;

  gunzip $gzcref => \$cref
    or die "gunzip failed: $GunzipError\n";

  # FIXME convert latin1 to utf-8 to HTML
  $cref = Unicode::String::latin1 ($cref)->utf8 ();
  $cref = encode_entities ($cref, "\200-\377");

  $cref =~ s|^.+(<table width="100.+</table>)</div></div><div.+$|<html><body>$1</body></html>|s;

  return( \$cref, undef);
}

sub ContentExtension {
  return 'html.gz';
}

sub FilteredExtension {
  return 'html';
}


#
# 3 Zeilen pro Programm
#
# 00:00 - 15:00 # Host #
#
# <b>Title</b><br>
# Musikstyle: Stil<br>
#
# Gammel
#
sub ImportContent {
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my( $xmltvid, $year, $month, $day ) = ( $batch_id =~ /^(.+)_(\d+)-(\d+)-(\d+)$/ );

  my $ds = $self->{datastore};

  my $dt = DateTime->new( 
                          year  => $year,
                          month => $month,
                          day   => $day,
                          time_zone => 'Europe/Berlin'
                          );

  my $te = HTML::TableExtract->new(
    keep_html => 1
  );

  $te->parse($$cref);

  my $table = $te->table(0, 0);

  for (my $i = 0; $i < $table->row_count(); $i+=3) {
    my @row = $table->row($i+0);

    my ( $hour1, $minute1, $hour2, $minute2 ) = ( $row[0] =~ m|(\d+):(\d+) - (\d+):(\d+)| );
    my ( $dj ) = ( $row[1] =~ m|\d+\">(.+)</a>| );

    @row = $te->table(2,$i/3)->row(1);
    my ( $title ) = ( $row[1] =~ m|<b>(.*)</b><br>| );
    my ( $desc ) = ( $row[1] =~ m|(Musikstyle: .+)<br><br>| );
    my ( $moredesc ) = ( $row[1] =~ m|<br><br>(.*)$|s );

    if ($moredesc) {
      $moredesc =~ s|\s+| |gs;
      $moredesc =~ s|<.*?>||g;
      $moredesc = norm (decode_entities ($moredesc));
      $moredesc =~ s|\x{201e}|\"|g;
      if ($moredesc eq '') {
        $moredesc = undef;
      } else {
        $desc = $moredesc . "\n" . $desc;
      }
    }

    my $start = DateTime->new(
                          year  => $year,
                          month => $month,
                          day   => $day,
                          hour  => $hour1,
                          minute => $minute1,
                          time_zone => 'Europe/Berlin'
                          );

    my $end = DateTime->new(
                          year  => $year,
                          month => $month,
                          day   => $day,
                          hour  => $hour2,
                          minute => $minute2,
                          time_zone => 'Europe/Berlin'
                          );

    # program over midnight? expecting to start today and end tomorrow
    if (DateTime->compare ($start, $end) == 1) {
      $end->add(days => 1);
      # program longer then 12 hours? it's more likely that start/end are swapped
      my $duration = $end->subtract_datetime($start);
      my $maxduration = DateTime::Duration->new (hours => 12);
      if (DateTime::Duration->compare ($duration, $maxduration) == 1) {
        $end->add (days => -1);
      }
      $year = $end->year;
      $month = $end->month;
      $day = $end->day;
    }

    $start->set_time_zone ('UTC');
    $end->set_time_zone ('UTC');

    my $ce = {
        channel_id  => $chd->{id},
        start_time  => $start->ymd("-") . " " . $start->hms(":"),
        end_time    => $end->ymd("-") . " " . $end->hms(":"),
        title => $title,
        description => $desc,
        presenters => $dj
    };

    $ds->AddProgramme( $ce );
  }

  return 1;
}


1;
