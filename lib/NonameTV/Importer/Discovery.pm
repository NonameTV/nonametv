package NonameTV::Importer::Discovery;

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
use Data::Dumper;

use NonameTV qw/Wordfile2Xml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::DataStore::Updater;
use NonameTV::Log qw/w f/;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseFile;
use base 'NonameTV::Importer::BaseFile';

my $command_re = "ÄNDRA|RADERA|TILL|INFOGA|EJ ÄNDRAD|" . 
    "CHANGE|DELETE|TO|INSERT|UNCHANGED";

my $time_re = '\d\d[\.:]\d\d';

sub new 
{
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);
  

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  my $dsu = NonameTV::DataStore::Updater->new( $self->{datastore} );
  $self->{datastoreupdater} = $dsu;
  
  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $filename, $chd ) = @_;
  
  

  if( $filename =~ /\bhigh/i ) {
    f "Skipping highlights file";
    return 0;
  }

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};

  my $doc = Wordfile2Xml( $filename );

  if( not defined( $doc ) ) {
    f "Failed to parse";
    return 0;
  }

#defined( $chd->{sched_lang} ) or die "You must specify the language used for this channel (sched_lang)";
#my $schedlang = $chd->{sched_lang};
my $schedlang = "en";

if( $filename !~ /\sAmend\s*.*$/ ) {return $self->ImportDocument( $filename, $doc, $channel_xmltvid, $channel_id );}
  else { return $self->ImportAmendments( $filename, $doc, $channel_xmltvid, $channel_id ); }

}

# Import files that contain full programming details,
# usually for an entire month.
# $doc is an XML::LibXML::Document object.
sub ImportDocument {
  my $self = shift;
  my( $filename, $doc, $channel_xmltvid, $channel_id ) = @_;
  
  my $dsh = $self->{datastorehelper};

  # Find all div-entries.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 ) {
    f "No programme entries found";
    return 0;
  }
  
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
    T_HEAD_ENG => 14,
  };
  
  my $state=ST_START;
  my $currdate;

  my $start;
  my $title;
  my $date;
  
  my $ce = {};
  
  foreach my $div ($ns->get_nodelist) {
    # Ignore English titles in National Geographic.
    #next if $div->findvalue( '@name' ) =~ /title in english/i;

    my( $text ) = norm( $div->findvalue( './/text()' ) );
    next if $text eq "";

#   print "Text: $text\n";

    my $type;
    
    if( $text =~ /^(måndag|tisdag|onsdag|torsdag|fredag|lördag|söndag|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s*\d+\s*\D+\s*\d+$/i )
    {
      $type = T_DATE;
      $date = parse_date( $text );
print "\n\ndate: $date \n";
      if( not defined $date ) {
	w "Invalid date $text";
      }

    }
    elsif( $text =~ /^\d\d\.\d\d\s+\S+/ )  
    {
      $type = T_HEAD;
      $start=undef;
      $title=undef;

      ($start, $title) = ($text =~ /^(\d+\.\d+)\s+(.*)\s*$/ );
      $start =~ tr/\./:/;  #start=HH:MM
print "$start, $title \n";
    }


    elsif( $text =~ /^\*:\s+\*$/ )
    {
      $type = T_HEAD_ENG;
      print Dumper($text);
    }
    elsif( $text =~ /^\s*END\s*$/ )
    {
      $type = T_STOP;
    }
    else
    {
      $type = T_TEXT;
    }
    
    if( $state == ST_START )
    {
      if( $type == T_TEXT )
      {
        if( $text =~ /M.nadskorrektur/ or 
	    $text =~ /Observera f.ljande .ndringar/ ) {
	    f "Ignoring amendments document.";
	    return 0;
	}
      }
      elsif( $type == T_DATE )
      {
	$dsh->StartBatch( "${channel_xmltvid}_$date", $channel_id );
	$dsh->StartDate( $date );
        $self->AddDate( $date );
	$state = ST_FDATE;
	next;
      }
      else
      {
 #       w "State ST_START, found: $text";
      }
    }
    elsif( $state == ST_FHEAD )
    {
      if( $type == T_TEXT )
      {
	if( defined( $ce->{description} ) )
	{
	  $ce->{description} .= " " . $text; 
	}
	else
	{
	  $ce->{description} = $text;
	}
	next;
      }
      elsif( $type == T_HEAD_ENG )
      {
      	$title = $text;
      }
      else
      {
	extract_extra_info( $ce );
	$dsh->AddProgramme( $ce );
	$ce = {};
	$state = ST_FDATE;
      }
    }
    
    if( $state == ST_FDATE )
    {
      if( $type == T_HEAD )
      {
	$ce->{start_time} = $start;
	$ce->{title} = $title;
#        $ce->{cx_short_description} = $title if $title;  #ignore
	$state = ST_FHEAD;
      }
      elsif( $type == T_DATE )
      {
	$dsh->EndBatch( 1 );

	$dsh->StartBatch( "${channel_xmltvid}_$date", $channel_id );
	$dsh->StartDate( $date );
        $self->AddDate( $date );
	$state = ST_FDATE;
      }
      elsif( $type == T_STOP )
      {
	$state = ST_EPILOG;
      }
      else
      {
	w "State ST_FDATE, found: $text";
      }
    }
    elsif( $state == ST_EPILOG )
    {
      if( ($type != T_TEXT) and ($type != T_DATE) )
      {
	w "State ST_EPILOG, found: $text";
      }
    }
  }
  $dsh->EndBatch( 1 ); 

  return 1;
}


