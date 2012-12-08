package NonameTV::Importer::PlayboyTV;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail. The parsing of the
data relies only on the text-content of the document, not on the
formatting.

Features:

Episode numbers parsed from title.
Subtitles.

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet File2Xml norm MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::DataStore::Updater;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;
use base 'NonameTV::Importer::BaseFile';

# The lowest log-level to store in the batch entry.
# DEBUG = 1
# INFO = 2
# PROGRESS = 3
# ERROR = 4
# FATAL = 5
my $BATCH_LOG_LEVEL = 4;

sub new 
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);
  

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

#return if( $chd->{xmltvid} !~ /privatespice\.tv\.gonix\.net/ );

  defined( $chd->{sched_lang} ) or die "You must specify the language used for this channel (sched_lang)";
  if( $chd->{sched_lang} !~ /^en$/ and $chd->{sched_lang} !~ /^se$/ and $chd->{sched_lang} !~ /^hr$/ ){
    error( "PlayboyTV: $chd->{xmltvid} Unsupported language '$chd->{sched_lang}'" );
    return;
  }

  my $schedlang = $chd->{sched_lang};
  progress( "PlayboyTV: $chd->{xmltvid}: Setting schedules language to '$schedlang'" );

  return if( $file !~ /\.doc$/i );

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};

  my $doc = File2Xml( $file );
#print "DOC\n---------------\n" . $doc->toString(1) . "\n";
#return;


  if( not defined( $doc ) )
  {
    error( "PlayboyTV: $chd->{xmltvid} Failed to parse $file" );
    return;
  }

  $self->ImportFull( $file, $doc, $channel_xmltvid, $channel_id, $schedlang );
}

# Import files that contain full programming details,
# usually for an entire month.
# $doc is an XML::LibXML::Document object.
sub ImportFull
{
  my $self = shift;
  my( $filename, $doc, $channel_xmltvid, $channel_id, $lang ) = @_;
  
  my $dsh = $self->{datastorehelper};

  # Find all div-entries.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 )
  {
    error( "PlayboyTV: $channel_xmltvid: No programme entries found in $filename" );
    return;
  }
  
  progress( "PlayboyTV: $channel_xmltvid: Processing $filename" );

  # States
  use constant {
    ST_START  => 0,
    ST_FDATE  => 1,   # Found date
    ST_FHEAD  => 2,   # Found head with starttime and title
    ST_FDESC  => 3,   # Found description
    ST_EPILOG => 4,   # After END-marker
  };
  
  use constant {
    T_HEAD => 10,
    T_DATE => 11,
    T_TEXT => 12,
    T_STOP => 13,
  };
  
  my $state=ST_START;
  my $currdate;

  my $start;
  my $title;
  my $date;
  
  my $ce = {};
  
  foreach my $div ($ns->get_nodelist)
  {

    my( $text ) = norm( $div->findvalue( './/text()' ) );
    next if $text eq "";

    my $type;

#print "$text\n";

    if( isDate( $text, $lang ) ){

      $type = T_DATE;
      $date = ParseDate( $text, $lang );
      if( not defined $date ) {
	error( "PlayboyTV: $channel_xmltvid: $filename Invalid date $text" );
      }
      progress("PlayboyTV: $channel_xmltvid: Date is: $date");

    } elsif( isShow( $text ) ){

      $type = T_HEAD;
      $start=undef;
      $title=undef;

      ( $start, $title ) = ($text =~ /^(\d+\:\d+)\s+(.*)\s*$/ );
      $start =~ tr/\./:/;
      $title =~ s/\s+\(18\+\)//g if $title;

    } elsif( $text =~ /^\s*Programme Schedule - \s*$/ ){

      $type = T_STOP;

    } else {

      $type = T_TEXT;

    }
    
    if( $state == ST_START ){

      if( $type == T_TEXT ) {

        # Ignore any text before we find T_DATE

      } elsif( $type == T_DATE ) {

	$dsh->StartBatch( "${channel_xmltvid}_$date", $channel_id );
	$dsh->StartDate( $date );
        $self->AddDate( $date );
	$state = ST_FDATE;
	next;

      } else {

	error( "PlayboyTV: $channel_xmltvid: State ST_START, found: $text" );

      }

    } elsif( $state == ST_FHEAD ){

      if( $type == T_TEXT ){

	if( defined( $ce->{description} ) ){

	  $ce->{description} .= " " . $text;

	} else {

	  $ce->{description} = $text;

	}
	next;

      } else {

	extract_extra_info( $ce );

        progress("PlayboyTV: $channel_xmltvid: $start - $title");

        $ce->{quality} = 'HDTV' if( $channel_xmltvid =~ /hd\./ );

	$dsh->AddProgramme( $ce );
	$ce = {};
	$state = ST_FDATE;

      }
    }
    
    if( $state == ST_FDATE ){

      if( $type == T_HEAD ){

	$ce->{start_time} = $start;
	$ce->{title} = $title;
	$state = ST_FHEAD;

      } elsif( $type == T_DATE ){

	$dsh->EndBatch( 1 );

	$dsh->StartBatch( "${channel_xmltvid}_$date", $channel_id );
	$dsh->StartDate( $date );
        $self->AddDate( $date );
	$state = ST_FDATE;

      } elsif( $type == T_STOP ){

	$state = ST_EPILOG;

      } else {

	error( "PlayboyTV: $channel_xmltvid: $filename State ST_FDATE, found: $text" );

      }

    } elsif( $state == ST_EPILOG ){

      if( ($type != T_TEXT) and ($type != T_DATE) ) {

        error( "PlayboyTV: $channel_xmltvid: $filename State ST_EPILOG, found: $text" );

      }
    }
  }

  $dsh->EndBatch( 1 );
}

