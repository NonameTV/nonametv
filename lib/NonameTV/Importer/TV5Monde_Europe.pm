package NonameTV::Importer::TV5Monde_Europe;

use strict;
use warnings;

=pod
Importer for TV5Monde, Europe EPG.

The excel files is sent via mail

Every day is runned as a seperate batch.

=cut

use utf8;

use POSIX;
use DateTime;
use Spreadsheet::ParseExcel;

use NonameTV qw/norm AddCategory ParseDescCatSwe/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "TV5Monde: Unknown file format: $file" );
  }

  return;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";
  my @ces;
  
  progress( "TV5Monde: $chd->{xmltvid}: Processing flat XLS $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {
  	my $foundcolumns = 0;
  	# browse through rows
    for(my $iR = 5 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {
      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

						$columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Date/ );
						$columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Titre/ );
						$columns{'Time'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Horaire/ );
          
          	$columns{'Description'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Summary/ );

            $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Date/ );
          }
        }
#foreach my $cl (%columns) {
#	print "$cl\n";
#}
        %columns = () if( $foundcolumns eq 0 );

        next;
      }



      # date - column 0 ('Date')
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      $date = ParseDate( $oWkC->Value );
      next if( ! $date );

	  # Startdate
      if( $date ne $currdate ) {
      	if( $currdate ne "x" ) {
					$dsh->EndBatch( 1 );
        }
      
      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("TV5Monde: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" ); 
        $currdate = $date;
      }

	  	# time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Time'}];
      next if( ! $oWkC );
      my $time = ParseTime($oWkC->Value) if( $oWkC->Value );

      # title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );
      
      # genre (column 6)
	  	$oWkC = $oWkS->{Cells}[$iR][6];
      my $genre = $oWkC->Value;

	  	# descr (column 9)
	  	my $desc = $oWkS->{Cells}[$iR][$columns{'Description'}]->Value if $oWkS->{Cells}[$iR][$columns{'Description'}];

      

			# empty last day array
     	undef @ces;

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
        description => norm( $desc ),
      };
      
      # Get genre
			my($program_type, $category ) = $ds->LookupCat( 'TV5Monde', $genre );
			AddCategory( $ce, $program_type, $category );

			# Add
			progress("TV5Monde: $chd->{xmltvid}: $time - $title");
      $dsh->AddProgramme( $ce );

			push( @ces , $ce );

    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my ( $text ) = @_;

  my( $year, $day, $month );
  
  # Empty string
  unless( $text ) {
		return 0;
	}
	
	if($text eq "") {
		return 0;
	}
	
	if($text eq "Date") {
		return 0;
	}

  # format '2011-04-13'
  if( $text =~ /^\d{4}\-\d{2}\-\d{2}$/i ){
    ( $year, $month, $day ) = ( $text =~ /^(\d{4})\-(\d{2})\-(\d{2})$/i );

  # format '2011/05/16'
  } elsif( $text =~ /^\d{2}\/\d{2}\/\d{4}$/i ){
    ( $day, $month, $year ) = ( $text =~ /^(\d{2})\/(\d{2})\/(\d{4})$/i );
  } elsif( $text =~ /^(\d+)-Mai-(\d+)$/ ){
    ( $day, $year ) = ( $text =~ /^(\d+)-Mai-(\d+)$/ );
    $month = "05";
  } elsif( $text =~ /^(\d+)-Juin-(\d+)$/ ){
    ( $day, $year ) = ( $text =~ /^(\d+)-Juin-(\d+)$/ );
    $month = "06";
  } elsif( $text =~ /^(\d+)-Juillet-(\d+)$/ ){
    ( $day, $year ) = ( $text =~ /^(\d+)-Juillet-(\d+)$/ );
    $month = "07";
  } elsif( $text =~ /^(\d+)-Août-(\d+)$/ ){
    ( $day, $year ) = ( $text =~ /^(\d+)-Août-(\d+)$/ );
    $month = "08";
  }

  $year += 2000 if $year < 100;


return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub ParseTime {
  my( $text ) = @_;

  my( $hour , $min );

  if( $text =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  }

  return sprintf( "%02d:%02d", $hour, $min );
}

1;