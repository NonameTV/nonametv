package NonameTV::Importer::C1R;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail.  Each day
is handled as a separate batch.

Features:

=cut

use utf8;

use POSIX;
use DateTime;
use RTF::Tokenizer;
use Locale::Recode;
use Data::Dumper;

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

  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  if( $file !~ /\.rtf$/ ) {
    progress( "C1R: Skipping unknown file $file" );
    return;
  }

  progress( "C1R: Processing $file" );
  
  $self->{fileerror} = 0;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  
  my $tokenizer = RTF::Tokenizer->new( file => $file );

  if( not defined( $tokenizer ) ) {
    error( "C1R $file: Failed to parse" );
    return;
  }

  my $text = '';
  my $textfull = 0;
  my $date;
  my $currdate = undef;
  my $starttime;
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

      $text .= chr(0x0160) if( $param eq '8a' ); # veliko S
      $text .= chr(0x017D) if( $param eq '8e' ); # veliko Z
      $text .= chr(0x0161) if( $param eq '9a' ); # malo s
      $text .= chr(0x017E) if( $param eq '9e' ); # malo z

      $text .= chr(0x0106) if( $param eq 'c6' ); # veliko mekano C
      $text .= chr(0x010C) if( $param eq 'c8' ); # veliko tvrdo C
      $text .= chr(0x0107) if( $param eq 'e6' ); # malo mekano c
      $text .= chr(0x010D) if( $param eq 'e8' ); # malo tvrdo c
      $text .= chr(0x0110) if( $param eq 'd0' ); # veliko dj
      $text .= chr(0x0111) if( $param eq 'f0' ); # malo dj

    } elsif( $type eq 'text' ){
      if( $arg =~ /^\d\d\.\d\d$/ ){
        $text = $arg;
        $textfull = 1;
      } else {
        $text .= $arg;
      }
    }

    if( $textfull )
    {

      #my $cod = Locale::Recode->new( from => 'windows-1250' , to => 'UTF-8' );
      #my $cod = Locale::Recode->new( from => 'ISO-8859-2' , to => 'UTF-8' );
      #$cod->recode( $text );

#print "TEXT: $text\n";

      if( $text eq "" ) {
        # blank line
      }
      elsif( isDate( $text ) ) { # the token with the date in format 'MONDAY 12.4.'
#print "DATE\n";

        $date = ParseDate( $text );
#print "DATE $date\n";

        if( defined $date ) {

          $dsh->EndBatch( 1 )
            if defined $currdate;

          my $batch_id = "${xmltvid}_" . $date->ymd();
          $dsh->StartBatch( $batch_id, $channel_id );
          $dsh->StartDate( $date->ymd("-") , "04:00" );
          $currdate = $date;

          progress("C1R: $chd->{xmltvid}: Date is " . $date->ymd("-") );

          $havedatetime = 0;
        }
      }
      elsif( isShow( $text ) ) { # the token with the time in format '19.30 Vremja'

	    my( $starttime , $title, $desc ) = ParseShow( $text );

        progress("C1R: $chd->{xmltvid}: $starttime - $title");

        my $ce = {
          channel_id   => $chd->{id},
          start_time => $starttime,
          title => norm($title),
        };

        $ce->{description} = norm($desc) if defined $desc and norm($desc) ne "";

        if(defined($ce->{description}) and $ce->{description} =~ / v (.*?)$/i) {
            my $genre = $1;
            $ce->{description} =~ s/ v (.*?)$//i;

            my($program_type, $category ) = $ds->LookupCat( "C1R", norm($genre) );
            AddCategory( $ce, $program_type, $category );
        }

        $dsh->AddProgramme( $ce );

        $havedatetime = 0;
      }

      $textfull = 0;
      $text = ''
    }
  }

  $dsh->EndBatch( 1 );
    
  return;
}

sub isDate {
  my ( $text ) = @_;

  #print Dumper($text);

  # format 'Wednesday, August 13'
  # format 'Monday, September, 1'
  if( $text =~ /^\s*(monday|tuesday|wednesday|thursday|friday|saturday|sunday),\s*\S+,*\s*\d+$/i ){
    return 1;
  }

  # format 'Ponedel'nik, 27 aprelja'
  if( $text =~ /^\s*(Ponedel'nik|Vtornik|Sreda|Chetverg|Pjatnica|Subbota|Voskresen'e),\s+\d+\s+(.*)$/i ){
    return 1;
  }

  return 0;
}

sub isShow {
  my ( $text ) = @_;

  # format '23.00 Vremja'
  if( $text =~ /^\d+\.\d+\s+\S+/ ){
    return 1;
  }

  return 0;
}

sub ParseDate {
  my( $text ) = @_;

#  print Dumper($text);

  my( $dayname, $monthname, $day );
  my $month;

  # format 'Wednesday, August 13'
  if( $text =~ /^\s*(monday|tuesday|wednesday|thursday|friday|saturday|sunday),\s*\S+,*\s*\d+$/i ){
    ( $dayname, $monthname, $day ) = ( $text =~ /^\s*(\S+),\s*(\S+),*\s*(\d+)$/ );
    $month = MonthNumber( $monthname , "en" );
  }

  # format 'Ponedel'nik, 27 aprelja'
  if( $text =~ /^\s*(Ponedel'nik|Vtornik|Sreda|Chetverg|Pjatnica|Subbota|Voskresen'e),\s+\d+\s+\s*/i ){
    ( $dayname, $day, $monthname ) = ( $text =~ /^\s*(\S+),\s+(\d+)\s+(\S+)/ );
    $month = MonthNumber( $monthname , "ru" );
  }

#print "$dayname\n";
#print "$day\n";
#print "$monthname\n";
#print "$month\n";

  my $year = DateTime->today->year();

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => 0,
                          minute => 0,
                          second => 0,
                          time_zone => 'Europe/Moscow',
  );

  return $dt;
}

sub ParseShow {
  my( $text ) = @_;

  my( $hour, $min, $title ) = ( $text =~ /^(\d+)\.(\d+)\s+(.*)$/ );

  my $desc = undef;

  #$title =~ s/"//gi;
  my ($realtitle) = ($title =~ /"(.*?)"/);
  if(defined($realtitle)) {
    # Remove the title and clean it up
    # then add it to description (Premiere, actors etc)
    $desc  = $title;
    $desc  =~ s/"(.*?)"//;
    $desc  = norm($desc);
    $desc  =~ s/^\.//;
    $desc  =~ s/\((.*?)\)//g;
    $desc  = norm($desc);

    # New title
    $title = $realtitle;
  }

  $title =~ s/\.\.\.//i;
  $title =~ s/\(.*\)//i;

  return( sprintf("%02d:%02d", $hour, $min) , $title, $desc );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