sub ImportAmendments
{
  my $self = shift;
  my( $filename, $doc, $channel_xmltvid, $channel_id ) = @_;

  my $dsh = $self->{datastorehelper};
  my $dsu = $self->{datastoreupdater};
  my $lang = "en";

  progress "GlobalListings: $channel_xmltvid: Processing $filename " ;

  # Find all div-entries.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 )
  {
    error( "GlobalListings: $channel_xmltvid: $filename: No programme entries found." );
    return;
  }

  use constant {
    ST_HEAD => 0,
    ST_FOUND_DATE => 1,
  };

  my $state=ST_HEAD;

  my( $date, $prevtime, $e );
  
  foreach my $div ($ns->get_nodelist)
  {
    my( $text ) = norm( $div->findvalue( './/text()' ) );
    next if $text eq "";

#print ">$text<\n";

    my( $time, $command, $title );

    if( ($text =~ /^sida \d+ av \d+$/i) or
        ($text =~ /tablån fortsätter som tidigare/i) or
        ($text =~ /slut på tablå/i) or
        ($text =~ /^page \d+ of \d+$/i) or
        ($text =~ /schedule resumes as/i)
        )
    {
      next;
    }
    elsif( $text =~ /^SLUT|END|KRAJ$/ )
    {
      last;
    }
    elsif( isDate( $text, $lang ) )
    {
      if( $state != ST_HEAD )
      {
        $self->process_command( $channel_id, $channel_xmltvid, $e )
          if( defined( $e ) );
        $e = undef;
        $dsu->EndBatchUpdate( 1 )
          if( $self->{process_batch} ); 
      }
      $date = parse_date( $text);
      if( not defined $date ) {
	error( "GlobalListings: $channel_xmltvid: $filename Invalid date $text" );
      }

      $state = ST_FOUND_DATE;

      $self->{process_batch} = 
        $dsu->StartBatchUpdate( "${channel_xmltvid}_$date", $channel_id ) ;
      
      $self->AddDate( $date ) if $self->{process_batch};
      $self->start_date( $date );
      progress("GlobalListings: $channel_xmltvid: Date is: $date");
    }
    elsif( ($command, $title) = 
           ($text =~ /^($command_re)\s
                       (.*?)\s*
                       ( \( [^)]* \) )*
                     $/x ) )
    {
      if( $state != ST_FOUND_DATE )
      {
        die( "GlobalListings: $channel_xmltvid: $filename Wrong state for $text" );
      }

      $self->process_command( $channel_id, $channel_xmltvid, $e )
        if defined $e;

      $e = $self->parse_command( $prevtime, $command, $title );
    }
# the next regexp is not ok for Croatian yet
    elsif( ($time, $command, $title) = 
           ($text =~ /^($time_re)\s
                       ($command_re)\s+
                       ([A-ZÅÄÖ].*?)\s*
                       ( \( [^)]* \) )*
                     $/x ) )
    {
      if( $state != ST_FOUND_DATE )
      {
        die( "GlobalListings: $channel_xmltvid: $filename Wrong state for $text" );
      }

      $self->process_command( $channel_id, $channel_xmltvid, $e )
        if defined $e;

      $e = $self->parse_command( $time, $command, $title );

      $prevtime = $time;
    }
    elsif( $state == ST_FOUND_DATE )
    {
      # Plain text. This must be a description.
      if( defined( $e ) )
      {
        $e->{desc} .= $text;
        $self->process_command( $channel_id, $channel_xmltvid, $e );
        $e = undef;
      }
      else
      {
        error( "GlobalListings: $channel_xmltvid: $filename Ignored text: $text" );
      }
    }
    else
    {
      # Plain text in header. Ignore.
    }
  }
  $self->process_command( $channel_id, $channel_xmltvid, $e )
    if( defined( $e ) );

  $dsu->EndBatchUpdate( 1 )
    if( $self->{process_batch} ); 
}


