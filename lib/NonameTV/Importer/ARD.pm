package NonameTV::Importer::ARD;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail. The parsing of the
data relies only on the text-content of the document, not on the
formatting.

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet File2Xml norm MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::DataStore::Updater;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;
use base 'NonameTV::Importer::BaseFile';

use constant {
  ST_START => 1,
  ST_NEWSHOW => 2,
  ST_END => 3,
};

sub new 
{
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

#return if( $chd->{xmltvid} !~ /disceur\.tv\.gonix\.net/ );

  return if( $file !~ /\.doc$/i );

  my $doc = File2Xml( $file );

  if( not defined( $doc ) )
  {
    error( "ARD: $chd->{xmltvid} Failed to parse $file" );
    return;
  }

  $self->ImportFull( $file, $doc, $chd );
}


# Import files that contain full programming details,
# usually for an entire month.
# $doc is an XML::LibXML::Document object.
sub ImportFull
{
  my $self = shift;
  my( $filename, $doc, $chd ) = @_;
  
  my $dsh = $self->{datastorehelper};

  # Find all div-entries.
  my $ns = $doc->find( "//div" );
  if( $ns->size() == 0 )
  {
    error( "ARD: $chd->{xmltvid}: No programme entries found in $filename" );
    return;
  }
  
return if( $filename !~ /Pressedienst1310/i );

  progress( "ARD: $chd->{xmltvid}: Processing $filename" );

  my $docweek;
  my $docyear;
  my $docfday;
  my $docfmon;
  my $date;
  my $currdate = "x";

  my $time;
  my $title;
  my $subtitle;
  my $aspect;
  my $stereo;
  my $quality;
  my $description;
  my @ces;

  my $state = ST_START;

  foreach my $div ($ns->get_nodelist)
  {
    # Ignore English titles in National Geographic.
    next if $div->findvalue( '@name' ) =~ /title in english/i;

    my( $text ) = norm( $div->findvalue( './/text()' ) );
    next if $text eq "";

print "$text\n";

    # extract document week and year from the top of the document in format '12|2010'
    if( ! $docweek and ! $docyear and ( $text =~ /^\d\d.*\d\d\d\d$/i ) ){
      ( $docweek, $docyear ) = ( $text =~ /^(\d\d).*(\d\d\d\d)$/i );
      next;

    # extract document first day from the top of the document in format '20. Marz bis 26. Marz'
    } elsif( ! $docfday and ( $text =~ /^\d+\.\s+\S+\s+bis\s+\d+\.\s+\S+$/i ) ){
      ( $docfday, $docfmon ) = ( $text =~ /^(\d+)\.\s+(\S+)\s+bis\s+\d+\.\s+\S+$/i );
      my $month = MonthNumber( $docfmon, "de" );

      $date = sprintf( '%d-%02d-%02d', $docyear, $month, $docfday );

      my $batch_id = $chd->{xmltvid} . "_" . $date;
      $dsh->StartBatch( $batch_id , $chd->{id} );
      $dsh->StartDate( $date , "00:00" );
      $currdate = $date;

      progress("ARD: $chd->{xmltvid}: First date is: $date");
      next;

    }

    if( isNewShow( $text ) or isEnd( $text ) or isDate( $text ) ){
print "NOVi SHOW ===================================================\n";
      # check if we have to save something
      if( $title and $time ){

print "KRUMPIRA!!!!!!!!!!!\n";

        progress( "ARD: $chd->{xmltvid}: $time - $title" );

        my $ce = {
          channel_id => $chd->{id},
          title => $title,
          start_time => $time,
        };

        $ce->{subtitle} = $subtitle if $subtitle;
        $ce->{description} = $description if $description;
        $ce->{aspect} = $aspect if $aspect;
        $ce->{stereo} = $stereo if $stereo;
        $ce->{quality} = $quality if $quality;

        $dsh->AddProgramme( $ce );

        undef $time;
        undef $title;
        undef $subtitle;
        undef $aspect;
        undef $stereo;
        undef $quality;
        undef $description;
      }

      $state = ST_NEWSHOW;

      next;
    }

    if( $state eq ST_NEWSHOW and isDate( $text ) ){

      $date = ParseDate( $text );
      if( not defined $date ) {
	error( "ARD: $chd->{xmltvid}: $filename Invalid date $text" );
      }

      if( $date ne $currdate ) {

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batch_id , $chd->{id} );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("ARD: $chd->{xmltvid}: Date is: $date");

      }

    } elsif( $state eq ST_NEWSHOW and $text =~ /^\d+\.\d+$/ ){

      ( $time ) = ( $text =~ /^(\d+\.\d+)$/ );
      $time =~ s/\./:/;

    } elsif( $state eq ST_NEWSHOW ){

      if( ! $title ){

        if( $text =~ /.*[a-z][A-Z].*/ ){
          ( $title, $subtitle ) = ( $text =~ /^(.*[a-z])([A-Z].*)$/ );
        } elsif( $text =~ /.*[a-z][1-9].*/ ){
          ( $title, $subtitle ) = ( $text =~ /^(.*[a-z])([1-9].*)$/ );
        } else {
          $title = $text;
          $subtitle = "";
        }

print "TITLE $title\n";
print "SUBTITLE $subtitle\n";

      } elsif( $text =~ /Stereo/ ){
        $stereo = "stereo";
      } elsif( $text =~ /16:9/ ){
        $aspect = "16:9";
      } elsif( $text =~ /High Definition/ ){
        $quality = "HDTV";
      } else {
        $description = $text;
      }

    }

  }

  $dsh->EndBatch( 1 );

  return;
}

sub isDate {
  my ( $text ) = @_;

#print "isDate: >$text<\n";

  # format 'Sonntag, 21. Mä 2010'
  if( $text =~ /^(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag),\s*\d+\.\s+\S+\s+\d+$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my( $text ) = @_;

  my( $weekday, $day, $monthname, $month, $year );

  # try 'Sunday 1 June 2008'
  if( $text =~ /^(Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag),\s*\d+\.\s+\S+\s+\d+$/i ){
    ( $weekday, $day, $monthname, $year ) = ( $text =~ /^(\S+),\s*(\d+)\.\s+(\S+)\s+(\d+)$/i );
  }

  $month = MonthNumber( $monthname, "de" );

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isNewShow
{
  my( $text ) = @_;

  if( $text =~ /^(BR|WDR|SWR|ARD|MDR|HR|RBB|NDR|ZDF|SRi)/ ){
    return 1;
  }

  return 0;
}

sub isEnd
{
  my( $text ) = @_;

  if( $text =~ /^Stand: \d+\.\d+\.\d+$/ or $text =~ /^Programmwoche \d+ \/ \d+$/ ){
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
