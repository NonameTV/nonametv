package NonameTV::Importer::FOX;

use strict;
use warnings;

=pod

Import data from Xls or Xml files delivered via e-mail.  Each
day is handled as a separate batch.

Features:

=cut

use utf8;

use DateTime;
use Encode qw/encode decode/;
use XML::LibXML;
use Spreadsheet::ParseExcel;
use Archive::Zip;
use Data::Dumper;
use File::Temp qw/tempfile/;

use NonameTV qw/norm AddCategory MonthNumber/;
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

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $channel_id, $channel_xmltvid );
  } elsif( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $channel_id, $channel_xmltvid );
  }

  return;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $channel_id, $channel_xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # there is no date information in the document
  # the first and last dates are known from the file name
  # which is in format 'FOX Crime schedule 28 Apr - 04 May CRO.xml'
  # as each day is in one worksheet, other days are
  # calculated as the offset from the first one
  my $dayoff = 0;
  my $year = DateTime->today->year();

  progress( "FOX XML: $channel_xmltvid: Processing XML $file" );
  
  my( $month, $firstday ) = ExtractDate( $file );
  if( not defined $firstday ) {
    error( "FOX XML: $file: Unable to extract date from file name" );
    next;
  }

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "FOX XML: $file: Failed to parse xml" );
    return;
  }
  my $wksheets = $doc->findnodes( "//ss:Worksheet" );
  
  if( $wksheets->size() == 0 ) {
    error( "FOX XML: $file: No worksheets found" ) ;
    return;
  }

  my $batch_id;

  my $currdate = "x";
  my $column;

  # find the rows in the worksheet
  foreach my $wks ($wksheets->get_nodelist) {

    # the name of the worksheet
    my $dayname = $wks->getAttribute('ss:Name');
    progress("FOX XML: $channel_xmltvid: processing worksheet named '$dayname'");

    # the path should point exactly to one worksheet
    my $rows = $wks->findnodes( ".//ss:Row" );
  
    if( $rows->size() == 0 ) {
      error( "FOX XML: $channel_xmltvid: No Rows found in worksheet '$dayname'" ) ;
      return;
    }

    foreach my $row ($rows->get_nodelist) {

      # the column names are stored in the first row
      # so read them and store their column positions
      # for further findvalue() calls

      if( not defined( $column ) ) {
        my $cells = $row->findnodes( ".//ss:Cell" );
        my $i = 1;
        $column = {};
        foreach my $cell ($cells->get_nodelist) {
	  my $v = $cell->findvalue( "." );
	  $column->{$v} = "ss:Cell[$i]";
	  $i++;
        }

        # Check that we found the necessary columns.

        next;
      }

      my ($timeslot, $title, $crotitle, $genre);

      $timeslot = norm( $row->findvalue( $column->{'Time Slot'} ) );
      $title = norm( $row->findvalue( $column->{'EN Title'} ) );
      $crotitle = norm( $row->findvalue( $column->{'Croatian Title'} ) );
      $genre = norm( $row->findvalue( $column->{'Genre'} ) );

      if( ! $timeslot ){
        next;
      }

      my $starttime = create_dt( $year , $month , $firstday , $dayoff , $timeslot );

      my $date = $starttime->ymd('-');

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
	  $dsh->EndBatch( 1 );
        }

        my $batch_id = $channel_xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("FOX XML: $channel_xmltvid: Date is: $date");
      }

      if( not defined( $starttime ) ) {
        error( "Invalid start-time '$date' '$starttime'. Skipping." );
        next;
      }

      eval{ $crotitle = decode( "iso-8859-2", $crotitle ); };
      #$title = decode( "iso-8859-2", $title );

      progress( "FOX XML: $channel_xmltvid: $starttime - $title" );

      my $ce = {
        channel_id => $channel_id,
        title => $crotitle || $title,
        subtitle => $title,
        start_time => $starttime->hms(':'),
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'FOX', $genre );
        AddCategory( $ce, $program_type, $category );
      }
    
      $dsh->AddProgramme( $ce );

    } # next row

    $column = undef;
    $dayoff++;

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $channel_id, $channel_xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # there is no date information in the document
  # the first and last dates are known from the file name
  # which is in format 'FOX Crime schedule 28 Apr - 04 May CRO.xml'
  # as each day is in one worksheet, other days are
  # calculated as the offset from the first one
  my $dayoff = 0;
  my $year = DateTime->today->year();

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "FOX XLS: $channel_xmltvid: Processing XLS $file" );

  my( $month, $firstday ) = ExtractDate( $file );
  if( not defined $firstday ) {
    error( "FOX XLS: $file: Unable to extract date from file name" );
    next;
  }
  if( $month lt DateTime->today->month() ){
    $year += 1;
  }

#my @list = Encode->encodings();
#foreach my $e (@list) {
#print "$e\n";
#}

  my( $oBook, $oWkS, $oWkC );
  $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "FOX XLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("FOX XLS: $channel_xmltvid: processing worksheet named '$oWkS->{Name}'");

    # read the rows with data
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;
          }
        }