sub parse_command
{
  my $self = shift;
  my( $time, $command, $title ) = @_;

#print "parse_command: $time - $command - $title\n";
  my $e;

  $e->{time} = $time;
  $e->{title} = $title;
  $e->{desc} = "";

  if( $command eq "ÄNDRA" or $command eq "RADERA")
  {
    $e->{command} = "DELETEBLIND";
  }
  elsif( $command eq "CHANGE" or $command eq "DELETE" )
  {
    # This is a document with changes in English.
    # The titles won't match.
    $e->{command} = "DELETEBLIND";
  }
  elsif( $command eq "PROMIJENI" or $command eq "BRISI" )
  {
    # This is a document with changes in Croatian.
    # The titles won't match.
    $e->{command} = "DELETEBLIND";
  }
  elsif( $command eq "TILL" or $command eq "INFOGA"    # Swedish
         or $command eq "TO" or $command eq "INSERT"   # English
         or $command eq "U" or $command eq "UMETNI" )  # Croatian
  {
    $e->{command} = "INSERT";
  }
  elsif( $command eq "EJ ÄNDRAD" or $command eq "UNCHANGED" or $command eq "NEPROMIJENJENO" )
  {
    $e->{command} = "IGNORE";
  }
  else
  {
    error( "Unknown command $command with time $time" );
  }

  return $e;
}


sub process_command
{
  my $self = shift;
  my( $channel_id, $channel_xmltvid, $e ) = @_;

  progress( "GlobalListings: $channel_xmltvid: $e->{command}: $e->{time} - $e->{title}, $e->{desc}" );

  return unless $self->{process_batch};

  my $dsu = $self->{datastoreupdater};

  my $dt = $self->create_dt( $e->{time} );

  return if $dt < DateTime->today;

  if( $e->{command} eq 'DELETEBLIND' )
  {
    my $ce = {
      channel_id => $channel_id,
      start_time => $dt->ymd('-') . " " . $dt->hms(':'),
    };      

    $self->{del_e} = $dsu->DeleteProgramme( $ce, 1 );
  }
  elsif( $e->{command} eq "INSERT" )
  {
    my $ce = {
      channel_id => $channel_id,
      start_time => $dt->ymd('-') . " " . $dt->hms(':'),
      title => $e->{title},
      description => $e->{desc},
#      cx_short_description => $e->{title},  #ignore
    };
    extract_extra_info( $ce );

    if( $e->{desc} =~ /Programförklaring ej ändrad/ )
    {
      # This is a program that has gotten a new title. It means
      # that it is a record CHANGE ... TO ... Thus, the description
      # is the same as the description from the record we just deleted.
      $ce->{description} = $self->{del_e}->{description};
    }
    else
    {
      $e->{description} = $e->{desc};
    }

    $dsu->AddProgramme( $ce );
  }    
  elsif( $e->{command} eq "IGNORE" )
  {}
  else
  {
    die( "GlobalListings: Unknown command $e->{command}" );
  }
}


