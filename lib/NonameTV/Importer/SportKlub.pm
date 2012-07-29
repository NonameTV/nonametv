package NonameTV::Importer::SportKlub;

use strict;
use warnings;

=pod

channels: SportKlub, SportKlub Plus
country: Croatia

Import data from Excel-files delivered via e-mail.
Each file is for one week.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use Archive::Zip;
use Archive::Zip qw( :ERROR_CODES );
use File::Basename;
use Spreadsheet::ParseExcel;
use XML::LibXML;
use Encode qw/decode/;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV qw/Wordfile2Xml AddCategory norm/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

# File types
use constant {
  FT_UNKNOWN  => 0,  # unknown
  FT_FLATXLS  => 1,  # flat xls file
  FT_GRIDXLS  => 2,  # xls file with grid
};

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

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

return if ( $file !~ /\.doc/ );

  if( $file =~ /\.zip$/i ){
    #$self->UnzipArchive( $file, $chd );
    return;
  } elsif( $file =~ /\.doc$/i ){
    $self->ImportDoc( $file, $chd );
    return;
  } elsif( $file =~ /\.odt$/i ){
    return;
  }

  my $ft = CheckFileFormat( $file );

  if( $ft eq FT_FLATXLS ){
    $self->ImportFlatXLS( $file, $channel_id, $xmltvid );
  } elsif( $ft eq FT_GRIDXLS ){
    $self->ImportGridXLS( $file, $channel_id, $xmltvid );
  } else {
    error( "SportKlub: $xmltvid: Unknown file format of $file" );
  }

  return;
}

sub CheckFileFormat
{
  my( $file ) = @_;

  # Only process .xls files.
  return if( $file !~ /\.xls$/i );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );
  return FT_UNKNOWN if( ! $oBook );

  # the flat sheet file which is sent from Croatel
  # has multiple sheets and
  # column names in the 2nd row
  # check against the value in the 2nd column of 2nd row of the 1st sheet
  # the content of this column shoul be 'Satnica'
  if( $oBook->{SheetCount} gt 0 ){
    my $oWkS = $oBook->{Worksheet}[0];
    my $oWkC = $oWkS->{Cells}[1][1];
    if( $oWkC ){
      return FT_FLATXLS if( $oWkC->Value =~ /^Satnica$/ );
    }
  }

  # both SportKlub and SportKlub Play sometimes send
  # xls files with grid
  # which can differ from day to day or can
  # contain the schema for the whole period
  my $oWkS = $oBook->{Worksheet}[0];
  my $oWkC = $oWkS->{Cells}[0][0];
  if( $oWkC ){
    if( $oWkC->Value =~ /SportKlub.*EXCLUDING RUSSIA/ or $oWkC->Value =~ /SportKlub Play/ or $oWkC->Value =~ /Hungary/ ){
      return FT_GRIDXLS;
    }
  }

  return FT_UNKNOWN;
}

sub UnzipArchive {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

  # Only process .zip files.
  return if( $file !~ /\.zip$/i );

  progress( "History: $xmltvid: Processing $file" );

  # Unzip files
  progress( "History: $xmltvid: Extracting files from zip file $file" );

  my $dirname = dirname( $file );
  chdir $dirname;

  my $zip = Archive::Zip->new();
  unless ( $zip->read( $file ) == AZ_OK ) {
    error( "History: $xmltvid: Error while reading $file" );
  }

  my @members = $zip->memberNames();
  foreach my $member (@members) {
    progress( "History: $xmltvid: Extracting $member" );
    $zip->extractMemberWithoutPaths( $member );
  }

  my $res = $zip->Extract( -quiet );
  error( "History: $xmltvid: Error $res while extracting from $file" ) if ( $res );

  return;
}

sub ImportFlatXLS
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $currdate;
  my $today = DateTime->today();

  # Only process .xls files.
  return if $file !~  /\.xls$/i;

  progress( "SportKlub FlatXLS: $xmltvid: Processing $file" );

  $self->{fileerror} = 0;

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "SportKlub FlatXLS: $xmltvid: Processing worksheet: $oWkS->{Name}" );

    # The name of the sheet is the date in format DD.M.YYYY.
    my ( $date ) = ParseDate( $oWkS->{Name} );
    if( ! $date ){
      error( "SportKlub FlatXLS: $xmltvid: Invalid worksheet name: $oWkS->{Name} - skipping" );
      next;
    }

    if( defined $date ) {

      # skip the days in the past
      my $past = DateTime->compare( $date, $today );
      if( $past < 0 ){
        progress("SportKlub FlatXLS: $xmltvid: Skipping date $date");
        next;
      } else {
        progress("SportKlub FlatXLS: $xmltvid: Processing date $date");
      }
    }

    $dsh->EndBatch( 1 ) if defined $currdate;

    my $batch_id = "${xmltvid}_" . $date->ymd("-");
    $dsh->StartBatch( $batch_id, $channel_id );
    $dsh->StartDate( $date->ymd("-") , "05:00" );
    $currdate = $date;

    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # the show start time is in row1
print "R $iR\n";
my $oWkC = $oWkS->get_cell( $iR, 1 );
next unless $oWkC;
print "2\n";

print "Value       = ", $oWkC->unformated(),       "\n";



#      my $oWkC = $oWkS->{Cells}[$iR][1];
#      next if ( ! $oWkC );
#      next if ( ! $oWkC->Value );
#print "CELL " . $oWkC->value() . "\n";
print "3\n";
      my $showtime = ParseTime( $oWkC->Value );
