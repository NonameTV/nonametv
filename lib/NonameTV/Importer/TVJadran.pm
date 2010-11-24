package NonameTV::Importer::TVJadran;

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
#use Text::Capitalize qw/capitalize_title/;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

# File types
 use constant {
   FT_UNKNOWN    => 0,  # unknown
   FT_SCHEMAXLS  => 1,  # monthly schema in xls
   FT_SCHEMADOC  => 2,  # monthly schema in doc
   FT_SCHEDULE   => 3,  # daily schedule in doc
   FT_TEXT       => 4,  # schedule in text
};

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  $self->{grabber_name} = "TVJadran";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

#return if ( $file !~ /20090521222410-noname/ );

  my $ft = CheckFileFormat( $file );

  if( $ft eq FT_SCHEMADOC ){
    $self->ImportSchemaDOC( $file, $channel_id, $xmltvid );
  } elsif( $ft eq FT_SCHEDULE ){
    $self->ImportSchedule( $file, $channel_id, $xmltvid );
  } elsif( $ft eq FT_TEXT ){
    $self->ImportTXT( $file, $channel_id, $xmltvid );
  } else {
    error( "TVJadran: $xmltvid: $ft file format of $file" );
  }

  return;
}

sub CheckFileFormat
{
  my( $file ) = @_;

  if( $file =~ /noname$/ ){
    return FT_TEXT;
  }

  # check if the file contains 'PROGRAMSKA SHEMA TELEVIZIJE JADRAN'
  my $doc = Wordfile2Xml( $file );
  if( not defined( $doc ) ) {
    error( "TVJadran $file: Failed to parse" );
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
    error( "TVJadran $file: No divs found." ) ;
    return;
  }

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

    return FT_SCHEMADOC if( $text =~ /^PROGRAMSKA SHEMA TELEVIZIJE JADRAN$/ );
    return FT_SCHEDULE if( $text =~ /^PROGRAM TELEVIZIJE JADRAN$/ );
  }

  return FT_UNKNOWN;
}

#
# import the file with the monthly schema
#
sub ImportSchemaDOC
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  $self->{fileerror} = 0;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  
  return if( $file !~ /\.doc$/i );

  progress( "TVJadran: $xmltvid: Processing schema $file" );

  my $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "TVJadran $xmltvid: $file: Failed to parse" );
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
    error( "TVJadran $xmltvid: $file: No divs found." ) ;
    return;
  }

  my @shows = ();
  my $dayno = 0;
  my $spreadweeks = 6;
  my( $dtstart, $firstdate, $lastdate );

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );
#print ">$text<\n";

    # the month should be extracted from the text in format 'OD 01.10.2008.godine'
    # or 'STUPA NA SNAGU:  01.10.2008.'
    if( ( $text =~ /^OD \d{2}\.\d{2}\.\d{4}\.godine$/i )
     or ( $text =~ /^STUPA NA SNAGU: \d{2}\.\d{2}\.\d{4}\.$/i ) ){

      ( $dtstart, $firstdate, $lastdate ) = ParsePeriod( $text );

    }

    # next day on dayname
    if( $text =~ /^ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja/i ){

      # find the index of the day in the week
      my @days = qw/PONEDJELJAK UTORAK SRIJEDA ČETVRTAK PETAK SUBOTA NEDJELJA/;
      for( my $i = 0; $i < scalar(@days); $i++ ){
        if( $text =~ /$days[$i]/ ){
          $dayno = $i;
        }
      }
    }

    # push all shows of the day to the array for this day
    if( isShow( $text ) ){

      my( $time, $title, $genre ) = ParseShow( $text );

      my $show = {
        start_time => $time,
        title => $title,
      };

      @{$shows[$dayno]} = () if not $shows[$dayno];
      push( @{$shows[$dayno]} , $show );

    }

  }

  # spread shows accross weeks
  if( $spreadweeks ){
    @shows = SpreadWeeks( $spreadweeks, @shows );
  }

  # flush data to database
  FlushData( $dsh, $dtstart, $firstdate, $lastdate, $channel_id, $xmltvid, @shows );

  return;
}

sub ParsePeriod {
  my ( $text ) = @_;

print ">$text<\n";

  my @days = qw/Monday Tuesday Wednesday Thursday Friday Saturday Sunday/;

  # format 'OD 01.10.2008.godine'
  my( $firstday, $month, $year );
  if( $text =~ /^OD \d{2}\.\d{2}\.\d{4}\.godine$/i ){
    ( $firstday, $month, $year ) = ( $text =~ /^OD (\d+)\.(\d+)\.(\d+)\.godine$/i );
  } elsif( $text =~ /^STUPA NA SNAGU: \d{2}\.\d{2}\.\d{4}\.$/i ){
    ( $firstday, $month, $year ) = ( $text =~ /^STUPA NA SNAGU: (\d{2})\.(\d{2})\.(\d{4})\.$/i );
  }

  if( not $month or not $year ){
    error("Error while parsing period from '$text'");
    return( undef, undef, undef );
  }

  my $firstdate = DateTime->new( year   => $year,
                                 month  => $month,
                                 day    => $firstday,
                                 hour   => 0,
                                 minute => 0,
                                 second => 0,
                                 time_zone => 'Europe/Zagreb',
  );

  # find the name of the first day of the month
  my $firstdayname = $firstdate->day_name;

  # find the name of the last day of the month
  my $lastdate = DateTime->last_day_of_month( year => $year, month => $month );

  # the schedules data is on weekly basis
  # find the offset, or how many days it spreads to previous month
  my $offset = -1;
  for( my $i = 0; $i < scalar(@days); $i++ ){
    if( $days[$i] eq $firstdayname ){
      $offset = $i;
    }
  }
  if( $offset eq -1 ){
    error("Can't determine day offset");
    return( undef, undef, undef );
  }
  # find the first date which can be covered by this schedule
  # we will skip later the dates not from the correct month
  my $dtstart = $firstdate->clone->subtract( days => $offset );

  return( $dtstart, $firstdate, $lastdate );
}

