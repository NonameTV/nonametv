package NonameTV::Importer::Motors;

use strict;
use warnings;

=pod

Import data from Excel files delivered via e-mail.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use Text::CSV;
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

  if( $file =~ /\.csv$/i ){
    $self->ImportCSV( $file, $chd );
  } elsif( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd );
  }

  return;
}


sub ImportXLS {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.xls$/i );
  progress( "Motors XLS: $xmltvid: Processing $file" );

  my %columns = ();
  my $date;
  my $currdate = undef;

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "Motors XLS: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # browse through rows
    for(my $iR = 1 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {


      # date - column 0 ('Date de diffusion')
      my $oWkC = $oWkS->{Cells}[$iR][0];
      if( $oWkC ){
        if( $date = ParseDate( $oWkC->Value ) ){

          $dsh->EndBatch( 1 ) if defined $currdate;

          my $batch_id = "${xmltvid}_" . $date;
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date , "05:00" );
          $currdate = $date;

          progress("Motors XLS: Date is $date");

          next;
        }
      }


      # time - column 1 ('Horaire')
      $oWkC = $oWkS->{Cells}[$iR][1];
      next if( ! $oWkC );
      my $time = $oWkC->Value if( $oWkC->Value );
      
      # Sometimes Motors somehow add 24:00:00 in the time field, that fucks the system up. 
      my ( $hour , $min ) = ( $time =~ /^(\d+):(\d+)/ );
      if($hour eq "24") {
      	$hour = "00";
      }
      
      $time = $hour.":".$min;


			# End

      # title - column 2 ('Titre du produit')
      $oWkC = $oWkS->{Cells}[$iR][2];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

      my ( $subtitle, $description );

      # subtitle - column 3 ('Titre de l'ésode')
      $subtitle = $oWkS->{Cells}[$iR][3]->Value if $oWkS->{Cells}[$iR][3];

      # description - column 4 ('PRESSE UK')
      $description = $oWkS->{Cells}[$iR][5]->Value if $oWkS->{Cells}[$iR][5];

      progress("Motors XLS: $xmltvid: $time - $title");

      my $ce = {
        channel_id => $channel_id,
        title => norm($title),
        start_time => $time,
      };

      $ce->{subtitle} = norm($subtitle) if $subtitle;
      $ce->{description} = norm($description) if $description;

      $dsh->AddProgramme( $ce );
    }
  }

  $dsh->EndBatch( 1 );

  return;
}

sub ImportCSV {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  return if( $file !~ /\.csv$/i );
  progress( "Motors CSV: $xmltvid: Processing $file" );

  my $date;
  my $currdate = "x";

  open my $CSVFILE, "<", $file or die $!;

  my $csv = Text::CSV->new( {
    sep_char => ';',
    allow_whitespace => 1,
    blank_is_undef => 1,
    binary => 1,
  } );

  # get the column names from the first line
  my @columns = $csv->column_names( $csv->getline( $CSVFILE ) );
#foreach my $cl (@columns) {
#print "$cl\n";
#}

  # main loop
  while( my $row = $csv->getline_hr( $CSVFILE ) ){

    # Date
    if( $row->{'Date de diffusion'} ){
      $date = ParseDate( $row->{'Date de diffusion'} );

      if( $date and ( $date ne $currdate ) ){

        if( $currdate ne "x" ) {
          $dsh->EndBatch( 1 );
        }

        my $batch_id = $xmltvid . "_" . $date;
        $dsh->StartBatch( $batch_id , $channel_id );
        $dsh->StartDate( $date , "07:00" );
        $currdate = $date;

        progress( "Motors CSV: $xmltvid: Date is $date" );
      }
    }

    # Time
    my $time = $row->{'Horaire'};
    next if not $time;
    next if ( $time !~ /^\d\d\:\d\d$/ );

    # Title
    my $title = $row->{'Titre du produit'};
    next if not $title;

    # Subtitle
    my $subtitle = $row->{"Titre de l'épisode"};

    # Description
    my $description = $row->{'PRESSE UK'};

    progress( "Tiji: $xmltvid: $time - $title" );

    my $ce = {
      channel_id => $channel_id,
      title => $title,
      start_time => $time,
    };

    $ce->{subtitle} = $subtitle if $subtitle;
    $ce->{description} = $description if $description;

    $dsh->AddProgramme( $ce );

  }

  $dsh->EndBatch( 1 );

  return;
}


sub ParseDate {
  my( $text ) = @_;

  return undef if( ! $text );

  # Format 'VENDREDI 27 FAVRIER   2009'
  if( $text =~ /\S+\s+\d\d\s\S+\s+\d\d\d\d/ ){

    my( $dayname, $day, $monthname, $year ) = ( $text =~ /(\S+)\s+(\d\d)\s(\S+)\s+(\d\d\d\d)/ );
#print "$dayname\n";
#print "$day\n";
#print "$monthname\n";
#print "$year\n";

    $year += 2000 if $year lt 100;

    my $month = MonthNumber( $monthname, 'fr' );
#print "$month\n";

    my $date = sprintf( "%04d-%02d-%02d", $year, $month, $day );
    return $date;
  }

  return undef;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
