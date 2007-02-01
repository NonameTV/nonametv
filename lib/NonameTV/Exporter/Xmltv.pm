package NonameTV::Exporter::Xmltv;

use strict;
use warnings;

use utf8;

use IO::File;
use DateTime;
use XMLTV;
use File::Copy;

use NonameTV::Exporter;
use NonameTV::Language qw/LoadLanguage/;

use XMLTV::ValidateFile qw/LoadDtd ValidateFile/;

use NonameTV::Log qw/info progress error logdie/;

use base 'NonameTV::Exporter';

=pod

Export data in xmltv format.

Options:

  --verbose
    Show which datafiles are created.

  --export-channels
    Print a list of all channels in xml-format to stdout.

  --remove-old
    Remove any old xmltv files from the output directory.

  --force-export
    Recreate all output files, not only the ones where data has
    changed.

=cut 

our $OptionSpec     = [ qw/export-channels remove-old force-export 
                           verbose help/ ];
our %OptionDefaults = ( 
                        'export-channels' => 0,
                        'remove-old' => 0,
                        'force-export' => 0,
                        'help' => 0,
                        'verbose' => 0,
                        );

$XMLTV::ValidateFile::REQUIRE_CHANNEL_ID = 0;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{Encoding} ) or die "You must specify Encoding.";
    defined( $self->{DtdFile} ) or die "You must specify DtdFile.";
    defined( $self->{Root} ) or die "You must specify Root";
    defined( $self->{Language} ) or die "You must specify Language";

    $self->{MaxDays} = 365 unless defined $self->{MaxDays};
    $self->{MinDays} = $self->{MaxDays} unless defined $self->{MinDays};

    $self->{LastRequiredDate} = 
      DateTime->today->add( days => $self->{MinDays}-1 )->ymd("-");

    LoadDtd( $self->{DtdFile} );

    my $ds = $self->{datastore};

    # Load language strings
    $self->{lngstr} = LoadLanguage( $self->{Language}, 
                                   "exporter-xmltv", $ds );

    return $self;
}

sub Export
{
  my( $self, $p ) = @_;

  if( $p->{'help'} )
  {
    print << 'EOH';
Export data in xmltv-format with one file per day and channel.

Options:

  --export-channels
    Generate an xml-file listing all channels and their corresponding
    base url.

  --remove-old
    Remove all data-files for dates that have already passed.

  --force-export
    Export all data. Default is to only export data for batches that
    have changed since the last export.

EOH

    return;
  }

  NonameTV::Log::verbose( $p->{verbose} );

  if( $p->{'export-channels'} )
  {
    $self->ExportChannelList();
    return;
  }

  if( $p->{'remove-old'} )
  {
    $self->RemoveOld();
    return;
  }

  my $todo = {};
  my $update_started = time();
  my $last_update = $self->ReadState();

  if( $p->{'force-export'} ) {
    $self->FindAll( $todo );
  }
  else {
    $self->FindUpdated( $todo, $last_update );
    $self->FindUnexportedDays( $todo, $last_update );
  }

  $self->ExportData( $todo );

  $self->WriteState( $update_started );
}


# Find all dates for each channel
sub FindAll {
  my $self = shift;
  my( $todo ) = @_;

  my $ds = $self->{datastore};

  my ( $res, $channels ) = $ds->Sql( 
       "select id from channels where export=1");

  my $last_date = DateTime->today->add( days => $self->{MaxDays} -1 );
  my $first_date = DateTime->today; 

  while( my $data = $channels->fetchrow_hashref() ) {
    add_dates( $todo, $data->{id}, 
               '1970-01-01 00:00:00', '2100-12-31 23:59:59', 
               $first_date, $last_date );
  }

  $channels->finish();
}