sub SpreadWeeks {
  my ( $spreadweeks, @shows ) = @_;

  for( my $w = 1; $w < $spreadweeks; $w++ ){
    for( my $d = 0; $d < 7; $d++ ){
      next if( ! $shows[$d] );
      my @tmpshows = @{$shows[$d]};
      @{$shows[ ( $w * 7 ) + $d ]} = @tmpshows;
    }
  }

  return @shows;
}

sub FlushData {
  my ( $dsh, $dtstart, $firstdate, $lastdate, $channel_id, $xmltvid, @shows ) = @_;

print "FlushData\n";

  my $date = $dtstart;
  my $currdate = "x";

  my $batch_id = "${xmltvid}_schema_" . $firstdate->ymd("-");
  $dsh->StartBatch( $batch_id, $channel_id );

  # run through the shows
  foreach my $dayshows ( @shows ) {

#    if( $date < $firstdate or $date > $lastdate ){
#      progress( "TVJadran: $xmltvid: Date " . $date->ymd("-") . " is outside of the month " . $firstdate->month_name . " -> skipping" );
#      $date->add( days => 1 );
#      next;
#    }

    progress( "TVJadran: $xmltvid: Date is " . $date->ymd("-") );

    if( $date ne $currdate ) {

      $dsh->StartDate( $date->ymd("-") , "06:00" );
      $currdate = $date->clone;

    }

    foreach my $s ( @{$dayshows} ) {

      progress( "TVJadran: $xmltvid: $s->{start_time} - $s->{title}" );

      my $ce = {
        channel_id => $channel_id,
        start_time => $s->{start_time},
        title => $s->{title},
      };

      $dsh->AddProgramme( $ce );

    } # next show in the day

    # increment the date
    $date->add( days => 1 );

  } # next day

  $dsh->EndBatch( 1 );

}

#
# import the file with the daily schedule
#
sub ImportSchedule
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  $self->{fileerror} = 0;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  
  return if( $file !~ /\.doc$/i );

  progress( "TVJadran: $xmltvid: Processing schedule $file" );
  
  my $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "TVJadran $xmltvid: $file: Failed to parse" );
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
    error( "TVJadran $xmltvid: $file: No divs found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

    if( isDate( $text ) ) { # the line with the date in format 'Friday 1st August 2008'

      $date = ParseDate( $text );

      if( $date ) {

        if( $date ne $currdate ) {

          if( $currdate ne "x" ){
            $dsh->EndBatch( 1 );
          }

          my $batch_id = "${xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date , "00:00" ); 
          $currdate = $date;
        }

        progress("TVJadran: $xmltvid: Date is $date");
      }

      # empty last day array
      undef @ces;
      undef $description;

    } elsif( isShow( $text ) ) {

      my( $time, $title, $genre ) = ParseShow( $text );

      progress("TVJadran: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'TVJadran', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      $dsh->AddProgramme( $ce );

    } else {
        # skip
    }
  }

  $dsh->EndBatch( 1 );
    
  return;
}

sub ImportTXT
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  progress( "TVJadran TXT: $xmltvid: Processing $file" );

  open(HTMLFILE, $file);
  my @lines = <HTMLFILE>;
  close(HTMLFILE);

  my $date;
  my $currdate = "x";

  foreach my $text (@lines){

    $text = norm( $text );
print ">$text<\n";

    if( isDate( $text ) ){

      $date = ParseDate( $text );

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("TVJadran TXT: $xmltvid: Date is: $date");
      }
    } elsif( $date and isShow( $text ) ) {

      my( $time, $title, $genre, $ep_no, $ep_se ) = ParseShow( $text );

      progress("TVJadran TXT: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'TVJadran', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      if( $ep_no and $ep_se ){
        $ce->{episode} = sprintf( "%d . %d .", $ep_se-1, $ep_no-1 );
      } elsif( $ep_no ){
        $ce->{episode} = sprintf( ". %d .", $ep_no-1 );
      }

      $dsh->AddProgramme( $ce );

    } else {
      #skip
    }
  }

  $dsh->EndBatch( 1 );

  return;
}

sub isDate {
  my ( $text ) = @_;

  # format 'ZA  PETAK  24.10.2008.'
  if( $text =~ /(ponedjeljak|utorak|srijeda|ČETVRTAK|petak|subota|nedjelja)\s+\d+\.\s*\d+\.\s*\d+\.*$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  my( $dayname, $day, $month, $year ) = ( $text =~ /(\S+)\s+(\d+)\.\s*(\d+)\.\s*(\d+)\.*$/ );

  $year += 2000 if $year lt 100;

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

#print "isShow >$text<\n";

  # format '15,30 Zap skola,  crtana serija  ( 3/52)'
  if( $text =~ /^\d+[\,|\:]\d+\s+\S+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

#print "ParseShow >$text<\n";

  my( $hour, $min, $title, $genre );

  ( $hour, $min, $title ) = ( $text =~ /^(\d+)[\,|\:](\d+)\s+(.*)$/ );

  if( $title =~ /\,\s/ ){
    ( $genre ) = ( $title =~ /\,\s*(.*)$/ );
    $title =~ s/\,.*//;
  }

  return( $hour . ":" . $min , $title , $genre );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
