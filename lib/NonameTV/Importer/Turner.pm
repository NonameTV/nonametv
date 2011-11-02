package NonameTV::Importer::Turner;

use strict;
use warnings;

=pod

Channels: Boomerang, TCM, Cartoon Network, CNN

Import data from Word or XLS files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Spreadsheet::ParseExcel;
#use Text::Capitalize qw/capitalize_title/;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;
  
  # use augment
  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.doc$/i ){
    $self->ImportDOC( $file, $channel_id, $xmltvid );
  } elsif( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $channel_id, $xmltvid );
  }

  return;
}

sub ImportDOC
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};

  return if( $file !~ /\.doc$/i );

  progress( "Turner DOC: $xmltvid: Processing $file" );
  
  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "Turner DOC: $xmltvid: $file: Failed to parse" );
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
    error( "Turner DOC: $xmltvid: $file: No divs found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );

#print ">$text<\n";

    if( isDate( $text ) ) { # the line with the date in format 'Friday 1st August 2008'

      $date = ParseDate( $text );

      if( $date ) {

        if( $date ne $currdate ) {

          if( $currdate ne "x" ){
            # save last day if we have it in memory
            FlushDayData( $xmltvid, $dsh , @ces );
            $dsh->EndBatch( 1 );
            @ces = ();
          }

          my $batch_id = "${xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date , "00:00" ); 
          $currdate = $date;

          progress("Turner DOC: $xmltvid: Date is $date");
        }
      }

      # empty last day array
      undef @ces;
      undef $description;

    } elsif( isShow( $text ) ) {

      my( $time, $title ) = ParseShow( $text );

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      # add the programme to the array
      # as we have to add description later
      push( @ces , $ce );

    } else {

        # the last element is the one to which
        # this description belongs to
        my $element = $ces[$#ces];

        $element->{description} .= $text;

    }
  }

  # save last day if we have it in memory
  FlushDayData( $xmltvid, $dsh , @ces );

  $dsh->EndBatch( 1 );
    
  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.xls$/i );

  progress( "Turner XLS: $xmltvid: Processing $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );
  if( not defined( $oBook ) ) {
    error( "Turner XLS: Failed to parse xls" );
    return;
  }

  my $date;
  my $currdate = "x";
  my @ces = ();

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++){

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    if( $oWkS->{Name} =~ /Header/ ){
      progress("Turner XLS: $xmltvid: skipping worksheet '$oWkS->{Name}'");
      next;
    }
    progress("Turner XLS: $xmltvid: processing worksheet '$oWkS->{Name}'");

    # the time is in the column 0
    # the columns from 1 to 7 are each for one day
    for(my $iC = 1 ; $iC <= 7  ; $iC++) {

      # get the date from row 1
      my $oWkC = $oWkS->{Cells}[1][$iC];
      next if( ! $oWkC );
      $date = ParseDateXLS( $oWkC->Value );
      next if( ! $date );

      if( $date ne $currdate ) {

        if( $currdate ne "x" ) {
          # save last day if we have it in memory
          FlushDayData( $xmltvid, $dsh , @ces );
          $dsh->EndBatch( 1 );
          @ces = ();
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("Turner XLS: $xmltvid: Date is: $date");
      }

      my $time;
      my $title = "x";
      my $description;

      # browse through the shows
      # starting at row 2
      for(my $iR = 2 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++){

        my $oWkC = $oWkS->{Cells}[$iR][$iC];
        next if( ! $oWkC );
        my $text = $oWkC->Value;

        if( isTimeAndTitle( $text ) ){

          # check if we have something
          # in the memory already
          if( $title ne "x" ){

						# Remove (UU) and so on
						$title =~ s/\(.*\)//g;

            my $ce = {
              channel_id   => $channel_id,
              start_time => $time,
              title => norm($title),
            };

            $ce->{description} = $description if $description;

            push( @ces , $ce );
            $description = "";
          }

          ( $time, $title ) = ParseTimeAndTitle( $text );

        } else {
          $description .= $text;
        }

      } # next row

    } # next column
  } # next sheet

  # save last day if we have it in memory
  FlushDayData( $xmltvid, $dsh , @ces );

  $dsh->EndBatch( 1 );
    
  return;
}

sub FlushDayData {
  my ( $xmltvid, $dsh , @data ) = @_;

    if( @data ){
      foreach my $element (@data) {

        progress("Turner: $xmltvid: $element->{start_time} - $element->{title}");

        $dsh->AddProgramme( $element );
      }
    }
}

sub isDate {
  my ( $text ) = @_;

  # format 'Friday 1st August 2008'
  if( $text =~ /^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+\d+\S*\s+\S+\s+\d+$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

  my( $dayname, $day, $monthname, $year ) = ( $text =~ /^(\S+)\s+(\d+)\S*\s+(\S+)\s+(\d+)$/ );

  my $month = MonthNumber( $monthname , 'en' );

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseDateXLS {
  my( $text ) = @_;

#print "ParseDateXLS: >$text<\n";

  return undef if ( ! $text );

  my( $month, $day, $year );

  if( $text =~ /^(\d{4})-(\d{2})-(\d{2})$/ ){ # format '2010-04-26'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $text =~ /^(\d+)-(\d+)-(\d+)$/ ){ # format '8-1-08'
    ( $month, $day, $year ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
  }

  $year += 2000 if( $year < 100 );

  return sprintf( '%04d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

  # format 'UK 19.35 / CET 20.35 / CAT 20.35 And the title is here'
  # or
  # UK Time 05.30 / CET 06.30 / CAT 06.30 Looney Tunes
  if( $text =~ /^UK\s+\S*\s*\d+\.\d+\s+\/\s+CET\s+\d+\.\d+\s+\/\s+CAT\s+\d+\.\d+\s+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $hour, $min, $title ) = ( $text =~ /^UK\s+\S*\s*\d+\.\d+\s+\/\s+CET\s+(\d+)\.(\d+)\s+\/\s+CAT\s+\d+\.\d+\s+(.*)/ );

  return( $hour . ":" . $min , $title );
}

sub isTimeAndTitle {
  my ( $text ) = @_;

  # format '09:10 The Addams Family'
  if( $text =~ /^\d{2}:\d{2}\s+\S+/ ){
    return 1;
  }

  return 0;
}

sub ParseTimeAndTitle {
  my( $text ) = @_;

  my( $hour, $min, $title ) = ( $text =~ /^(\d{2}):(\d{2})\s+(.*)$/ );

  return( $hour . ":" . $min , $title );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
