package NonameTV::Importer::Arte_util;

use strict;
use warnings;

=pod

Import data from xml files (result of Word2Xml). The parsing of the
data relies only on the text-content of the document, not on the
formatting.

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet File2Xml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::DataStore::Updater;
use NonameTV::Log qw/progress error/;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # set the version for version checking
    $VERSION     = 0.1;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/ImportFull/;
}
our @EXPORT_OK;



# States
use constant {
  ST_START      => 0,
  ST_FDATE      => 1,   # Found date
  ST_FHEAD      => 2,   # Found head with starttime and title
  ST_FSUBINFO   => 3,   # Found sub info
  ST_FDESCSHORT => 4,   # Found short description
  ST_FDESCLONG  => 5,   # After long description
  ST_FADDINFO   => 6,   # After additional info
};

# Import files that contain full programming details,
# usually for an entire month.
# $doc is an XML::LibXML::Document object.
sub ImportFull
{
  my( $filename, $doc, $chd, $dsh ) = @_;
  my $have_batch;
  
  # Find all div-entries.
  my $ns = $doc->find( "//div" );
print "$doc\n==================================\n";
  
  if( $ns->size() == 0 )
  {
    error( "Arte: $chd->{xmltvid}: No programme entries found in $filename" );
    return;
  }

  if ($filename =~ m/.*\.doc/) {
    progress( "Arte: $chd->{xmltvid}: Processing $filename" );
    $have_batch = 0;
  } else {
    progress ("Arte: processing batch");
    $have_batch = 1;
  }

  my $date;
  my $currdate = "x";
  my $time;
  my $title;
  my $subinfo;
  my $shortdesc;
  my $longdesc;
  my $addinfo;

  my $state = ST_START;
  
  foreach my $div ($ns->get_nodelist)
  {

    # Ignore English titles in National Geographic.
    next if $div->findvalue( '@name' ) =~ /title in english/i;

    my( $text ) = norm( $div->findvalue( './/text()' ) );
    next if $text eq "";

print "$text\n";

    my $type;

    if( isDate( $text ) ){

      $date = ParseDate( $text );
      if( not defined $date ) {
	error( "Arte: $chd->{xmltvid}: $filename Invalid date $text" );
      }

      if( $date ne $currdate ) {

        if( $currdate ne "x" ) {
          if ($have_batch == 0) {
            $dsh->EndBatch( 1 );
          }
        }

        if ($have_batch == 0) {
          my $batch_id = $chd->{xmltvid} . "_" . $date;
          $dsh->StartBatch( $batch_id , $chd->{id} );
        }
        $dsh->StartDate( $date , "05:00" );
        $currdate = $date;

        progress("Arte: $chd->{xmltvid}: Date is: $date");

        $state = ST_FDATE;
      }

    } elsif( isTitle( $text ) ){

      # start of a new programme, write out last one and go ahead

      $state = ST_FHEAD;

    } elsif( isSubTitle( $text ) ){

      $state = ST_FSUBINFO;

    } elsif( $text =~ /^\[Kurz\]$/i ){

      $state = ST_FDESCSHORT;

    } elsif( $text =~ /^\[Lang\]$/i ){

      $state = ST_FDESCLONG;

    } elsif( $text =~ /^\[Zusatzinfo\]$/i ){

      $state = ST_FADDINFO;

    }

    # did we collect one full programme?
    if( ( $state eq ST_FDATE or $state eq ST_FHEAD ) and $time and $title and ( $subinfo or $longdesc ) ){

      my $aspect = undef;
      if( $title =~ /16:9/ ){
        $aspect = "16:9";
      }

      my $stereo = undef;
      if( $title =~ /stereo/i ){
        $stereo = "stereo";
      }

      my $quality;
      my ($subtitle, $genre, $directors, $actors);
      if ( defined ($subinfo)) {
      if( $subinfo =~ /Dieses Programm wurde in HD produziert/ ){
        $quality = "HDTV";
      }
      ( $subtitle, $genre, $directors, $actors ) = ParseExtraInfo( $subinfo );
     }

     $title =~ s/stereo.*$//i;
     $title =~ s/16:9.*$//i;

      $shortdesc =~ s/^\[Kurz\]// if $shortdesc;
      $longdesc =~ s/^\[Lang\]// if $longdesc;

      progress( "Arte: $chd->{xmltvid}: $time - $title" );

      my $ce = {
        channel_id => $chd->{id},
        title => $title,
        start_time => $time,
      };

      $ce->{subtitle} = $subtitle if $subtitle;
      $ce->{description} = $longdesc if $longdesc;
      $ce->{directors} = $directors if $directors;
      $ce->{actors} = $actors if $actors;
      $ce->{aspect} = $aspect if $aspect;
      $ce->{quality} = $quality if $quality;
      $ce->{stereo} = $stereo if $stereo;

      $dsh->AddProgramme( $ce );

      $time = undef;
      $title = undef;
      $subinfo = undef;
      $shortdesc = undef;
      $longdesc = undef;
      $addinfo = undef;
    }

    # after subinfo line there comes
    # some text with information about the program
    if ( $state eq ST_FHEAD ) {
      ( $time, $title ) = ParseTitle( $text );
    } elsif( $state eq ST_FSUBINFO ){
      $subinfo .= $text . "\n";
    } elsif( $state eq ST_FDESCSHORT ){
      $shortdesc .= $text . "\n";
    } elsif( $state eq ST_FDESCLONG ){
      $longdesc .= $text . "\n";
    } elsif( $state eq ST_FADDINFO ){
      $addinfo .= $text . "\n";
    }
  }
 
  if ($have_batch == 0) {
    $dsh->EndBatch( 1 );
  }

  return;
}

