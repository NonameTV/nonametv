package NonameTV::Exporter::RSS;

use strict;
use warnings;

use utf8;

use IO::File;
use DateTime;
use XML::RSS;
use File::Copy;

use NonameTV::Exporter;
use NonameTV::Language qw/LoadLanguage/;
use NonameTV qw/norm/;

use NonameTV::Log qw/progress error d p w StartLogSection EndLogSection SetVerbosity/;

use base 'NonameTV::Exporter';

=pod

Export data in RSS format.

Options:

  --verbose
    Show which datafiles are created.

  --quiet 
    Show only fatal errors.

  --export-nowongroup
    Print a list of all channels in xml-format to stdout.

  --export-todayongroup
    Print a list of all channels in xml-format to stdout.

  --remove-old

  --force-export
    Recreate all output files, not only the ones where data has
    changed.

=cut 

$XMLTV::ValidateFile::REQUIRE_CHANNEL_ID = 0;

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{Encoding} ) or die "You must specify Encoding.";
    #defined( $self->{DtdFile} ) or die "You must specify DtdFile.";
    defined( $self->{Root} ) or die "You must specify Root";
    defined( $self->{RootUrl} ) or die "You must specify RootUrl";
    defined( $self->{CopyRight} ) or die "You must specify CopyRight";
    defined( $self->{Language} ) or die "You must specify Language";
    defined( $self->{NowOnChannelUrl} ) or die "You must specify NowOnChannelUrl";
    defined( $self->{TodayOnChannelUrl} ) or die "You must specify TodayOnChannelUrl";
    defined( $self->{ImagesUrl} ) or die "You must specify ImagesUrl";

    $self->{MaxDays} = 365 unless defined $self->{MaxDays};
    $self->{MinDays} = $self->{MaxDays} unless defined $self->{MinDays};

    $self->{LastRequiredDate} = 
      DateTime->today->add( days => $self->{MinDays}-1 )->ymd("-");

    $self->{OptionSpec} = [ qw/export-nowongroup export-todayongroup 
			       remove-old force-export 
                               verbose quiet help/ ];

    $self->{OptionDefaults} = { 
      'export-nowongroup' => 0,
      'export-todayongroup' => 0,
      'remove-old' => 0,
      'force-export' => 0,
      'help' => 0,
      'verbose' => 0,
      'quiet' => 0,
    };

    #LoadDtd( $self->{DtdFile} );

    my $ds = $self->{datastore};

    # Load language strings
    $self->{lngstr} = LoadLanguage( $self->{Language}, "exporter-rss", $ds );

    return $self;
}

sub Export
{
  my( $self, $p ) = @_;

  if( $p->{'help'} )
  {
    print << 'EOH';
Export data in RSS with one file per day and channel.

Options:

  --export-nowongroup
    Generate an xml-file listing all channels and their corresponding
    base url.

  --export-todayongroup
    Generate an xml-file listing all channels and their corresponding
    base url.

  --remove-old

  --force-export
    Export all data. Default is to only export data for batches that
    have changed since the last export.

EOH

    return;
  }

  SetVerbosity( $p->{verbose}, $p->{quiet} );

  StartLogSection( "RSS", 0 );

  if( $p->{'export-nowongroup'} )
  {
    $self->ExportNowOnGroup();
    return;
  }

  if( $p->{'export-todayongroup'} )
  {
    $self->ExportTodayOnGroup();
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
  }

  $self->ExportData( $todo );

  $self->WriteState( $update_started );

  EndLogSection( "RSS" );
}


# Find all dates for each channel
sub FindAll {
  my $self = shift;
  my( $todo ) = @_;

  my $ds = $self->{datastore};

  my ( $res, $channels ) = $ds->sa->Sql("select id from channels where export=1");

  my $first_date = DateTime->today; 
  my $last_date = $first_date->clone();

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

  my $first_date = DateTime->today; 
  my $last_date = $first_date->clone();

  while( my $data = $update_batches->fetchrow_hashref() ) {
    add_dates( $todo, $data->{channel_id}, 
               $data->{min_start}, $data->{max_start}, 
               $first_date, $last_date );
  }

  $update_batches->finish();
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

  my $last_update = $ds->sa->Lookup( 'state', { name => "rss_last_update" },
                                 'value' );

  if( not defined( $last_update ) )
  {
    $ds->sa->Add( 'state', { name => "rss_last_update", value => 0 } );
    $last_update = 0;
  }

  return $last_update;
}

