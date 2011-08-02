package NonameTV::Importer::Mtve_mail;

use strict;
use warnings;

=pod
Importer for MTVNHD

The excel files is sent via mail

Every day is runned as a seperate batch.

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Spreadsheet::ParseExcel;

use NonameTV qw/norm/;
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
    error( "Mtve_mail: Unknown file format: $file" );
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
  
  progress( "Mtve_mail: $chd->{xmltvid}: Processing flat XLS $file" );

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  # main loop
  foreach my $oWkS (@{$oBook->{Worksheet}}) {
  	
		my $foundcolumns = 0;
		
    # browse through rows
    for(my $iR = 0 ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {


      if( not %columns ){
        # the column names are stored in the first row
        # so read them and store their column positions
        # for further findvalue() calls

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          if( $oWkS->{Cells}[$iR][$iC] ){
            $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;

						$columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Start/ );
						$columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Title/ );
          
          	
          
          	$columns{'Description'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Description/ );

            $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Start/ );
          }
        }
#foreach my $cl (%columns) {
#	print "$cl\n";
#}
        %columns = () if( $foundcolumns eq 0 );

        next;
      }



      # date & Time - column 1 ('Date')
      my $start = $self->create_dt( $oWkS->{Cells}[$iR][$columns{'Date'}]->Value );
      my $date = $start->ymd("-");
      next if( ! $date );
      my $time = $start->hms(":");

	  	# Startdate
      if( $date ne $currdate ) {
      	if( $currdate ne "x" ) {
					$dsh->EndBatch( 1 );
        }
      
      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("Mtve_mail: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" ); 
        $currdate = $date;
      }

      # title
      my $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );
      
      # Remove *** Premiere *** 
      $title =~ s/\*\*\* premiere\*\*\* //g; 
      $title =~ s/\*\*\* PREMIERE \*\*\* //g; 
      
      # Uppercase the first letter
      $title = ucfirst($title);
      
      # Replace and upstring
      $title =~ s/Hd/HD/;  #replace hd with HD

	  	# descr (column 7)
	  	my $desc = $oWkS->{Cells}[$iR][$columns{'Description'}]->Value if $oWkS->{Cells}[$iR][$columns{'Description'}];

			# empty last day array
     	undef @ces;

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
        description => norm( $desc ),
      };
      
      # Seperate :
      ( $ce->{subtitle} ) = ($ce->{title} =~ /:\s*(.+)$/);
  		$ce->{title} =~ s/:\s*(.+)//;
      

			progress("Mtve_mail: $chd->{xmltvid}: $time - $title");
      $dsh->AddProgramme( $ce );

			push( @ces , $ce );

    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  
  my( $year, $month, $day, $hour, $minute ) = 
      ($str =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+)$/ );

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'Europe/Stockholm',
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}


1;