# Find all dates that may have new data for each channel.
sub FindUpdated {
  my $self = shift;
  my( $todo, $last_update ) = @_;

  my $ds = $self->{datastore};
 
  my ( $res, $update_batches ) = $ds->Sql( << 'EOSQL'
    select channel_id, batch_id, 
           min(start_time)as min_start, max(start_time) as max_start
    from programs 
    where batch_id in (
      select id from batches where last_update > ?
    )
    group by channel_id, batch_id

EOSQL
    , [$last_update] );

  my $last_date = DateTime->today->add( days => $self->{MaxDays} -1 );
  my $first_date = DateTime->today; 

  while( my $data = $update_batches->fetchrow_hashref() ) {
    add_dates( $todo, $data->{channel_id}, 
               $data->{min_start}, $data->{max_start}, 
               $first_date, $last_date );
  }

  $update_batches->finish();
}

# Find all dates that should be exported but haven't been exported
# yet. 
sub FindUnexportedDays {
  my $self = shift;
  my( $todo, $last_update ) = @_;

  my $ds = $self->{datastore};

  my $days = int( time()/(24*60*60) ) - int( $last_update/(24*60*60) );
  $days = $self->{MaxDays} if $days > $self->{MaxDays};

  if( $days > 0 ) {
    # The previous export was done $days ago.

    my $last_date = DateTime->today->add( days => $self->{MaxDays} -1 );
    my $first_date = $last_date->clone->subtract( days => $days-1 ); 

    my ( $res, $channels ) = $ds->Sql( 
       "select id from channels where export=1");
    
    while( my $data = $channels->fetchrow_hashref() ) {
      add_dates( $todo, $data->{id}, 
                 '1970-01-01 00:00:00', '2100-12-31 23:59:59', 
                 $first_date, $last_date ); 
    }
    
    $channels->finish();
  }
}

sub ExportData {
  my $self = shift;
  my( $todo ) = @_;

  my $ds = $self->{datastore};

  foreach my $channel (keys %{$todo}) {
    my $chd = $ds->Lookup( "channels", { id => $channel } );

    foreach my $date (sort keys %{$todo->{$channel}}) {
      $self->ExportFile( $chd, $date );
    }
  }
}

sub ReadState {
  my $self = shift;

  my $ds = $self->{datastore};
 
  my $last_update = $ds->Lookup( 'state', { name => "xmltv_last_update" },
                                 'value' );

  if( not defined( $last_update ) )
  {
    $ds->Add( 'state', { name => "xmltv_last_update", value => 0 } );
    $last_update = 0;
  }

  return $last_update;
}

sub WriteState {
  my $self = shift;
  my( $update_started ) = @_;

  my $ds = $self->{datastore};

  $ds->Update( 'state', { name => "xmltv_last_update" }, 
               { value => $update_started } );
}

#######################################################
#
# Utility functions
#
sub add_dates {
  my( $h, $chid, $from, $to, $first, $last ) = @_;

  my $from_dt = create_dt( $from, 'UTC' )->truncate( to => 'day' );
  my $to_dt = create_dt( $to, 'UTC' )->truncate( to => 'day' );
 
  $to_dt = $last->clone() if $last < $to_dt;
  $from_dt = $first->clone() if $first > $from_dt;

  my $first_dt = $from_dt->clone()->subtract( days => 1 );
 
  for( my $dt = $first_dt->clone();
       $dt <= $to_dt; $dt->add( days => 1 ) ) {
    $h->{$chid}->{$dt->ymd('-')} = 1;
  } 
}
  
sub create_dt
{
  my( $str, $tz ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) =
    ( $str =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})$/ );

  if( defined( $second ) ) {
    return DateTime->new(
                         year => $year,
                         month => $month,
                         day => $day,
                         hour => $hour,
                         minute => $minute,
                         second => $second,
                         time_zone => $tz );
  }

  ( $year, $month, $day ) =
    ( $str =~ /^(\d{4})-(\d{2})-(\d{2})$/ );

  logdie( "Xmltv: Unknown time format $str" )
    unless defined $day;

  return DateTime->new(
                       year => $year,
                       month => $month,
                       day => $day,
                       time_zone => $tz );
}