sub WriteState {
  my $self = shift;
  my( $update_started ) = @_;

  my $ds = $self->{datastore};

  $ds->sa->Update( 'state', { name => "rss_last_update" }, 
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

  die( "RSS: Unknown time format $str" )
    unless defined $day;

  return DateTime->new(
                       year => $year,
                       month => $month,
                       day => $day,
                       time_zone => $tz );
}

#######################################################
#
# RSS-specific methods.
#

sub ExportFile {
  my $self = shift;
  my( $chd, $date ) = @_;

  my $startdate = $date;
  my $now = DateTime->now();

  $self->{filename} =  "todayon-" . $chd->{xmltvid} . ".xml";

  my( $res, $sth ) = $self->{datastore}->sa->Sql( "
        SELECT * from programs
        WHERE (channel_id = ?) 
          and (start_time >= ?)
          and (start_time < ?) 
        ORDER BY start_time", 
      [$chd->{id}, "$startdate 00:00:00", "$startdate 23:59:59"] );
  
  progress("RSS: creating today on channel file for $chd->{xmltvid}");

  my $rss = new XML::RSS (version => '2.0');

  $rss->channel(
    title          => $self->{lngstr}->{todayon} . " " . $chd->{display_name} . " (" . $chd->{xmltvid} . ")",
    link           => $self->{RootUrl},
    language       => $self->{Language},
    description    => $self->{lngstr}->{todayon} . " " . $chd->{display_name} . " - " . $chd->{xmltvid},
    copyright      => $self->{CopyRight},
    pubDate        => $now->dmy('-') . ' ' . $now->hms(':'),
    lastBuildDate  => $now->dmy('-') . ' ' . $now->hms(':'),
    managingEditor => $self->{AdminEmail},
    webMaster      => $self->{AdminEmail},
  );

  $rss->image(
    title       => $chd->{display_name},
    url         => $self->{ImagesUrl} . "/" . $chd->{xmltvid} . ".png",
    link        => $self->{RootUrl},
    width       => 16,
    height      => 16,
    description => $chd->{display_name},
  );

  my $done = 0;

  my $d1 = $sth->fetchrow_hashref();

  if( (not defined $d1) or ($d1->{start_time} gt "$startdate 23:59:59") ) {
    $self->CloseWriter( $rss );
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
      error( "RSS: Adjusted endtime for $chd->{xmltvid}: " . 
             "$d1->{end_time} => $d2->{start_time}" );

      $d1->{end_time} = $d2->{start_time}
    }        
      

    $self->WriteEntry( $rss, $d1, $chd )
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
      $self->WriteEntry( $rss, $d1, $chd )
        unless $d1->{title} eq "end-of-transmission";
    }
    else
    {
      error( "RSS: Missing end-time for last entry for " .
             "$chd->{xmltvid}_$date" ) 
	  unless $date gt $self->{LastRequiredDate};
    }
  }

  $self->CloseWriter( $rss );
  $sth->finish();
}

sub CloseWriter
{
  my $self = shift;
  my( $rss ) = @_;

  my $path = $self->{Root};
  my $filename = $self->{filename};
  delete $self->{filename};

  #print $rss->as_string;
  print $rss->save( $path . "/" . $filename );
}

sub WriteEntry
{
  my $self = shift;
  my( $rss, $data, $chd ) = @_;

  $self->{writer_entries}++;

  my $from = create_dt( $data->{start_time}, 'UTC' );
  $from->set_time_zone( $self->{TimeZone} );
  my $epochtime = $from->clone->subtract( seconds => $from->offset )->epoch;

  my $to = create_dt( $data->{end_time}, 'UTC' );
  $to->set_time_zone( $self->{TimeZone} );

  $rss->add_item(
    title => $from->hms(':') . " - " . $to->hms(':') . " : " . $data->{title},
    link => $self->{ViewProgramUrl} . "?channel=" . $chd->{id} . "&time=" . $epochtime,
    description => $data->{description},
  );
}

