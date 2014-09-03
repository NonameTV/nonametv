package NonameTV::Importer::BBCWW_mail;

use strict;
use warnings;

=pod
Importer for BBC Worldwide

Channels: BBC Entertainment, BBC Knowledge, BBC HD, BBC Lifestyle, CBeebies

The excel files is downloaded from BBCWWChannels.com

Every month is runned as a seperate batch.

=cut

use utf8;

use POSIX;
use DateTime;
use XML::LibXML;
use Spreadsheet::ParseExcel;
use Data::Dumper;
use Spreadsheet::Read;

use Spreadsheet::XLSX;
use Spreadsheet::XLSX::Utility2007 qw(ExcelFmt ExcelLocaltime LocaltimeExcel);
use Spreadsheet::Read;

use Text::Iconv;
my $converter = Text::Iconv -> new ("utf-8", "windows-1251");

use NonameTV qw/norm MonthNumber/;
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
  
  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd );
  } else {
    error( "BBCWW: Unknown file format: $file" );
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
  my $oBook;

  if ( $file =~ /\.xlsx$/i ){ progress( "using .xlsx" );  $oBook = Spreadsheet::XLSX -> new ($file, $converter); }
  else { $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );  }

  # main loop
  #for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {
  foreach my $oWkS (@{$oBook->{Worksheet}}) {

	# main worksheet is "Schedule" if thats not the right one, jump to "Hungary"
	if( $oWkS->{Name} !~ /Schedule/ and $oWkS->{Name} !~ /Hungary/ and $oWkS->{Name} !~ /English/ ){
          progress( "BBCWW: $chd->{xmltvid}: Skipping worksheet: $oWkS->{Name}" );
          next;
    }

    #my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress( "BBCWW: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

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

			$columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /English Title/ );
			$columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Programme Title/ );
			$columns{'Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Programme \(English\)$/ );

            $columns{'ORGTitle'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /English Title/ );
			$columns{'ORGTitle'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /^Programme \(English\)$/ );

            $columns{'Episode Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /English Episode Title/ );
            $columns{'Episode Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode Name \(English\)/ );
            $columns{'Episode Title'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode Title/ );
          
            $columns{'Ser No'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Series No./ );
            $columns{'Ser No'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Series Number/ );
            $columns{'Ep No'}  = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode No./ );
            $columns{'Ep No'}  = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episode Number/ );
            $columns{'Eps'}    = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Episodes in/ );

            $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Synopsis./ );
            $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /English Synopsis/ );

            $columns{'Date'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Date/ and $oWkS->{Cells}[$iR][$iC]->Value !~ /EET/ );
            $columns{'Time'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Time/ and $oWkS->{Cells}[$iR][$iC]->Value !~ /EET/ ); # Dont set the time to EET
            $columns{'Time'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Time \(CET\/CEST\)/ );

            $columns{'Year'}      = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Production Year/ );
            $columns{'Director'}  = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Director/ );
            $columns{'Cast'}      = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Cast/ );
            $columns{'Presenter'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Presenter/ );

            # Swedish
			if($chd->{sched_lang} eq "sv") {
			    $columns{'Title'}    = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Programme \(Swedish\)/ );
			    $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Synopsis \(Swedish\)/ );
			}

			# Norwegian
            if($chd->{sched_lang} eq "no") {
                $columns{'Title'}    = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Programme \(Norwegian\)/ );
			    $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Synopsis \(Norwegian\)/ );
			}

			# Danish
            if($chd->{sched_lang} eq "da") {
                $columns{'Title'}    = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Programme \(Danish\)/ );
			    $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Synopsis \(Danish\)/ );
			}

			# Finnish
            if($chd->{sched_lang} eq "fi") {
                $columns{'Title'}    = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Programme \(Finnish\)/ );
			    $columns{'Synopsis'} = $iC if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Synopsis \(Finnish\)/ );
			}

            $foundcolumns = 1 if( $oWkS->{Cells}[$iR][$iC]->Value =~ /Date/ );
          }
        }

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
			# save last day if we have it in memory
		#	FlushDayData( $channel_xmltvid, $dsh , @ces );
			$dsh->EndBatch( 1 );
        }
      
      	my $batchid = $chd->{xmltvid} . "_" . $date;
        $dsh->StartBatch( $batchid , $chd->{id} );
        progress("BBCWW: $chd->{xmltvid}: Date is $date");
        $dsh->StartDate( $date , "00:00" ); 
        $currdate = $date;
      }

	  # time
	  $oWkC = $oWkS->{Cells}[$iR][$columns{'Time'}];
      next if( ! $oWkC );
      my $time = $oWkC->Value if( $oWkC->Value );
      $time =~ s/'//g;

      # title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Title'}];
      next if( ! $oWkC );
      my $title = $oWkC->Value if( $oWkC->Value );

	  # episode and season
      my $epino = $oWkS->{Cells}[$iR][$columns{'Ep No'}]->Value if $oWkS->{Cells}[$iR][$columns{'Ep No'}];
      my $seano = $oWkS->{Cells}[$iR][$columns{'Ser No'}]->Value if $oWkS->{Cells}[$iR][$columns{'Ser No'}];

	  # extra info
	  my $desc = $oWkS->{Cells}[$iR][$columns{'Synopsis'}]->Value if $oWkS->{Cells}[$iR][$columns{'Synopsis'}];
	  my $year = $oWkS->{Cells}[$iR][$columns{'Year'}]->Value if defined($columns{'Year'}) and $oWkS->{Cells}[$iR][$columns{'Year'}];

      progress("BBCWW: $chd->{xmltvid}: $time - $title");

      my $ce = {
        channel_id => $chd->{channel_id},
        title => norm( $title ),
        start_time => $time,
        description => norm( $desc ),
      };

	  # Extra
	  $ce->{subtitle}        = parse_person_list(norm($oWkS->{Cells}[$iR][$columns{'Episode Title'}]->Value)) if $oWkS->{Cells}[$iR][$columns{'Episode Title'}];
	  $ce->{actors}          = parse_person_list(norm($oWkS->{Cells}[$iR][$columns{'Cast'}]->Value))          if defined($columns{'Cast'}) and $oWkS->{Cells}[$iR][$columns{'Cast'}];
	  $ce->{directors}       = parse_person_list(norm($oWkS->{Cells}[$iR][$columns{'Director'}]->Value))      if defined($columns{'Director'}) and $oWkS->{Cells}[$iR][$columns{'Director'}];
	  $ce->{presenters}      = parse_person_list(norm($oWkS->{Cells}[$iR][$columns{'Presenter'}]->Value))     if defined($columns{'Presenter'}) and $oWkS->{Cells}[$iR][$columns{'Presenter'}];
      $ce->{production_date} = $year."-01-01" if defined($year) and $year ne "" and $year ne "0000";

      if( $epino ){
        if( $seano ){
          $ce->{episode} = sprintf( "%d . %d .", $seano-1, $epino-1 );
        } else {
          $ce->{episode} = sprintf( ". %d .", $epino-1 );
        }
      }

      # org title
      if(defined $columns{'ORGTitle'}) {
        $oWkC = $oWkS->{Cells}[$iR][$columns{'ORGTitle'}];
        my $title_org = $oWkC->Value if( $oWkC->Value );
        $ce->{original_title} = norm($title_org) if defined($title_org) and $ce->{title} ne norm($title_org) and norm($title_org) ne "";
      }


      $dsh->AddProgramme( $ce );

    } # next row
  } # next worksheet

	$dsh->EndBatch( 1 );

  return 1;
}

sub ParseDate {
  my( $text ) = @_;

  $text =~ s/^\s+//;

  my( $dayname, $day, $monthname, $year );
  my $month;

  if( $text =~ /^\d+-\d+-\d+$/ ) { # format '2011-07-01'
    ( $year, $month, $day ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
    $year += 2000 if $year lt 100;
  } elsif( $text =~ /^\d+\/\d+\/\d+$/ ) { # format '01/11/2008'
    ( $day, $month, $year ) = ( $text =~ /^(\d+)\/(\d+)\/(\d+)$/ );
    $year += 2000 if $year lt 100;
  }

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub parse_person_list
{
  my( $str ) = @_;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    s/^.*\s+-\s+//;
  }

  return join( ";", grep( /\S/, @persons ) );
}

1;
