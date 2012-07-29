package NonameTV::Importer::Nickelodeon;

use strict;
use warnings;

=pod

Import data from Word-files delivered via e-mail. The parsing of the
data relies only on the text-content of the document, not on the
formatting.

Features:

=cut

use utf8;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet Wordfile2Xml Htmlfile2Xml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::DataStore::Updater;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer;

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

  $self->{grabber_name} = 'Nickelodeon';

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $doc;
  if( $file =~  /doc$/i )
  {
    $doc = Wordfile2Xml( $file );
  }
  elsif( $file =~ /html$/i )
  {
    $doc = Htmlfile2Xml( $file );
  }
  else
  {
    error( "Nickelodeon: Unknown filename $file" );
    return;
  }

  if( not defined( $doc ) )
  {
    error( "Nickelodeon: Failed to parse $file" );
    return;
  }

  $self->ImportData( $file, $doc, $chd );
}

# Import files that contain full programming details,
# usually for an entire month.
# $doc is an XML::LibXML::Document object.
sub ImportData
{
  my $self = shift;
  my( $filename, $doc, $chd ) = @_;
  
  my $loghandle;

  # Find all div-entries.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 )
  {
    error( "Nickelodeon: No programme entries found in $filename" );
    return;
  }
  
  # States
  use constant {
    ST_START  => 0,
    ST_FDATE  => 1,   # Found date
    ST_FHEAD  => 2,   # Found head with starttime and title
    ST_FEND => 4,   # After END-marker
  };
  
  use constant {
    T_DATE => 10,
    T_HEAD => 11,
    T_TEXT => 12,
    T_END => 13,
  };
  
  # We keep track of the earliest and latest mentioned dates
  # and make sure that we see data for each day between these dates
  # exactly once.
  $self->{earliest_date} = DateTime->today->add( days => 1000 );
  $self->{latest_date} = DateTime->today->subtract( days => 1000 );
  my %seen_days;

  my $state=ST_START;

  my( @dates );
  my( @perioddates, $periodtext );
  my $entries = [];
  my $start;
  my $title;
  
  foreach my $div ($ns->get_nodelist)
  {
    my( $text ) = norm( $div->findvalue( './/text()' ) );
    next if $text eq "";

    my $type;
    
    if( $text =~ /^\d{1,2}(\.|:)\d{1,2}\s+(END)|(SLUT)\s*$/i ) {
      $type = T_END;
      ($start) = ($text =~ /^(\d+[\.:]\d+)\s+/ );
      $start =~ tr/\./:/;
    }
    elsif( $text =~ /^\d{1,2}(\.|:)\d{1,2}\s+\S+/ )
    {
      $type = T_HEAD;
      $start=undef;
      $title=undef;
      ($start, $title) = ($text =~ /^(\d+[\.:]\d+)\s+(.*?)\s*$/ );
      $start =~ tr/\./:/;
    }
    elsif( match_date_range( $text, \@dates ) )
    {
      $type = T_DATE;
    }
    else {
      $type = T_TEXT;
    }

#    print "$state $type\n";
    if( $state == ST_START ) {
      if( $type == T_DATE ) {
        @perioddates = @dates; 
        $periodtext = $text;
        $state = ST_FDATE;
      }
      else {
        error( "Nickelodeon: Unexpected text in state ST_START: $text" );
        next;
      }
    } 
    elsif( $state == ST_FDATE ) {
      if( $type == T_HEAD ) {
        push @{$entries}, [$start, $title, ""];
        $state = ST_FHEAD;
      }
      else {
        error( "Nickelodeon: Unexpected text in state ST_FDATE: $text" );
        next;
      }
    }
    elsif( $state == ST_FHEAD ) {
      if( $type == T_DATE ) {
        $self->process_entries( \@perioddates, $entries, $chd );
        @perioddates = @dates;
        $periodtext = $text;
        $entries = [];
        $state = ST_FDATE;
      }
      elsif( $type == T_HEAD ) {
        push @{$entries}, [$start, $title, ""];
        $state = ST_FHEAD;
      }
      elsif( $type == T_END ) {
        push @{$entries}, [$start, "end-of-transmission", ""];
        $self->process_entries( \@perioddates, $entries, $chd ); 
        @perioddates = ();
        $periodtext = undef;
        $entries = [];
        $state = ST_FEND;
      }
      elsif( $type == T_TEXT ) {
        $entries->[-1]->[2] .= " " . $text;
      }
      else {
        error( "Nickelodeon: Unexpected text in state ST_FHEAD: $text" );
        next;
      }
    }
    elsif( $state == ST_FEND ) {
      if( $type == T_DATE ) {
        @perioddates = @dates;
        $periodtext = $text;
        $entries = [];
        $state = ST_FDATE;
      }
      else {
        error( "Nickelodeon: Unexpected text in state ST_FEND: $text" );
        next;
      }
    }
  }
  $self->process_entries( \@perioddates, $entries, $chd )
    unless $state == ST_FEND;

  my $currdate = $self->{earliest_date}->clone();

  while($currdate <= $self->{latest_date}) 
  {
    if( !defined($self->{seen_days}->{$currdate->ymd("-")} ) ) {
      error( "No data for " . $currdate->ymd('-') );
    }
    $currdate = $currdate->add( days => 1 );
  }

  progress( "Nickelodeon: Imported data from " . 
            $self->{earliest_date}->ymd() . " to " .
            $self->{latest_date}->ymd() );
  
}