#
# Export NowOnGroup
#
sub ExportNowOnGroup
{
  my( $self ) = @_;
  my $ds = $self->{datastore};

  my $dt = DateTime->now();

  ## format the output
  ## one file per each channel group
  ## each item is the channel that belongs to that channel group

  my( $res, $sth ) = $ds->sa->Sql( "
      SELECT * from channelgroups
      WHERE 1
      ORDER BY abr" );

  while( my $gdata = $sth->fetchrow_hashref() )
  {
    progress("RSS: creating RSS channel group file for group $gdata->{abr}");

    my $rss = new XML::RSS (version => '2.0');

    $rss->channel(
      title          => $self->{lngstr}->{nowonchgroup} . " " . $gdata->{abr},
      link           => $self->{RootUrl},
      language       => $self->{Language},
      description    => $self->{lngstr}->{nowonchgroup} . " " . $gdata->{abr} . " - " . $gdata->{display_name},
      copyright      => $self->{CopyRight},
      pubDate        => $dt->dmy('-') . ' ' . $dt->hms(':'),
      lastBuildDate  => $dt->dmy('-') . ' ' . $dt->hms(':'),
      managingEditor => $self->{AdminEmail},
      webMaster      => $self->{AdminEmail},
    );
  
    my( $cres, $csth ) = $ds->sa->Sql( "
        SELECT * from channels
        WHERE `chgroup`='$gdata->{abr}'
        AND export=1
        ORDER BY xmltvid" );

    while( my $cdata = $csth->fetchrow_hashref() )
    {
      #progress("RSS: adding item $cdata->{xmltvid}");

      $rss->add_item(
        title => $cdata->{display_name},
        link => $self->{NowOnChannelUrl} . $cdata->{id},
        description => $cdata->{xmltvid} . " - " . $cdata->{display_name}
      );
    }

    # save it to file
    $rss->save( $self->{Root} . "/nowongroup-" . $gdata->{abr} . ".xml" );
  }
}

#
# Export TodayOnGroup
#
sub ExportTodayOnGroup
{
  my( $self ) = @_;
  my $ds = $self->{datastore};

  my $dt = DateTime->now();

  ## format the output
  ## one file per each channel group
  ## each item is the channel that belongs to that channel group

  my( $res, $sth ) = $ds->sa->Sql( "
      SELECT * from channelgroups
      WHERE 1
      ORDER BY abr" );

  while( my $gdata = $sth->fetchrow_hashref() )
  {
    progress("RSS: creating RSS channel group file for group $gdata->{abr}");

    my $rss = new XML::RSS (version => '2.0');

    $rss->channel(
      title          => $self->{lngstr}->{todayonchgroup} . " " . $gdata->{abr},
      link           => $self->{RootUrl},
      language       => $self->{Language},
      description    => $self->{lngstr}->{todayonchgroup} . " " . $gdata->{abr} . " - " . $gdata->{display_name},
      copyright      => $self->{CopyRight},
      pubDate        => $dt->dmy('-') . ' ' . $dt->hms(':'),
      lastBuildDate  => $dt->dmy('-') . ' ' . $dt->hms(':'),
      managingEditor => $self->{AdminEmail},
      webMaster      => $self->{AdminEmail},
    );
  
    my( $cres, $csth ) = $ds->sa->Sql( "
        SELECT * from channels
        WHERE `chgroup`='$gdata->{abr}'
        AND export=1
        ORDER BY xmltvid" );

    while( my $cdata = $csth->fetchrow_hashref() )
    {
      #progress("RSS: adding item $cdata->{xmltvid}");

      $rss->add_item(
        title => $cdata->{display_name},
        link => $self->{TodayOnChannelUrl} . $cdata->{id},
        description => $cdata->{xmltvid} . " - " . $cdata->{display_name}
      );
    }

    # save it to file
    $rss->save( $self->{Root} . "/todayongroup-" . $gdata->{abr} . ".xml" );
  }
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

  my @files = glob( $self->{Root} . "/todayon-*" );
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
        unlink( $file );
        $removed++;
      }
    }
  }

  progress( "RSS: Removed $removed files" )
    if( $removed > 0 );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
  
