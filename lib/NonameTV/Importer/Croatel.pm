package NonameTV::Importer::Croatel;

use strict;
use warnings;

=pod

channels: SportKlub, SportKlub2, DoQ
country: Croatia

Import data from Excel-files delivered via e-mail.
Each file is for one week.

Features:

=cut

use utf8;

use DateTime;
use Spreadsheet::ParseExcel;
use RTF::Tokenizer;
use DateTime::Format::Excel;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV qw/AddCategory norm/;

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

return if ( $file =~ /Croatian/i );
return if ( $file !~ /EPG/i );

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xls$/i ){
    $self->ImportXLS( $file, $chd );
  } elsif( $file =~ /\.rtf$/i ){
    #$self->ImportRTF( $file, $chd );
  }

  return;
}

sub ImportXLS {
  my $self = shift;
  my( $file, $chd ) = @_;

  my $currdate;
  my $today = DateTime->today();

  # Only process .xls files.
  return if $file !~  /\.xls$/i;

  progress( "Croatel: $chd->{xmltvid}: Processing $file" );

  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++) {

    my $oWkS = $oBook->{Worksheet}[$iSheet];

    progress( "Croatel: $chd->{xmltvid}: Processing worksheet: $oWkS->{Name}" );

    # The name of the sheet is the date in format DD.M.YYYY.
    my ( $date ) = ParseDate( $oWkS->{Name} );
    if( ! $date ){
      error( "Croatel: $chd->{xmltvid}: Invalid worksheet name: $oWkS->{Name} - skipping" );
      next;
    }

    if( defined $date ) {

      # skip the days in the past
      my $past = DateTime->compare( $date, $today );
      if( $past < 0 ){
        progress("Croatel: $chd->{xmltvid}: Skipping date " . $date->ymd("-") );
        next;
      }
    }

    $dsh->EndBatch( 1 ) if $currdate;

    my $batch_id = "${xmltvid}_" . $date->ymd("-");
    $dsh->StartBatch( $batch_id, $channel_id );
    $dsh->StartDate( $date->ymd("-") , "05:00" );
    $currdate = $date;

    progress("Croatel: $chd->{xmltvid}: Processing date " . $date->ymd("-") );

    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # the show start time is in row1
      my $oWkC = $oWkS->{Cells}[$iR][1];
      next if ( ! $oWkC );
      next if ( ! $oWkC->Value );
      my $celltime = $oWkC->Value;
      my $time;

      if ( $celltime =~ /^(\d+):(\d+)$/ ){

        my( $hours, $minutes ) = ( $celltime =~ /^(\d+):(\d+)$/ );
        $time = sprintf( '%02d:%02d', $hours, $minutes );

      } elsif ( $celltime =~ /^(\d+):(\d+):(\d+)$/ ){

        my( $hours, $minutes, $seconds ) = ( $celltime =~ /^(\d+):(\d+):(\d+)$/ );
        $time = sprintf( '%02d:%02d:%02d', $hours, $minutes, $seconds );

      } elsif ( $celltime =~ /^\d+/ ){


	my $secs = 86400 * $celltime;
        $secs = int($secs);

        my $hours = int( $secs / 3600 );
        my $minutes = int( ( $secs - ( $hours * 3600 ) ) / 60 );
        my $seconds = $secs - ( $hours * 3600 ) - $minutes * 60;

        $time = sprintf( '%02d:%02d:%02d', $hours, $minutes, $seconds );

      } else {
        error("Croatel: $chd->{xmltvid}: Incorrect time format: $celltime");
        next;
      }

      # the show title is in row2
      $oWkC = $oWkS->{Cells}[$iR][2];
      next if ( ! $oWkC );
      next if ( ! $oWkC->Value );
      my $title = $oWkC->Value;
      next if ( ! $title );

      # the show description is in row3
      $oWkC = $oWkS->{Cells}[$iR][3];
      my $descr = $oWkC->Value if ( $oWkC and $oWkC->Value );

      progress("Croatel: $chd->{xmltvid}: $time - $title");

      my $ce = {
        channel_id   => $chd->{id},
        start_time => $time,
        title => $title,
      };

      $ce->{description} = $descr if $descr;

      $dsh->AddProgramme( $ce );

    } # next row

  } # next worksheet

  $dsh->EndBatch( 1 );

  return;
}

sub ImportRTF {
  my $self = shift;
  my( $file, $chd ) = @_;

  progress( "OTV: Processing $file" );

  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $tokenizer = RTF::Tokenizer->new( file => $file );

  if( not defined( $tokenizer ) ) {
    error( "OTV $file: Failed to parse" );
    return;
  }

  my $text = '';
  my $textfull = 0;
  my $date;
  my $currdate = undef;
  my $title;
  my $havedatetime = 0;

  while( my ( $type, $arg, $param ) = $tokenizer->get_token( ) ){

    last if $type eq 'eof';

#print "--------------------------------------------------------------------\n";
#print "type: $type\n";
#print "arg: $arg\n";
#print "param: $param\n";
#print "--------------------------------------------------------------------\n";

    if( ( $type eq 'control' ) and ( $arg eq 'par' ) ){
      $textfull = 1;
    } elsif( ( $type eq 'control' ) and ( $arg eq '\'' ) ){

#      $text .= chr(0x0160) if( $param eq '8a' ); # veliko S
#      $text .= chr(0x017D) if( $param eq '8e' ); # veliko Z
#      $text .= chr(0x0161) if( $param eq '9a' ); # malo s
#      $text .= chr(0x017E) if( $param eq '9e' ); # malo z

#      $text .= chr(0x0106) if( $param eq 'c6' ); # veliko mekano C
#      $text .= chr(0x010C) if( $param eq 'c8' ); # veliko tvrdo C
#      $text .= chr(0x0107) if( $param eq 'e6' ); # malo mekano c
#      $text .= chr(0x010D) if( $param eq 'e8' ); # malo tvrdo c
#      $text .= chr(0x0110) if( $param eq 'd0' ); # veliko dj
#      $text .= chr(0x0111) if( $param eq 'f0' ); # malo dj

    } elsif( $type eq 'text' ){
      if( $arg =~ /^\d\d\:\d\d$/ ){
        $text = $arg;
        $textfull = 1;
      } else {
        $text .= $arg;
      }
    }

    if( $textfull ){
print "TEXT: $text\n";
    }
  }
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  $dinfo =~ s/[ ]//g;

  my( $day, $mon, $yea ) = ( $dinfo =~ /(\d+)\.(\d+)\.(\d+)/ );
  if( ! $day or ! $mon or ! $yea ){
    return undef;
  }

  # there is an error in the file, so fix it
  $yea = 2008 if( $yea eq 3008 );

  my $dt = DateTime->new( year   => $yea,
                          month  => $mon,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/Zagreb',
  );

  return $dt;
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