#######################################################
#
# Xmltv-specific methods.
#

sub ExportFile {
  my $self = shift;
  my( $chd, $date ) = @_;

  my $startdate = $date;
  my $enddate = create_dt( $date, 'UTC' )->add( days => 1 )->ymd('-');

  my( $res, $sth ) = $self->{datastore}->Sql( "
        SELECT * from programs
        WHERE (channel_id = ?) 
          and (start_time >= ?)
          and (start_time < ?) 
        ORDER BY start_time", 
      [$chd->{id}, "$startdate 00:00:00", "$enddate 23:59:59"] );
  
  my $w = $self->CreateWriter( $chd, $date );

  my $done = 0;

  my $d1 = $sth->fetchrow_hashref();

  if( (not defined $d1) or ($d1->{start_time} gt "$startdate 23:59:59") ) {
    error( "Xmltv: No data for $chd->{xmltvid}_$date" )
      unless $chd->{empty_ok};

    $self->CloseWriter( $w );
    $sth->finish();
    return;
  }

  while( my $d2 = $sth->fetchrow_hashref() )
  {
    if( (not defined( $d1->{end_time})) or
        ($d1->{end_time} eq "0000-00-00 00:00:00") )
    {
      # Fill in missing end_time on the previous entry with the start-time
      # of the current entry
      $d1->{end_time} = $d2->{start_time}
    }
    elsif( $d1->{end_time} gt $d2->{start_time} )
    {
      # The previous programme ends after the current programme starts.
      # Adjust the end_time of the previous programme.
      error( "Xmltv: Adjusted endtime for $chd->{xmltvid}: " . 
             "$d1->{end_time} => $d2->{start_time}" );

      $d1->{end_time} = $d2->{start_time}
    }        
      

    $self->WriteEntry( $w, $d1, $chd )
      unless $d1->{title} eq "end-of-transmission";

    if( $d2->{start_time} gt "$startdate 23:59:59" ) {
      $done = 1;
      last;
    }
    $d1 = $d2;
  }

  if( not $done )
  {
    # The loop exited because we ran out of data. This means that
    # there is no data for the day after the day that we
    # wanted to export. Make sure that we write out the last entry
    # if we know the end-time for it.
    if( (defined( $d1->{end_time})) and
        ($d1->{end_time} ne "0000-00-00 00:00:00") )
    {
      $self->WriteEntry( $w, $d1, $chd )
        unless $d1->{title} eq "end-of-transmission";
    }
    else
    {
      error( "Xmltv: Missing end-time for last entry for " .
             "$chd->{xmltvid}_$date" );
    }
  }

  $self->CloseWriter( $w );
  $sth->finish();
}

sub CreateWriter
{
  my $self = shift;
  my( $chd, $date ) = @_;

  my $xmltvid = $chd->{xmltvid};

  my $path = $self->{Root};
  my $filename =  $xmltvid . "_" . $date . ".xml";

  info( "Xmltv: $filename" );

  $self->{writer_filename} = $filename;
  $self->{writer_entries} = 0;
  # Make sure that writer_entries is always true if we don't require data
  # for this date.
  $self->{writer_entries} = "0 but true" 
    if( ($date gt $self->{LastRequiredDate}) or $chd->{empty_ok} );

  open( my $fh, '>:encoding(' . $self->{Encoding} . ')', "$path$filename.new")
    or logdie( "Xmltv: cannot write to $path$filename.new" );

  my $w = new XMLTV::Writer( encoding => $self->{Encoding},
                             OUTPUT   => $fh );
  
  $w->start({ 'generator-info-name' => 'nonametv' });
    
  return $w;
}

