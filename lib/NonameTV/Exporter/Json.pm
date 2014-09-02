package NonameTV::Exporter::Json;

use strict;
use warnings;

use utf8;

use IO::File;
use DateTime;
use File::Copy;
use JSON::XS;
use Data::Dumper;

use NonameTV::Exporter;
use NonameTV::Language qw/LoadLanguage/;
use NonameTV qw/norm/;

use NonameTV::Log qw/d p w StartLogSection EndLogSection SetVerbosity/;

use base 'NonameTV::Exporter';

=pod

Export data in json format.

Options:

  --verbose
    Show which datafiles are created.

  --quiet 
    Show only fatal errors.

  --export-channels
    Print a list of all channels in xml-format to stdout.

  --remove-old
    Remove any old xmltv files from the output directory.

  --force-export
    Recreate all output files, not only the ones where data has
    changed.

=cut 

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{Root} ) or die "You must specify Root";
    defined( $self->{Language} ) or die "You must specify Language";

    $self->{MaxDays} = 365 unless defined $self->{MaxDays};
    $self->{MinDays} = $self->{MaxDays} unless defined $self->{MinDays};

    $self->{LastRequiredDate} = 
      DateTime->today->add( days => $self->{MinDays}-1 )->ymd("-");

    $self->{OptionSpec} = [ qw/export-channels remove-old force-export 
			    verbose+ quiet+ help/ ];

    $self->{OptionDefaults} = { 
      'export-channels' => 0,
      'remove-old' => 0,
      'force-export' => 0,
      'help' => 0,
      'verbose' => 0,
      'quiet' => 0,
    };

    return $self;
}

sub Export
{
  my( $self, $p ) = @_;

  if( $p->{'help'} )
  {
    print << 'EOH';
Export data in json-format with one file per day and channel.

Options:

  --export-channels
    Generate an json-file listing all channels and their corresponding
    base url.

  --remove-old
    Remove all data-files for dates that have already passed.

  --force-export
    Export all data. Default is to only export data for batches that
    have changed since the last export.

EOH

    return;
  }

  SetVerbosity( $p->{verbose}, $p->{quiet} );

  StartLogSection( "Json", 0 );

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
  EndLogSection( "Json" );
}