print "TIME $showtime\n";
      next if( ! $showtime );

      # the show title is in row2
      $oWkC = $oWkS->{Cells}[$iR][2];
      next if not $oWkC;
      next if not $oWkC->Value;
      my $eventtitle = $oWkC->Value;
print "TITLE $eventtitle\n";

      # the show description is in row3
      $oWkC = $oWkS->{Cells}[$iR][3];
      my $descr;
      if( $oWkC ){
        $descr = $oWkC->Value;
      }

      my $starttime = create_dt( $date , $showtime );

      # the 'title' is sometimes empty
      # use description in that case
      my $title = $eventtitle || $descr;

      progress("SportKlub FlatXLS: $xmltvid: $starttime - $title");

      my $ce = {
        channel_id   => $channel_id,
        start_time => $starttime->hms(":"),
        title => norm($title),
      };

      $ce->{description} = $descr if $descr;

      $dsh->AddProgramme( $ce );

    } # next row

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ImportDoc
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.doc$/i );

  progress( "SportKlub DOC: $xmltvid: Processing $file" );

  my $doc;
  $doc = Wordfile2Xml( $file );

  if( not defined( $doc ) ) {
    error( "SportKlub DOC: $xmltvid: $file: Failed to parse" );
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
    error( "SportKlub DOC: $xmltvid: $file: No divs found." ) ;
    return;
  }

  my $currdate = "x";
  my $date = undef;
  my @ces;
  my $description;

  foreach my $div ($ns->get_nodelist) {

    my( $text ) = norm( $div->findvalue( '.' ) );
#print ">$text<\n";

    if( isDate( $text ) ) {

      $date = ParseDate( $text );
      $date = $date->ymd();

      if( $date ) {

        if( $date ne $currdate ) {

          if( $currdate ne "x" ){
            $dsh->EndBatch( 1 );
          }

          my $batch_id = "${xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date , "00:00" );
          $currdate = $date;

          progress("SportKlub DOC: $xmltvid: Date is $date");
        }
      }

    } elsif( isShow( $text ) ){

      my ( $time, $title ) = ParseShow( $text );
      next if( ! $time );
      next if( ! $title );


      #$title = decode( "iso-8859-2" , $title );

      progress("SportKlub DOC: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => $title,
      };

      $dsh->AddProgramme( $ce );

    } else {
        # skip
    }

  }

  $dsh->EndBatch( 1 );

  return;
}

sub isDate {
  my ( $text ) = @_;

#print ">$text<\n";

  # format 'Utorak, 1.12.'
  if( $text =~ /^(ponedjeljak|ponedeljak|utorak|srijeda|sreda|Četvrtak|petak|subota|nedjelja|nedelja),\s*\d+\.\s*\d+\.*$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  $dinfo =~ s/[ ]//g;

  my( $dayname, $day, $month, $year );

  if( $dinfo =~ /(\d+)\.(\d+)\.(\d+)/ ){

    ( $day, $month, $year ) = ( $dinfo =~ /(\d+)\.(\d+)\.(\d+)/ );

    if( ! $day or ! $month or ! $year ){
      return undef;
    }

  } elsif( $dinfo =~ /^(ponedjeljak|ponedeljak|utorak|srijeda|sreda|Četvrtak|petak|subota|nedjelja|nedelja),\s*\d+\.\s*\d+\.*$/i ){

    ( $dayname, $day, $month ) = ( $dinfo =~ /^(ponedjeljak|ponedeljak|utorak|srijeda|sreda|Četvrtak|petak|subota|nedjelja|nedelja),\s*(\d+)\.\s*(\d+)\.*$/i );
    $year = DateTime->today->year();
  }

  # there is an error in the file, so fix it
  $year = 2008 if( $year eq 3008 );

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/Zagreb',
  );

  return $dt;
}

sub isShow {
  my ( $text ) = @_;

  if( $text =~ /^\d+[\.|:]\d+[-|\/]\d+\.\d+\s+\S+/i ){ # format '15.45/16.45 ATP Masters London, pregled turnira'
    return 1;
  } elsif( $text =~ /^\d+[\.|:]\d+\s+\S+/i ){ # format '04:00 Championship: TBA'
    return 1;
  }

  return 0;
}

sub ParseShow
{
  my ( $text ) = @_;

  my( $time, $title );

  if( $text =~ /^\d+[\.|:]\d+[-|\/]\d+\.\d+\s+\S+/i ){ # format '15.45/16.45 ATP Masters London, pregled turnira'
    ( $time, $title ) = ( $text =~ /^(\d+[\.|:]\d+)[-|\/]\d+\.\d+\s+(.*)/i );
  } elsif( $text =~ /^\d+[\.|:]\d+\s+\S+/i ){ # format '04:00 Championship: TBA'
    ( $time, $title ) = ( $text =~ /^(\d+[\.|:]\d+)\s+(.*)/i );
  }

  $time =~ s/\./:/g;

  return( $time, $title );
}

sub ParseTime
{
  my ( $text ) = @_;

  return 0;
}

sub create_dt
{
  my ( $dat , $tim ) = @_;

  my( $hr, $mn ) = ( $tim =~ /^(\d+)\:(\d+)$/ );

  my $dt = $dat->clone()->add( hours => $hr , minutes => $mn );

  if( $hr < 5 ){
    $dt->add( days => 1 );
  }

  return( $dt );
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