sub process_entries {
  my $self = shift;
  my( $dates, $entries, $chd ) = @_;

  my $dsh= $self->{datastorehelper};
  my $xmltvid= $chd->{xmltvid};
  my $channel_id= $chd->{id};

  foreach my $currdate (@{$dates}) 
  {
    error( "Nickelodeon: Duplicate data for " . $currdate->ymd('-') )
      if( defined( $self->{seen_days}->{$currdate->ymd("-")} ) );

    $self->{seen_days}->{$currdate->ymd("-")} = 1;
    
    $self->{earliest_date} = $currdate->clone()
      if( $self->{earliest_date} > $currdate );

    $self->{latest_date} = $currdate->clone()
      if( $self->{latest_date} < $currdate );

    $dsh->StartBatch($xmltvid.'_'.$currdate->ymd('-'), $channel_id);
    $dsh->StartDate($currdate->ymd('-'));
    foreach my $entry (@{$entries}) {
      my( $start, $title, $desc ) = @{$entry};
      my $ce = {
        start_time  => $start,
        title       => norm( $title ),
      };
      
      $ce->{description} = norm($desc) if $desc =~ /\S/;
      
      $dsh->AddProgramme($ce);
    }
    $dsh->EndBatch(1);
  }

  return;
}

my @weekdays_sv = qw/måndag tisdag onsdag torsdag fredag lördag söndag/;
my %monthno= ( januari => 1, januar => 1, january => 1, 
               februari => 2, februar => 2, february => 2,
               mars => 3, marts => 3, march => 3, 
               april => 4, 
               maj => 5, mai => 5, may => 5, 
               juni => 6, june => 6, 
               july => 7, juli => 7, 
               augusti => 8 , august => 8, 
               september => 9 , 
               oktober => 10, october => 10, 
               november => 11, november => 11, 
               december => 12, desember => 12, );

my $WD = join( "|", @weekdays_sv, map { $_ . "ar" } @weekdays_sv );
my %holidays = ( 'nyårsafton' => '31 december',
                 'julafton' => '24 december',
                 );

my %weekdayno = ( vardagar => "[12345]",
                  vardager => "[12345]",
                  helger => "[67]",
                  helgen => "[67]",
                  helgor => "[67]",
                  );
my $WD_SET = join( "|", keys( %weekdayno ));
my $range_re = '\s*(' . $WD . '|' . 
                   join( "|", keys( %holidays ), keys( %weekdayno ), 
                         keys( %monthno ) ) .
               '|\d+|\s+|,|och|&|-)+';

for( my $i=0; $i < scalar( @weekdays_sv ); $i++ ) 
{ 
  $weekdayno{$weekdays_sv[$i]} = $i+1;
}

sub match_date_range {
  my( $text, $dates ) = @_;

#  progress("Range?: $text" );

  return 0 unless $text =~ /^$range_re$/i;
  return 0 if $text =~ /^\s*\d*\s*$/;

  @{$dates} = ();
  my $wd = "[1234567]";
  progress("Range: $text");

  if( $text =~ s/^\s*($WD|$WD_SET)\s*//i ) {
    $wd = $weekdayno{lc($1)};
  }

  $text =~ s/\s+och\s+/, /i;
  $text =~ s/\s*&\s*/, /i;

  foreach my $holiday (keys %holidays) {
    $text  =~ s/\b$holiday\b/$holidays{$holiday}/i;
  }

  my( $fromspec, $tospec ) = split( /\s*-\s*/, $text, 2 );

  if( defined $tospec ) {
    # This is a range.
    my( $fromdate, $todate );
    $todate = parse_date( $tospec, DateTime->today );
    $fromdate = parse_date( $fromspec, $todate );

    if( DateTime->today->subtract( months => 2 ) > $fromdate ) {
      $fromdate = $fromdate->add( years => 1 );
    }

    if( $fromdate > $todate ) {
      $todate = $todate->add( years => 1 );
    }

    my $currdate = $fromdate->clone();
    my $matches = 0;

    while($currdate <= $todate) 
    {
      if( $currdate->wday() =~ m/$wd/ ) {
        push @{$dates}, $currdate->clone;
        $matches++;
      }
      $currdate->add( days => 1 );
    }
  }
  else {
    my @pdates = split( /\s*,\s*/, $text );

    my $prevdate = DateTime->today;
    for( my $i = scalar( @pdates ) - 1; $i >= 0; $i-- ) {
      # Remove the weekday since the date is unambiguous.
      $pdates[$i] =~ s/$WD//i;
      my $date = parse_date( $pdates[$i], $prevdate );
      unshift @{$dates}, $date->clone;
      $prevdate = $date;
    }
  } 

  foreach my $d (@{$dates}) {
    progress( $d->ymd('-') );
  }

  return 1;
}

# Parse a (partial) date into a proper DateTime object.
# Takes two parameters: A string containing a partial
# date specification and a DateTime object to use for
# any components that are not specified by the date 
# specification.
sub parse_date {
  my( $str, $def_dt ) = @_;

  my $dt = $def_dt->clone();

  # Avoid issues with days that don't exist in all months.
  $dt->set( day => 1 );

  $str =~ s/^\s+//;
  $str =~ s/\s+$//;

  my( $day, $month, $year ) = split( /\s+/, $str );

  if( defined( $year ) ) {
    if( $year !~ /^[0-9]{4}$/ ) {
      error( "Nickelodeon: Unknown year $year\n" );
    }
    else {
      $dt->set( year => $year );
    }
  }

  if( defined( $month ) ) {
    if( not exists( $monthno{ lc $month } ) ) {
      error( "Nickelodeon: Unknown month $month\n" );
    }
    else {
      $dt->set( month => $monthno{lc $month} );
    }
  }

  if( $day !~ /^[0-9]{1,2}$/ ) {
    error( "Nickelodeon: Unknown day $day\n" );
  }
  else {
    $dt->set( day => $day );
  }

  return $dt;
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