# Find all dates for each channel
sub FindAll {
  my $self = shift;
  my( $todo ) = @_;

  my $ds = $self->{datastore};

  my ( $res, $channels ) = $ds->sa->Sql( 
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
 
  my ( $res, $update_batches ) = $ds->sa->Sql( << 'EOSQL'
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

    my ( $res, $channels ) = $ds->sa->Sql( 
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
    my $chd = $ds->sa->Lookup( "channels", { id => $channel } );

    foreach my $date (sort keys %{$todo->{$channel}}) {
      $self->ExportFile( $chd, $date );
    }
  }
}

sub ReadState {
  my $self = shift;

  my $ds = $self->{datastore};
 
  my $last_update = $ds->sa->Lookup( 'state', { name => "json_last_update" },
                                 'value' );

  if( not defined( $last_update ) )
  {
    $ds->sa->Add( 'state', { name => "json_last_update", value => 0 } );
    $last_update = 0;
  }

  return $last_update;
}

sub WriteState {
  my $self = shift;
  my( $update_started ) = @_;

  my $ds = $self->{datastore};

  $ds->sa->Update( 'state', { name => "json_last_update" }, 
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

  die( "Xmltv: Unknown time format $str" )
    unless defined $day;

  return DateTime->new(
                       year => $year,
                       month => $month,
                       day => $day,
                       time_zone => $tz );
}

#######################################################
#
# Json-specific methods.
#

sub ExportFile {
  my $self = shift;
  my( $chd, $date ) = @_;

  my $section = "Json $chd->{xmltvid}_$date";

  StartLogSection( $section, 0 );

  d "Generating";

  my $startdate = $date;
  my $enddate = create_dt( $date, 'UTC' )->add( days => 1 )->ymd('-');

  my( $res, $sth ) = $self->{datastore}->sa->Sql( "
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
    $self->CloseWriter( $w );
    $sth->finish();
    EndLogSection( $section );
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
      w "Adjusted endtime $d1->{end_time} => $d2->{start_time}";

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
      w "Missing end-time for last entry"
	  unless $date gt $self->{LastRequiredDate};
    }
  }

  $self->CloseWriter( $w );
  $sth->finish();

  EndLogSection( $section );
}

sub CreateWriter
{
  my $self = shift;
  my( $chd, $date ) = @_;

  my $xmltvid = $chd->{xmltvid};

  my $path = $self->{Root};
  my $filename =  $xmltvid . "_" . $date . ".js";

  my $ds = $self->{datastore};

  $self->{writer_filename} = $filename;
  $self->{writer_entries} = 0;
  # Make sure that writer_entries is always true if we don't require data
  # for this date.
  $self->{writer_entries} = "0 but true" 
    if( ($date gt $self->{LastRequiredDate}) or $chd->{empty_ok} );

  $self->{lngstr} = LoadLanguage( $chd->{sched_lang},
                                         "exporter-xmltv", $ds );

  my $data = [];

  return $data;
}

sub CloseWriter
{
  my $self = shift;
  my( $data ) = @_;

  my $path = $self->{Root};
  my $filename = $self->{writer_filename};
  delete $self->{writer_filename};

  open( my $fh, ">$path$filename.new")
    or die( "Json: cannot write to $path$filename.new" );

  my $odata = { 
    jsontv => { 
      programme => $data,
    }
  };

  my $js = JSON::XS->new;
  $js->ascii( 1 );
  $js->pretty( 1 );
  $fh->print( $js->encode( $odata ) );
  $fh->close();

  system("gzip -f -n $path$filename.new");
  if( -f "$path$filename.gz" )
  {
    system("diff $path$filename.new.gz $path$filename.gz > /dev/null");
    if( $? )
    {
      move( "$path$filename.new.gz", "$path$filename.gz" );
      p "Exported";
      if( not $self->{writer_entries} )
      {
        w "Created empty file";
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
    p "Generated";
    if( not $self->{writer_entries} )
    {
      w "Empty file";
    }
  }
}

sub WriteEntry
{
  my $self = shift;
  my( $data, $entry, $chd ) = @_;

  $self->{writer_entries}++;

  my $start_time = create_dt( $entry->{start_time}, "UTC" );
  my $end_time = create_dt( $entry->{end_time}, "UTC" );
  
  my $d = {
    channel => $chd->{xmltvid},
    start => $start_time->strftime( "%s" ),
    stop => $end_time->strftime( "%s" ),
    title => { $chd->{sched_lang}, $entry->{title} }
  };
  
  $d->{desc} = { $chd->{sched_lang} => $entry->{description} } 
    if defined( $entry->{description} ) and $entry->{description} ne "";
  
  $d->{'subTitle'} = { $chd->{sched_lang} => $entry->{subtitle} }
    if defined( $entry->{subtitle} ) and $entry->{subtitle} ne "";
  
  if( defined( $entry->{episode} ) and ($entry->{episode} =~ /\S/) )
  {
    my( $season, $ep, $part );

    if( $entry->{episode} =~ /\./ )
    {
      ( $season, $ep, $part ) = split( /\s*\.\s*/, $entry->{episode} );
      if( $season =~ /\S/ )
      {
        $season++;
      }
    }
    else
    {
      print "Simple episode '$entry->{episode}'\n";
      $ep = $entry->{episode};
    }

    if( $ep =~ /\S/ ) {
      my( $ep_nr, $ep_max ) = split( "/", $ep );
      my( $inetref, $system );
      $ep_nr++;
      
      my $ep_text = $self->{lngstr}->{episode_number} . " $ep_nr";
      $ep_text .= " " . $self->{lngstr}->{of} . " $ep_max" 
	  if defined $ep_max;
      $ep_text .= " " . $self->{lngstr}->{episode_season} . " $season" 
	  if( $season );

	  # MythTV
	  if( $entry->{url}) {
        if( $entry->{url} =~ m|^http://thetvdb.com/| ){
          ( $inetref )=( $entry->{url} =~ m|seriesid=(\d+)| );
          $system = 'thetvdb.com';
          $inetref = 'series/' . $inetref;
        }elsif( $entry->{url} =~ m|^http://www.themoviedb.org/| ){
          ( $inetref )=( $entry->{url} =~ m|movie/(\d+)| );
          $system = 'themoviedb.org';
          $inetref = 'movie/' . $inetref;
        }elsif( $entry->{url} =~ m|^http://www.tvrage.com//| ){
          ( $inetref )=( $entry->{url} =~ m|episodes/(\d+)| );
          $system = 'tvrage.com';
          $inetref = 'episode/' . $inetref;
        }
	  }

      # Only add if it exists
      if( $system ){
        $d->{'episodeNum'} = { xmltv_ns =>  norm($entry->{episode}),
        			     onscreen => $ep_text, $system => $inetref };
      } else {
        $d->{'episodeNum'} = { xmltv_ns =>  norm($entry->{episode}),
      			     onscreen => $ep_text };
      }

    }
    else {
      # This episode is only a segment and not a real episode.
      # I.e. " . . 0/2".
      $d->{'episodeNum'} = { xmltv_ns => norm($entry->{episode}) };
    }
  }
  
  if( defined( $entry->{program_type} ) and ($entry->{program_type} =~ /\S/) )
  {
    push @{$d->{category}->{en}}, $entry->{program_type};
  }
  elsif( defined( $chd->{def_pty} ) and ($chd->{def_pty} =~ /\S/) )
  {
    push @{$d->{category}->{en}}, $chd->{def_pty};
  }

  if( defined( $entry->{category} ) and ($entry->{category} =~ /\S/) )
  {
    push @{$d->{category}->{en}}, $entry->{category};
  }
  elsif( defined( $chd->{def_cat} ) and ($chd->{def_cat} =~ /\S/) )
  {
    push @{$d->{category}->{en}}, $chd->{def_cat};
  }

  if( defined( $entry->{production_date} ) and 
      ($entry->{production_date} =~ /\S/) )
  {
    $d->{date} = substr( $entry->{production_date}, 0, 4 );
  }

  if( $entry->{aspect} ne "unknown" )
  {
    $d->{video} = { aspect => $entry->{aspect} };
  }

  if( $entry->{directors} =~ /\S/ )
  {
    $d->{credits}->{director} = ParseCredits($entry->{directors});
  }

  if( $entry->{actors} =~ /\S/ )
  {
    $d->{credits}->{actor} = ParseCredits($entry->{actors});
  }

  if( $entry->{writers} =~ /\S/ )
  {
    $d->{credits}->{writer} = ParseCredits($entry->{writers});
  }

  if( $entry->{adapters} =~ /\S/ )
  {
    $d->{credits}->{adapter} = ParseCredits($entry->{adapters});
  }

  if( $entry->{producers} =~ /\S/ )
  {
    $d->{credits}->{producer} = ParseCredits($entry->{producers});
  }

  if( $entry->{presenters} =~ /\S/ )
  {
    $d->{credits}->{presenter} = ParseCredits($entry->{presenters});
  }

  if( $entry->{commentators} =~ /\S/ )
  {
    $d->{credits}->{commentator} = ParseCredits($entry->{commentators});
  }

  if( $entry->{guests} =~ /\S/ )
  {
    $d->{credits}->{guest} = ParseCredits($entry->{guests});
  }

  if( $entry->{url} )
  {
    $d->{url} = [ $entry->{url} ];

    # MythTV in case of no episodeNum
    my ($system, $inetref);
    if( $entry->{url} =~ m|^http://www.themoviedb.org/| ){
        ( $inetref )=( $entry->{url} =~ m|movie/(\d+)| );
        $system = 'themoviedb.org';
        $inetref = 'movie/' . $inetref;
    }
    # Only add if it exists
    if( $system and !defined $d->{'episodeNum'} and $entry->{url} =~ m|^http://www.themoviedb.org/| ){
        $d->{'episodeNum'} = { $system => $inetref };
    }
  }



  if( $entry->{star_rating} )
  {
    $d->{rating}->{stars} = $entry->{star_rating};
  }
  
  if( $entry->{rating} )
  {
    $d->{rating}->{mpaa} = $entry->{rating};
  }

  if( $entry->{previously_shown} )
  {
    $d->{previously_shown} = $entry->{previously_shown};
  }

  if( $entry->{country} )
  {
    $d->{country} = $entry->{country};
  }

  push @{$data}, $d;
}

sub ParseCredits
{
    my( $data ) = @_;

    my @credits = split( ", ", $data);
    my $return = [];

    foreach my $act (@credits)
    {
        my ( $role ) = ($act =~ /\((.*)\)$/);
        $act =~ s/\((.*?)\)$//;
        my $name = norm($act);

        push @{$return}, { role => norm($role), name => norm($name) };
    }

    return $return;
}

#
# Write description of all channels to channels.js.gz.
#
sub ExportChannelList
{
  my( $self ) = @_;
  my $ds = $self->{datastore};

  my $channels = {};

  my( $res, $sth ) = $ds->sa->Sql( "
      SELECT * from channels 
      WHERE export=1
      ORDER BY xmltvid" );

  while( my $data = $sth->fetchrow_hashref() )
  {
    $channels->{$data->{xmltvid}} = {
      "displayName" => {
	$self->{Language} => $data->{display_name}, 
      },
      "baseUrl" => $self->{RootUrl},
    };

    if( $data->{logo} )
    {
      $channels->{$data->{xmltvid}}->{icon} = $self->{IconRootUrl} . $data->{xmltvid} . ".png";
    }
  }

  my $fh = new IO::File("> $self->{Root}channels.js");
  my $js = JSON::XS->new;
  $js->ascii( 1 );
  $js->pretty( 1 );
  $fh->print( $js->encode( { jsontv => { channels => $channels } } ) );
  $fh->close();
  
  system("gzip -f -n $self->{Root}channels.js");
}

#
# Remove old js-files and js.gz-files. 
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
      ($file =~ /(\d\d\d\d-\d\d-\d\d)\.js(\.gz){0,1}/);

    if( defined( $date ) )
    {
      # Compare date-strings.
      if( $date lt $keep_date )
      {
        unlink( $file );
        $removed++;
      }
    }
  }

  p "Removed $removed files"
    if( $removed > 0 );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
  