sub CloseWriter
{
  my $self = shift;
  my( $w ) = @_;

  my $path = $self->{Root};
  my $filename = $self->{writer_filename};
  delete $self->{writer_filename};

  $w->end();

  system("gzip -f -n $path$filename.new");
  if( -f "$path$filename.gz" )
  {
    system("diff $path$filename.new.gz $path$filename.gz > /dev/null");
    if( $? )
    {
      move( "$path$filename.new.gz", "$path$filename.gz" );
      progress( "Exported $filename.gz" );
      if( not $self->{writer_entries} )
      {
        error( "Xmltv: $filename.gz is empty" );
      }
      elsif( $self->{writer_entries} > 0 )
      {
        my @errors = ValidateFile( "$path$filename.gz" );
        if( scalar( @errors ) > 0 )
        {
          error( "Xmltv: $filename.gz contains errors: " . 
                 join( ", ", @errors ) );
        }
      }
    }
    else
    {
      unlink( "$path$filename.new.gz" );
    }
  }
  else
  {
    move( "$path$filename.new.gz", "$path$filename.gz" );
    progress( "Xmltv: Exported $filename.gz" );
    if( not $self->{writer_entries} )
    {
      error( "Xmltv: $filename.gz is empty" );
    }
    elsif( $self->{writer_entries} > 0 )
    {
      my @errors = ValidateFile( "$path$filename.gz" );
      if( scalar( @errors ) > 0 )
      {
        error( "Xmltv: $filename.gz contains errors: " . 
               join( ", ", @errors ) );
      }
    }
  }
}

sub WriteEntry
{
  my $self = shift;
  my( $w, $data, $chd ) = @_;

  $self->{writer_entries}++;

  my $start_time = create_dt( $data->{start_time}, "UTC" );
  $start_time->set_time_zone( "Europe/Stockholm" );
  
  my $end_time = create_dt( $data->{end_time}, "UTC" );
  $end_time->set_time_zone( "Europe/Stockholm" );
  
  my $d = {
    channel => $chd->{xmltvid},
    start => $start_time->strftime( "%Y%m%d%H%M%S %z" ),
    stop => $end_time->strftime( "%Y%m%d%H%M%S %z" ),
    title => [ [ $data->{title}, $chd->{sched_lang} ] ],
  };
  
  $d->{desc} = [[ $data->{description},$chd->{sched_lang} ]] 
    if defined( $data->{description} ) and $data->{description} ne "";
  
  $d->{'sub-title'} = [[ $data->{subtitle}, $chd->{sched_lang} ]] 
    if defined( $data->{subtitle} ) and $data->{subtitle} ne "";
  
  if( defined( $data->{episode} ) and ($data->{episode} =~ /\S/) )
  {
    my( $season, $ep, $part );

    if( $data->{episode} =~ /\./ )
    {
      ( $season, $ep, $part ) = split( /\s*\.\s*/, $data->{episode} );
      if( $season =~ /\S/ )
      {
        $season++;
      }
    }
    else
    {
      $ep = $data->{episode};
    }

    my( $ep_nr, $ep_max ) = split( "/", $ep );
    $ep_nr++;

    my $ep_text = $self->{lngstr}->{episode_number} . " $ep_nr";
    $ep_text .= " " . $self->{lngstr}->{of} . " $ep_max" 
      if defined $ep_max;
    $ep_text .= " " . $self->{lngstr}->{episode_season} . " $season" 
      if( $season );

    $d->{'episode-num'} = [[ $data->{episode}, 'xmltv_ns' ],
                           [ $ep_text, 'onscreen'] ];
  }
  
  if( defined( $data->{program_type} ) and ($data->{program_type} =~ /\S/) )
  {
    push @{$d->{category}}, [$data->{program_type}, 'en'];
  }
  elsif( defined( $chd->{def_pty} ) and ($chd->{def_pty} =~ /\S/) )
  {
    push @{$d->{category}}, [$chd->{def_pty}, 'en'];
  }

  if( defined( $data->{category} ) and ($data->{category} =~ /\S/) )
  {
    push @{$d->{category}}, [$data->{category}, 'en'];
  }
  elsif( defined( $chd->{def_cat} ) and ($chd->{def_cat} =~ /\S/) )
  {
    push @{$d->{category}}, [$chd->{def_cat}, 'en'];
  }

  if( defined( $data->{production_date} ) and 
      ($data->{production_date} =~ /\S/) )
  {
    $d->{date} = substr( $data->{production_date}, 0, 4 );
  }

  if( $data->{aspect} ne "unknown" )
  {
    $d->{video} = { aspect => $data->{aspect} };
  }

  if( $data->{directors} =~ /\S/ )
  {
    $d->{credits}->{director} = [split( ", ", $data->{directors})];
  }

  if( $data->{actors} =~ /\S/ )
  {
    $d->{credits}->{actor} = [split( ", ", $data->{actors})];
  }

  if( $data->{writers} =~ /\S/ )
  {
    $d->{credits}->{writer} = [split( ", ", $data->{writers})];
  }

  if( $data->{adapters} =~ /\S/ )
  {
    $d->{credits}->{adapter} = [split( ", ", $data->{adapters})];
  }

  if( $data->{producers} =~ /\S/ )
  {
    $d->{credits}->{producer} = [split( ", ", $data->{producers})];
  }

  if( $data->{presenters} =~ /\S/ )
  {
    $d->{credits}->{presenter} = [split( ", ", $data->{presenters})];
  }

  if( $data->{commentators} =~ /\S/ )
  {
    $d->{credits}->{commentator} = [split( ", ", $data->{commentators})];
  }

  if( $data->{guests} =~ /\S/ )
  {
    $d->{credits}->{guest} = [split( ", ", $data->{guests})];
  }

  $w->write_programme( $d );
}