#foreach my $cl (%columns) {
#print "$cl\n";
#}
        next;
      }

      my ($timeslot, $title, $crotitle, $genre);

      # Time Slot
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Time Slot'}];
      next if( ! $oWkC );
      $timeslot = $oWkC->Value;

      # EN Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'EN Title'}];
      next if( ! $oWkC );
      $title = $oWkC->Value;

      # Croatian Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Croatian Title'}];
      next if( ! $oWkC );
      $crotitle = $oWkC->Value;

      # Genre
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Genre'}];
      next if( ! $oWkC );
      $genre = $oWkC->Value;

      if( ! $timeslot ){
        next;
      }

      my $starttime = create_dt( $year , $month , $firstday , $dayoff , $timeslot );

      my $date = $starttime->ymd('-');

      if( $date ne $currdate ) {
        if( $currdate ne "x" ) {
	  $dsh->EndBatch( 1 );
        }

        my $batch_id = $channel_xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("FOX XLS: $channel_xmltvid: Date is: $date");
      }

      if( not defined( $starttime ) ) {
        error( "Invalid start-time '$date' '$starttime'. Skipping." );
        next;
      }

#print "CROTITLE: $crotitle\n";
      #my $str = decode( "iso-8859-2", $crotitle );
#print "CROTITLE: $str\n";
      #$title = decode( "iso-8859-2", $title );

#print "CROTITLE: $crotitle\n";
#my $str = decode( "iso-8859-2", $crotitle );
#print "CROTITLE: $str\n";

      progress( "FOX XLS: $channel_xmltvid: $starttime - $title" );

      my $ce = {
        channel_id => $channel_id,
        title => $crotitle || $title,
        subtitle => $title,
        start_time => $starttime->hms(':'),
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'FOX', $genre );
        AddCategory( $ce, $program_type, $category );
      }
    
      $dsh->AddProgramme( $ce );

    } # next row

    %columns = ();
    $dayoff++;

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ExtractDate {
  my( $fn ) = @_;
  my $month;

#print "ExtractDate: >$fn<\n";

  # format of the file name could be
  # 'FOX Crime schedule 28 Apr - 04 May CRO.xml'
  # or
  # 'Life Programa 05 - 11 May 08 CRO.xml'

  my( $day , $monthname );

  # format: 'Programa 29 Sept - 05 Oct CRO.xls'
  if( $fn =~ m/.*\s+\d+\s+\S+\s*-\s*\d+\s+\S+.*/ ){
    ( $day , $monthname ) = ($fn =~ m/.*\s+(\d+)\s+(\S+)\s*-\s*\d+\s+\S+.*/ );

  # format: 'Programa 15 - 21 Sep 08 CRO.xls'
  } elsif( $fn =~ m/.*\s+\d+\s*-\s*\d+\s+\S+.*/ ){
    ( $day , $monthname ) = ($fn =~ m/.*\s+(\d+)\s*-\s*\d+\s+(\S{3}).*/ );

  # format: 'Programa Crime 18-24Jan CRO.xls'
  } elsif( $fn =~ m/.*\s+\d+\s*-\s*\d+\s*\S+.*/ ){
    ( $day , $monthname ) = ($fn =~ m/.*\s+(\d+)\s*-\s*\d+\s*(\S{3}).*/ );

  # format: 'Life Programa 24 DecCRO.xls'
  } elsif( $fn =~ m/.*\s+\d+\s*\S+.*/ ){
    ( $day , $monthname ) = ($fn =~ m/.*\s+(\d+)\s*(\S{3}).*/ );
  }

  # try the first format
  ###my( $day , $monthname ) = ($fn =~ m/\s(\d\d)\s(\S+)\s/ );
  
  # try the second if the first failed
  ###if( not defined( $monthname ) or ( $monthname eq '-' ) ) {
    ###( $day , $monthname ) = ($fn =~ m/\s(\d\d)\s\-\s\d\d\s(\S+)\s/ );
  ###}

  if( not defined( $day ) ) {
    return undef;
  }

  $month = MonthNumber( $monthname, 'en' );

  return ($month,$day);
}

sub create_dt {
  my ( $yr , $mn , $fd , $doff , $timeslot ) = @_;

  my( $hour, $minute );

  if( $timeslot =~ /^\d{4}-\d{2}-\d{2}T\d\d:\d\d:/ ){
    ( $hour, $minute ) = ( $timeslot =~ /^\d{4}-\d{2}-\d{2}T(\d\d):(\d\d):/ );
  } elsif( $timeslot =~ /^\d+:\d+/ ){
    ( $hour, $minute ) = ( $timeslot =~ /^(\d+):(\d+)/ );
  }

  my $dt = DateTime->new( year   => $yr,
                          month  => $mn,
                          day    => $fd,
                          hour   => $hour,
                          minute => $minute,
                          second => 0,
                          nanosecond => 0,
                          time_zone => 'Europe/Zagreb',
  );

  # add dayoffset number of days
  $dt->add( days => $doff );

  #$dt->set_time_zone( "UTC" );

  return $dt;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