sub isDate {
  my ( $text, $lang ) = @_;

#print "isDate: $lang >$text<\n";

  #
  # English formats
  #
  # format 'Friday 1st August 2008'  ovaj
  if( $text =~ /^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+\d+\S*\s+\S+\s+\d+$/i ){
    return 1; 
  }

  # format 'Sunday 1 June 2008'
  if( $text =~ /^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s*\d+\s*\D+\s*\d+$/i ){
    return 1; 
  }

  # format 'Tuesday July 01, 2008'
  if( $text =~ /^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s*\D+\s*\d+,\s*\d+$/i ){
    return 1; 
  } 

  #
  # Croatian formats
  #

  # format 'utorak(,) 1(.) srpnja 2008(.)'
  if( $text =~ /^(ponedjeljak|utorak|srijeda|četvrtak|petak|subota|nedjelja)\,*\s*\d+\.*\s*\D+\,*\s*\d+\.*$/i ){
    return 1;
  }

  return 0;
}


sub extract_extra_info
{
  my( $ce ) = shift;

  my( $episode ) = ($ce->{title} =~ /:\s*Avsnitt\s*(\d+)$/);
  $ce->{title} =~ s/:\s*Avsnitt\s*(\d+)$//; 
  $ce->{episode} = sprintf(" . %d . ", $episode-1)
    if defined( $episode );
  my( $t, $st ) = ($ce->{title} =~ /(.*)\: (.*)/);
  if( defined( $st ) )
  {
      # This program is part of a series and it has a colon in the title.
      # Assume that the colon separates the title from the subtitle.
      $ce->{title} = $t;
      $ce->{subtitle} = $st;
  }
  $ce->{title} =~ s/:\s*(.+)$//;

  $ce->{title} =~ s/^PREMI.R\s+//;

  if( $ce->{title} =~ /^\bs.ndningsslut\b$/i )
  {
    $ce->{title} = "end-of-transmission";
  }

  return;
}


sub parse_date
{
  my( $text ) = @_;

  my @months = qw/januari februari mars april maj juni juli augusti
      september oktober november december/;

  my @months_eng = qw/january february march april may june july
    august september october november december/;
  
  my %monthnames = ();
  for( my $i = 0; $i < scalar(@months); $i++ ) 
  { $monthnames{$months[$i]} = $i+1;}

  for( my $i = 0; $i < scalar(@months_eng); $i++ ) 
  { $monthnames{$months_eng[$i]} = $i+1;}
  
  my( $weekday, $day, $monthname, $year ) = 
      ( $text =~ /^(\S+?)\s*(\d+)\s*(\S+?)\s*(\d+)$/ );
  
  my $month = $monthnames{lc $monthname};
  return undef unless defined( $month );

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}


sub start_date
{
  my $self = shift;
  my( $date ) = @_;

#  print "StartDate: $date\n";

  my( $year, $month, $day ) = split( '-', $date );
  $self->{curr_date} = DateTime->new( 
                                      year   => $year,
                                      month  => $month,
                                      day    => $day,
                                      hour   => 0,
                                      minute => 0,
                                      second => 0,
                                      time_zone => 'Europe/Stockholm' );
}


sub create_dt
{
  my $self = shift;
  my( $time ) = @_;

  my $dt = $self->{curr_date}->clone();
  
  my( $hour, $minute ) = split( /[:\.]/, $time );

  w "Unknown starttime $time"
    if( not defined( $minute ) );

  # The schedule date doesn't wrap at midnight. This is what
  # they seem to use.
  if( $hour < 7 )
  {
    $dt->add( days => 1 );
  }

  # Don't die for invalid times during shift to DST.
  my $res = eval {
    $dt->set( hour   => $hour,
              minute => $minute,
              );
  };

  if( not defined $res )
  {
    w $dt->ymd('-') . " $hour:$minute: $@" ;
    $hour++;
    w "Adjusting to $hour:$minute";
    $dt->set( hour   => $hour,
              minute => $minute,
              );
  }

  $dt->set_time_zone( "UTC" );

  return $dt;
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
