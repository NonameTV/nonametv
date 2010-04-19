package NonameTV::Importer::OSTV;

use strict;
use warnings;

=pod

Channels: Gradska TV Zadar

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Encode qw/decode/;
use File::Basename;
use Clone qw(clone);

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

my $lastday;

my @weekdays = qw/ponedjeljak utorak srijeda ČETVRTAK petak subota nedjelja/;

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

#return if( $file !~ /20090204-TV TJEDNI PROGRAM\.doc/i );

  return if( $file !~ /\.doc$/i );

  progress( "OSTV: $xmltvid: Processing $file" );

  my( $startdate, $enddate ) = ParsePeriod( $file );
print "SDATE $startdate\n";
print "EDATE $enddate\n";

  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "OSTV $xmltvid: $file: Failed to parse" );
    return;
  }

  my @nodes = $doc->findnodes( '//span[@style="text-transform:uppercase"]/text()' );
  foreach my $node (@nodes) {
    my $str = $node->getData();
    $node->setData( uc( $str ) );
  }
  
  # Find all paragraphs.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 ) {
    error( "OSTV $xmltvid: $file: No divs found." ) ;
    return;
  }

  my $date = undef;
  my @ces = {};
  my @weekces;
  my $weekday;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

print ">$text<\n";

    if( isDate( $text ) ) { # the line with the date in format 'Friday 1st August 2008'

      for( $weekday = 0 ; $weekday < scalar(@weekdays) ; $weekday++ ){

        if( $text =~ /$weekdays[$weekday]/i ){

          # save last saved day
          if( @ces ){
print "C @ces\n";
            @{$weekces[$weekday]} = @ces;
print "W @{$weekces[$weekday]}\n";
print "1\n";
foreach my $wc ( @weekces ){
  print "WC $wc\n";
}
            @ces = {};
print "2\n";
foreach my $wc ( @weekces ){
  print "WC $wc\n";
}
          }

          last;
        }
      }

      progress("OSTV: $xmltvid: Skupljam programe za dan $weekdays[$weekday]");

      # initialize day and week array
      $weekces[$weekday] = {};

    } elsif( isShow( $text ) ) {

      my( $time, $title, $genre, $episode ) = ParseShow( $text );
      #$title = decode( "iso-8859-2" , $title );

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => norm($title),
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'OSTV', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      if( $episode ){
        $ce->{episode} = sprintf( ". %d .", $episode-1 );
      }

      push( @ces , $ce );

    } else {
        # skip
    }
  }

  @weekces[$weekday] = clone( \@ces );
  @ces = {};

  $self->{weekces} = @weekces;

  $self->FlushData( $chd, $startdate, $enddate );

  return;
}

sub FlushData {
  my $self = shift;
  my( $chd, $sdt, $edt ) = @_;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};

  my @weekces = $self->{weekces};

  my $currdate = "x";

foreach my $wc ( @weekces ){
  print "WC $wc\n";
}

print "FlushData S $sdt\n";
print "FlushData E $edt\n";

  for( my $dt = $sdt ; $dt <= $edt ; $dt->add( days => 1 ) ){
print "FlushData D $dt\n";

    if( $dt ne $currdate ) {

      if( $currdate ne "x" ){
        $dsh->EndBatch( 1 );
      }

      my $batch_id = "${xmltvid}_" . $dt->ymd();
      $dsh->StartBatch( $batch_id, $channel_id );
      $dsh->StartDate( $dt->ymd("-") , "00:00" ); 
      $currdate = $dt->clone;

      progress("OSTV: $xmltvid: Date is " . $dt->ymd("-") . " (" . $dt->day_name . ")" );
    }

    my $weekday = $dt->day_of_week - 1;
    progress("OSTV: $xmltvid: " . $dt->day_name . " - " . $weekday );

    next if not $weekces[$weekday];

    foreach my $ce ( @{$weekces[$weekday]} ) {
print "FlushData CE $ce\n";

      next if not $ce;
      next if not $ce->{title};
      next if ( $ce->{start_time} !~ /^\d+:\d+$/ );

      progress("OSTV: $xmltvid: $ce->{start_time} - $ce->{title}");
      $dsh->AddProgramme( $ce );
    }

  }

  $dsh->EndBatch( 1 );
}

sub ParsePeriod {
  my ( $filename ) = @_;

  my( $sday, $smon, $syear );
  my( $eday, $emon, $eyear );

  # format: 'TV RASPORED  12.10.2009  -  31.05.2010..doc'
  if( $filename =~ /\d+\.\d+\.\d+\s*-\s*\d+\.\d+\.\d+/ ){
    ( $sday, $smon, $syear, $eday, $emon, $eyear ) = ( $filename =~ /(\d+)\.(\d+)\.(\d+)\s*-\s*(\d+)\.(\d+)\.(\d+)/ );
  }

  my $sdt = DateTime->new( year   => $syear,
                           month  => $smon,
                           day    => $sday,
                           hour   => 0,
                           minute => 0,
                           second => 0,
                           time_zone => 'Europe/Zagreb',
  );

  my $edt = DateTime->new( year   => $eyear,
                           month  => $emon,
                           day    => $eday,
                           hour   => 0,
                           minute => 0,
                           second => 0,
                           time_zone => 'Europe/Zagreb',
  );

  return( $sdt, $edt );
}

sub isDate {
  my ( $text ) = @_;

#print ">$text<\n";

  # format 'PONEDJELJAK'
  if( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja)\s*\,*$/i ){
    return 1;
  }

  # format 'PONEDJELJAK, 26.1.2009'
  if( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja)\,*\s+\d+\.\d+\.\d+$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text, $path ) = @_;

  my( $dayname, $day, $month, $year );

  # format 'PONEDJELJAK'
  if( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja)$/i ){

    my $filename = basename($path);

    my( $fy, $fm, $fd ) = ( $filename =~ /^(\d{4})(\d{2})(\d{2})/ );

    DateTime->DefaultLocale( "hr_HR" );

    my $dt;

    if( not defined $lastday ){
      $dt = DateTime->new( year   => $fy,
                           month  => $fm,
                           day    => $fd,
                           hour   => 0,
                           minute => 0,
                           second => 0,
                           time_zone => 'Europe/Zagreb',
      );

      # start from next day
      $dt->add( days => 1 );
    } else {
      $dt = $lastday;
    }

    while(1){

      if( $dt->day_name eq lc( $text ) ){
        $lastday = $dt;
        return sprintf( '%d-%02d-%02d', $dt->year, $dt->month, $dt->day );
      }

      $dt->add( days => 1 );
    }

  }

  # format 'PONEDJELJAK, 26.1.2009'
  if( $text =~ /^(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja)\,*\s+\d+\.\d+\.\d+$/i ){
    ( $dayname, $day, $month, $year ) = ( $text =~ /^(\S+)\,*\s+(\d+)\.(\d+)\.(\d+)$/i );
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

  # format '18.40 Pogled preko ramena, informativna emisija'
  if( $text =~ /^\d+\.\d+\s+\S+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $hour, $min, $title, $genre, $episode );

  if( $text =~ /\(\d+\)/ ){
    ( $episode ) = ( $text =~ /\((\d+)\)/ );
    $text =~ s/\(\d+\).*//;
  }

  if( $text =~ /\,.*/ ){
    ( $genre ) = ( $text =~ /\,\s*(.*)$/ );
    $text =~ s/\,.*//;
  }

  ( $hour, $min, $title ) = ( $text =~ /^(\d+)\.(\d+)\s+(.*)$/ );

  return( $hour . ":" . $min , $title , $genre , $episode );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