sub extract_extra_info
{
  my( $ce ) = shift;

#  if( $ce->{title} =~ /Episode\s*\d+\./ ){
#
#    my( $t, $e, $d ) = ( $ce->{title} =~ /^(.*)\s*Episode\s*(\d+)\.\s*(.*)$/ );
#print "N $t\n";
#print "E $e\n";
#print "D $d\n";
#
#    $ce->{title} = $t if $t;
#    $ce->{description} = $d if $d;
#    $ce->episode = sprintf( ". %d .", $e-1 ) if $e;
#
#  }

  if( ! $ce->{description} ){

    if( $ce->{title} =~ /\S+[a-z|0-9][A-Z]\S+/ ){
      my( $t, $d ) = ( $ce->{title} =~ /(.*\S+[a-z|0-9])([A-Z]\S+.*)/ );
      $ce->{title} = $t;
      $ce->{description} = $d;
    }

  }

  return;
}

sub isDate {
  my ( $text, $lang ) = @_;

#print "isDate: $lang >$text<\n";

  if( $text =~ /^\d{2}\/\d{2}\/\d{2}$/i ){ # format '31/01/10'
    return 1;
  } elsif( $text =~ /^\d+-\S+-\d+$/i ){ # format '01-Feb-10'
    return 1;
  } elsif( $text =~ /^\d+\.\d+\.\d+$/i ){ # format '01.02.2010'
    return 1;
  } elsif( $text =~ /^(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\d+\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d+$/i ){ # format 'MONDAY18 OCTOBER 2010'
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my( $text, $lang ) = @_;

#print "ParseDate: >$text<\n";

  my( $dayname, $day, $month, $monthname, $year );

  if( $lang =~ /^en$/ ){

    if( $text =~ /^\d{2}\/\d{2}\/\d{2}$/i ){ # try '31/01/10'
      ( $day, $month, $year ) = ( $text =~ /^(\d{2})\/(\d{2})\/(\d{2})$/ );
    } elsif( $text =~ /^\d+-\S+-\d+$/i ){ # try '01-Feb-10'
      ( $day, $monthname, $year ) = ( $text =~ /^(\d+)-(\S+)-(\d+)$/ );
      $month = MonthNumber( $monthname, "en" );
    } elsif( $text =~ /^\d+\.\d+\.\d+$/i ){ # try '01.02.2010'
      ( $day, $month, $year ) = ( $text =~ /^(\d+)\.(\d+)\.(\d+)$/ );
    } elsif( $text =~ /^(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\d+\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d+$/i ){
      ( $dayname, $day, $monthname, $year ) = ( $text =~ /^(sunday|monday|tuesday|wednesday|thursday|friday|saturday)(\d+)\s+(\S+)\s+(\d+)$/i );
      $month = MonthNumber( $monthname, "en" );
    }

  } else {
    return undef;
  }

  $year+= 2000 if $year< 100;
  
  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isShow {
  my ( $text ) = @_;

  # format '4:00 Naughty Amateur Home Videos'
  if( $text =~ /^\d+:\d+\s+.*$/i ){
    return 1;
  }

  return 0;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
