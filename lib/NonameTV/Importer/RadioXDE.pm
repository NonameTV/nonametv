package NonameTV::Importer::RadioXDE;

use strict;
use warnings;

=pod

Sample importer for http-based sources.
See xxx for instructions. 

=cut

use Encode qw/decode/;
use HTML::TableExtract;
use HTML::Parse;
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;

use NonameTV qw/Html2Xml/;
use NonameTV::DataStore::Helper;
use NonameTV::Importer::BaseOne;
use NonameTV::Log qw/d p w f/;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    if (!defined( $self->{UrlRoot} )) {
      $self->{UrlRoot} = 'http://www.radiox.de/media/scripts/woche/woche_show_week.php';
    }

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  # Only one url to look at and no error
  return ([$self->{UrlRoot}], undef);
}

sub FilterContent {
  my $self = shift;
  my( $gzcref, $chd ) = @_;
  my $cref;

  gunzip $gzcref => \$cref
    or die "gunzip failed: $GunzipError\n";

  # FIXME convert latin1/cp1252 to utf-8 to HTML
  # $cref = decode( 'windows-1252', $cref );

  # cut away frame around tables
  $cref =~ s|^.+\"0Woche\"> *(<table.+/table>)\n +</div></body>.*$|<html><body><div>$1</div></body></html>|s;

  # remove hyperlinks
  $cref =~ s|<a href[^>]+>||g;
  $cref =~ s|</a>||g;

  # turn &nbsp; into space
  $cref =~ s|&nbsp;| |g;

  # remove duplicate space
  $cref =~ s|[[:space:]]+| |g;

  # remove class and id
  $cref =~ s| class=\"((?!\").)*\"||g;
  $cref =~ s| id=\"((?!\").)*\"||g;
  $cref =~ s| target=\"((?!\").)*\"||g;

  my $doc = Html2Xml ($cref);
  $doc->setEncoding('utf-8');
  $cref = $doc->toStringHTML ();

  return( \$cref, undef);
}

sub ContentExtension {
  return 'html.gz';
}

sub FilteredExtension {
  return 'html';
}

sub trimX {
  my $theString = shift;
  if ($theString) {
    $theString =~ s|\[Tipp\]||g;
    $theString =~ s|\{Tipp\]||g;
    $theString =~ s|\(Wdh.\)||g;
    $theString =~ s|[[:space:]]+| |g;
    $theString =~ s/^\s+//;
    $theString =~ s/\s+$//;
    if ($theString eq '') {
      $theString = undef;
    }
  }

  return $theString;
}

sub ImportContent {
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my $te = HTML::TableExtract->new(
    keep_html => 0
  );

  $$cref = decode( 'utf-8', $$cref );
  $te->parse($$cref);

  my $table = $te->table(0,0+1);
  my @firstrow = $table->row(0);
  my $firstdate = $firstrow[1];

  # the first day is the monday of the week three weeks ago
  my $year = DateTime->now()->year();
  my $month = DateTime->now()->month();
  my $day = DateTime->now()->day();

  my $dt = DateTime->new( 
                          year  => $year,
                          month => $month,
                          day   => $day,
                          time_zone => 'Europe/Berlin'
                          );
  # subtract days since monday to get monday
  $dt->add (days => -($dt->day_of_week() - 1));

  $dt->add (days => - 3*7);


  $month = $dt->month();
  $year = $dt->year();
  $day = $dt->day();

  $dsh->StartDate ($year . '-' . $month . '-' . $day, '02:00');

  # check if we got the correct day now
  my ($firstday) = ( $firstdate =~ /[A-Z][a-z] (\d+)\./ );
  if( $day != $firstday ){
    f( sprintf( "expected day %d but got %d", $day, $firstday ) );
  }


  # loop over 11 weeks of programme tables
  # loop over this+8 weeks
  for (my $woche = 0; $woche <= 8; $woche++) {
    $table = $te->table (0, $woche+1);
    if( !defined( $table ) ){
      last;
    }
    my $dtgestern = $dt;

    # look over the seven columns/days
    for (my $tagspalte = 1; $tagspalte <= 7; $tagspalte++) {
      # get date
      my $heute = $table->row(0)->[$tagspalte];
      ($day) = ($heute =~ /[A-Z][a-z] (\d+)\./);
      my $dtheute = DateTime->new (year => $year, month => $month, day => $day, time_zone => 'Europe/Berlin');

      # is it the start of a new month?
      if (DateTime->compare ($dtheute, $dtgestern) < 0) {
        $dtheute->add (months => 1);
        $month = $dtheute->month();
        $year = $dtheute->year();

# FIXME DataStoreHelper don't really like jumps over into the new year!
        $dsh->StartDate ($year . '-' . $month . '-' . $day, '00:00');
      }

      # process programmes
      for (my $stunderow = 2; $stunderow <= $table->row_count(); $stunderow++) {
        my @programmerow = $table->row ($stunderow);
        my $start_time = $programmerow[0] . ':00';
        my @sendung = split ("\n", $programmerow[$tagspalte]);

        my ($title, $desc);
        for (my $i = 0; $i < @sendung; $i++) {
          if (!$title) {
            if (!($sendung[$i] =~ /^[[:space:]]*d?i?t?o?[[:space:]]*$/s)) {
              if ($sendung[$i] =~ /ab 8 Uhr:/) {
                $start_time = '08:00';
              } elsif ($sendung[$i] =~ /ab 08:00 Uhr:/) {
                $start_time = '08:00';
              } else {
                $title = $sendung[$i];
              }
            }
          } else {
            if (!$desc) {
              $desc = $sendung[$i];
            } else {
              $desc = $desc . " " . $sendung[$i];
            }
          }
        }
        # trim title
        $title = trimX ($title);

        if ($title) {
          d( "$start_time $title" );

          my $ce = {
            start_time => $start_time,
            title => $title
          };

          # trim description
          $desc = trimX ($desc);
          if ($desc) {
            if ($desc =~ /^show \d+:/) {
              my ($episode) = ($desc =~ /^show (\d+):/);
              $ce->{episode} = ' . ' . ($episode-1) . ' . ';
              $desc =~ s/^show \d+: //;
            } elsif ($desc =~ /^#\s*\d+$/) {
              my ($episode) = ($desc =~ /^#\s*(\d+)$/);
              $ce->{episode} = ' . ' . ($episode-1) . ' . ';
              $desc = undef;
            } elsif ($desc =~ /^\d+:/) {
              my ($episode) = ($desc =~ /^(\d+):/);
              if( $episode < 1800 ){
                $ce->{episode} = ' . ' . ($episode-1) . ' . ';
                $desc =~ s/^\d+://;
              }
            }
            if ($desc) {
              $ce->{description} = $desc;
            }
          }

          $dsh->AddProgramme ($ce);
        }
      }

      # update gestern
      $dtgestern = $dtheute;
    }
  }

  return 1;
}


1;