sub isDate {
  my ( $text ) = @_;

print "isDate: >$text<\n";

  # format 'Samstag, 21.11.2009'
  if( $text =~ /^(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag),\s+\d+\.\d+\.\d+$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my( $text ) = @_;

  my( $weekday, $day, $month, $year );

  # try 'Sunday 1 June 2008'
  if( $text =~ /^(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag),\s+\d+\.\d+\.\d+$/i ){
    ( $weekday, $day, $month, $year ) = ( $text =~ /^(\S+),\s+(\d+)\.(\d+)\.(\d+)$/ );
  }

#print "WDAY: >$weekday<\n";
#print "DAY : >$day<\n";
#print "MON : >$month<\n";
#print "YEAR: >$year<\n";

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isTitle
{
  my( $text ) = @_;

  if( $text =~ /^\d\d:\d\d\s+\S+/ ){
    return 1;
  }

  return 0;
}

sub ParseTitle
{
  my( $text ) = @_;

  my( $time, $rest ) = ( $text =~ /^(\d+:\d+)\s+(.*)\s*$/ );

  return( $time, $rest );
}

sub isSubTitle
{
  my( $text ) = @_;

  if( $text =~ /^\[\d\d:\d\d\]\s+\S+/ ){
    return 1;
  }

  return 0;
}

sub ParseExtraInfo
{
  my( $text ) = @_;

#print "ParseExtraInfo >$text<\n";

  my( $subtitle, $genre, $directors, $actors, $aspect, $stereo );

  my @lines = split( /\n/, $text );
  foreach my $line ( @lines ){
#print "LINE $line\n";

    if( $line =~ /^\[\d\d:\d\d\]\s+\S+,\s*Wiederholung/i ){
      ( $genre ) = ($line =~ /^\[\d\d:\d\d\]\s+(\S+),\s*Wiederholung/i );
#print "GENRE $genre\n";
    }

    if( $line =~ /^Regie:\s*.*$/i ){
      ( $directors ) = ( $line =~ /^Regie:\s*(.*)$/i );
      $directors =~ s/;.*$//;
#print "DIRECTORS $directors\n";
    }

    if( $line =~ /^Mit:\s*.*$/i ){
      ( $actors ) = ( $line =~ /^Mit:\s*(.*)$/i );
#print "ACTORS $actors\n";
    }

    $aspect = "4:3";
    $aspect = "16:9" if( $line =~ /16:9/i );

    $stereo = "stereo" if( $line =~ /stereo/i );

  }

  return( $subtitle, $genre, $directors, $actors );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
