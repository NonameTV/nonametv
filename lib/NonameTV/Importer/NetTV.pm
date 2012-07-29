package NonameTV::Importer::NetTV;

use strict;
use warnings;

=pod

Import data from Excel-files delivered via e-mail.
Each file is for one week.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV qw/AddCategory norm/;
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

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls files
  return if $file !~  /\.xls$/i;
#return if $file !~  /18\.10/i;

  progress( "NetTV: Processing $file" );
  
  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  my $date;

  my %columns = ();
  my $kada;
  my $batch_id;
  my $currdate = "x";
  my( $day, $month , $year , $hour , $min );
  my( $title, $premiere );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    # process only the sheet with the name PPxle
    #next if ( $oWkS->{Name} !~ /PPxle/ );

    progress( "NetTV: Processing worksheet: $oWkS->{Name}" );

    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # get the names of the columns from the 1st row
      if( not %columns ){
        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {

          next if( ! $oWkS->{Cells}[$iR][$iC] );
          next if( ! $oWkS->{Cells}[$iR][$iC]->Value );

          $columns{norm($oWkS->{Cells}[$iR][$iC]->Value)} = $iC;

          # columns alternate names
          $columns{'DATE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /(ponedjeljak|utorak|srijeda|cetvrtak|petak|subota|nedjelja)/i );
          $columns{'TIME'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^VRIJEME$/i );
          $columns{'TITLE'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^IME EMISIJE$/i );
        }
#foreach my $col (%columns) {
#print ">$col<\n";
#}
	if( ! $columns{'DATE'} and ! $columns{'TIME'} and ! $columns{'TIME'} ){
          %columns = ();
        }
        next if %columns;
      }

      # Date
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'DATE'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );

      if( isDate( $oWkC->Value ) ){

        $date = ParseDate( $oWkC->Value );
        next if( ! $date );

        if( $date ne $currdate ) {
          if( $currdate ne "x" ) {
            $dsh->EndBatch( 1 );
          }

          my $batch_id = $xmltvid . "_" . $date;
          $dsh->StartBatch( $batch_id , $channel_id );
          $dsh->StartDate( $date , "06:00" );
          $currdate = $date;

          progress("NetTV FLAT: $chd->{xmltvid}: Date is: $date");
          next;
        }

      }

      # time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'TIME'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = $oWkC->Value;
      next if( $time !~ /^\d\d\.\d\d$/ );
      $time =~ s/\./:/;

      # Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'TITLE'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $title = $oWkC->Value;
      next if( ! $title );

      # Genre
      $oWkC = $oWkS->{Cells}[$iR][2];
      my $genre = $oWkC->Value if( $oWkC and $oWkC->Value );

      # Episode
      $oWkC = $oWkS->{Cells}[$iR][3];
      my $episode = $oWkC->Value if( $oWkC and $oWkC->Value );

      # Premiere
      $oWkC = $oWkS->{Cells}[$iR][4];
      my $premiere = $oWkC->Value if( $oWkC and $oWkC->Value );

      progress( "NetTV: $xmltvid: $time - $title" );

      my $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => $title,
      };

      # episode number
      my $ep = undef;
      if( $episode ){
         if( $episode =~ /^\d+\/\d+$/ ){
           my( $ep_nr, $ep_se ) = ( $episode =~ /(\d+)\/(\d+)/ );
           $ep = sprintf( "%d . %d .", $ep_se-1, $ep_nr-1 );
         } elsif( $episode =~ /^\d+$/ ){
           $ep = sprintf( ". %d .", $episode-1 );
         }
      }

      if( defined( $ep ) and ($ep =~ /\S/) ){
        $ce->{episode} = norm($ep);
        $ce->{program_type} = 'series';
      }

      if( $genre ){
        my( $program_type, $category ) = $ds->LookupCat( "NetTV", $genre );
        AddCategory( $ce, $program_type, $category );
      }

      $dsh->AddProgramme( $ce );

      $hour = undef;

    } # next row (next show)

    $dsh->EndBatch( 1 );

  } # next worksheet

  return;
}

sub isDate
{
  my( $text ) = @_;

#print ">$text<\n";

  if( $text =~ /^\d+\.\d+\.\d+$/ ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my( $text ) = @_;

#print ">$text<\n";

  my( $day, $month, $year );

  if( $text =~ /^\d+\.\d+\.\d+$/ ){
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\.(\d+)\.(\d+)$/ );
  }

  $year += 2000 if $year < 100;

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