#
# Write description of all channels to channels.xml.gz.
#
sub ExportChannelList
{
  my( $self ) = @_;
  my $ds = $self->{datastore};
 
  my $output = new IO::File("> $self->{Root}channels.xml");
  
  my %w_args = ( 
                 encoding    => $self->{Encoding},
                 DATA_INDENT => 2, 
                 DATA_MODE   => 1,
                 OUTPUT      => $output,
                 );
  my $w = new XML::Writer( %w_args );

  $w->xmlDecl( $self->{Encoding} );

  $w->startTag( 'tv', 'generator-info-name' => 'nonametv' );

  my( $res, $sth ) = $ds->Sql( "
      SELECT * from channels 
      WHERE export=1
      ORDER BY xmltvid" );

  while( my $data = $sth->fetchrow_hashref() )
  {
    $w->startTag( 'channel', id => $data->{xmltvid} );
    $w->startTag( 'display-name', lang => $data->{sched_lang} );
    $w->characters( $data->{display_name} );
    $w->endTag( 'display-name' );
    $w->startTag( 'base-url' );
    $w->characters( $self->{RootUrl} );
    $w->endTag( 'base-url' );
    if( $data->{logo} )
    {
      $w->emptyTag( 'icon', 
                    src => $self->{IconRootUrl} . 
                           $data->{xmltvid} .  ".png"  );
    }
    $w->endTag( 'channel' );
  }
  
  $w->endTag( 'tv' );
  $w->end();
  system("gzip -f -n $self->{Root}channels.xml");
}

#
# Remove old xml-files and xml.gz-files. 
#
sub RemoveOld
{
  my( $self ) = @_;

  my $ds = $self->{datastore};
 
  # Keep files for the last week.
  my $keep_date = DateTime->today->subtract( days => 8 )->ymd("-");

  my @files = glob( $self->{Root} . "*" );
  my $removed = 0;

  foreach my $file (@files)
  {
    my($date) = 
      ($file =~ /(\d\d\d\d-\d\d-\d\d)\.xml(\.gz){0,1}/);

    if( defined( $date ) )
    {
      # Compare date-strings.
      if( $date lt $keep_date )
      {
        info( "Xmltv: Removing $file" );
        unlink( $file );
        $removed++;
      }
    }
  }

  progress( "Xmltv: Removed $removed files" )
    if( $removed > 0 );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
  
