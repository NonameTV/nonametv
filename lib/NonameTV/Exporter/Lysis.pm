package NonameTV::Exporter::Lysis;

use strict;
use warnings;

=pod

The exporter for Lysis from Nagravision (www.nagravision.com) CMS system.

=cut

#use utf8;

use File::Util;
use IO::File;
use DateTime;
use File::Copy;
use Encode qw/encode decode/;
use Data::HexDump;
use Text::Truncate;
use XML::LibXML;
use Lingua::Translate;

use NonameTV::Exporter;
use NonameTV::Language qw/LoadLanguage/;
use NonameTV qw/norm/;
use DVB qw/DVBCategory/;

use NonameTV::Log qw/progress error d p w StartLogSection EndLogSection SetVerbosity/;

use base 'NonameTV::Exporter';

=pod

Export data in Lysis format.

Options:

  --verbose
    Show which datafiles are created.

  --epgserver <servername>
    Export data only for the epg server specified.

  --quiet 
    Show only fatal errors.

  --export-networks
    Print a list of all network information in xml-format.

  --remove-old
    Remove any old xml files from the output directory.

  --force-export
    Recreate all output files, not only the ones where data has
    changed.

  --exportedlist <filename>
    Write the list of files that have been updated to this file.

=cut 

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{Encoding} ) or die "You must specify Encoding.";
    #defined( $self->{DtdFile} ) or die "You must specify DtdFile.";
    defined( $self->{Root} ) or die "You must specify Root";
    defined( $self->{Language} ) or die "You must specify Language";

    $self->{MaxDays} = 365 unless defined $self->{MaxDays};
    $self->{MinDays} = $self->{MaxDays} unless defined $self->{MinDays};

    $self->{LastRequiredDate} = 
      DateTime->today->add( days => $self->{MinDays}-1 )->ymd("-");

    $self->{OptionSpec} = [ qw/export-networks remove-old force-export 
			    epgserver=s exportedlist=s
			    verbose quiet help/ ];

    $self->{OptionDefaults} = { 
      'export-networks' => 0,
      'remove-old' => 0,
      'force-export' => 0,
      'epgserver' => "",
      'help' => 0,
      'verbose' => 0,
      'quiet' => 0,
      'exportedlist' => "",
    };

    #LoadDtd( $self->{DtdFile} );

    my $ds = $self->{datastore};

    # Load language strings
    $self->{lngstr} = LoadLanguage( $self->{Language}, 
                                   "exporter-lysis", $ds );

    return $self;
}

sub Export
{
  my( $self, $p ) = @_;

  my $epgserver = $p->{'epgserver'};

  my $ds = $self->{datastore};

  if( $p->{'help'} )
  {
    print << 'EOH';
Export data in xml-format with one file per day and channel.

Options:

  --export-networks
    Generate an xml-file listing all network information.

  --epgserver <servername>
    Export data only for the epg server specified.

  --remove-old
    Remove all data-files for dates that have already passed.

  --force-export
    Export all data. Default is to only export data for batches that
    have changed since the last export.

EOH

    return;
  }

  SetVerbosity( $p->{verbose}, $p->{quiet} );

  StartLogSection( "Lysis", 0 );

  if( $p->{'export-networks'} )
  {
    $self->ExportNetworks( $epgserver );
    #return;
  }

  if( $p->{'remove-old'} )
  {
    $self->RemoveOld();
    #return;
  }

  my $exportedlist = $p->{'exportedlist'};
  if( $exportedlist ){
    $self->{exportedlist} = $exportedlist;
    progress("Lysis: The list of exported files will be available in '$exportedlist'");
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

  my $equery = "SELECT * from epgservers WHERE `active`=1 AND `type`='Lysis'";
  $equery .= " AND name='$epgserver'" if $epgserver;

  my( $eres, $esth ) = $ds->sa->Sql( $equery );

  while( my $edata = $esth->fetchrow_hashref() )
  {
    progress("Lysis: Exporting schedules for services on epg server '$edata->{name}'");

    my $nquery = "SELECT * from networks WHERE epgserver=$edata->{id} AND active=1";
    my( $nres, $nsth ) = $ds->sa->Sql( $nquery );
    while( my $ndata = $nsth->fetchrow_hashref() )
    {
      my $squery = "SELECT * from services WHERE network=$ndata->{id} AND active=1";
      my( $sres, $ssth ) = $ds->sa->Sql( $squery );
      while( my $sdata = $ssth->fetchrow_hashref() )
      {
        progress("Lysis: Exporting service $ndata->{id}/$sdata->{serviceid} - $sdata->{servicename}");
        $self->ExportData( $edata, $ndata, $sdata, $todo );
      }
      $ssth->finish();
    }
    $nsth->finish();
  }
  $esth->finish();

  $self->WriteState( $update_started );

  EndLogSection( "Lysis" );
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
  my( $edata, $ndata, $sdata, $todo ) = @_;

  my $ds = $self->{datastore};

  foreach my $channel (keys %{$todo}) {

    # only export files for the channel
    # which is used as the source for this service
    next if ( $sdata->{dbchid} ne $channel );

    my $chd = $ds->sa->Lookup( "channels", { id => $channel } );

    foreach my $date (sort keys %{$todo->{$channel}}) {
      $self->ExportFile( $edata, $ndata, $sdata, $chd, $date );
    }
  }
}

sub ReadState {
  my $self = shift;

  my $ds = $self->{datastore};
 
  my $last_update = $ds->sa->Lookup( 'state', { name => "lysis_last_update" },
                                 'value' );

  if( not defined( $last_update ) )
  {
    $ds->sa->Add( 'state', { name => "lysis_last_update", value => 0 } );
    $last_update = 0;
  }

  return $last_update;
}

sub WriteState {
  my $self = shift;
  my( $update_started ) = @_;

  my $ds = $self->{datastore};

  $ds->sa->Update( 'state', { name => "lysis_last_update" }, 
               { value => $update_started } );
}

sub ReadLastEventId {
  my $self = shift;
  my( $sid ) = @_;

  my $ds = $self->{datastore};
 
  my $lastno = $ds->sa->Lookup( 'services', { id => $sid }, 'lasteventid' );

  if( not defined( $lastno ) )
  {
    $lastno = 0;
    $self->WriteLastEventId( $sid, $lastno );
  }

  return $lastno;
}

sub WriteLastEventId {
  my $self = shift;
  my( $sid, $lastno ) = @_;

  my $ds = $self->{datastore};

  $ds->sa->Update( 'services', { id => $sid }, { lasteventid => $lastno } );
}

sub EventDuration {
  my( $start, $end ) = @_;

  my( $year1, $month1, $day1, $hour1, $min1, $sec1 ) = ( $start =~ /^(\d+)-(\d+)-(\d+)\s+(\d+):(\d+):(\d+)$/ );
  my( $year2, $month2, $day2, $hour2, $min2, $sec2 ) = ( $end =~ /^(\d+)-(\d+)-(\d+)\s+(\d+):(\d+):(\d+)$/ );

  my $dt1 = DateTime->new(
                       year => $year1,
                       month => $month1,
                       day => $day1,
                       hour => $hour1,
                       minute => $min1,
                       second => $sec1,
                       time_zone => "Europe/Zagreb"
  );

  my $dt2 = DateTime->new(
                       year => $year2,
                       month => $month2,
                       day => $day2,
                       hour => $hour2,
                       minute => $min2,
                       second => $sec2,
                       time_zone => "Europe/Zagreb"
  );

  my $duration = $dt2 - $dt1;

  return $duration->in_units( 'minutes' ) * 60;
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

  logdie( "Lysis: Unknown time format $str" )
    unless defined $day;

  return DateTime->new(
                       year => $year,
                       month => $month,
                       day => $day,
                       time_zone => $tz );
}

#######################################################
#
# Lysis-specific methods.
#

sub ExportFile {
  my $self = shift;
  my( $edata, $ndata, $sdata, $chd, $date ) = @_;

  my $startdate = $date;
  my $enddate = create_dt( $date, 'UTC' )->add( days => 1 )->ymd('-');

  my( $res, $sth ) = $self->{datastore}->sa->Sql( "
        SELECT * from programs
        WHERE (channel_id = ?) 
          and (start_time >= ?)
          and (start_time < ?) 
        ORDER BY start_time", 
      [$chd->{id}, "$startdate 00:00:00", "$enddate 23:59:59"] );
  
  my ( $odoc, $root ) = $self->CreateWriter( $edata, $ndata, $sdata, $chd, $date );

  my $dp = $odoc->createElement( 'DownloadPeriod' );
  $dp->setAttribute( 'action' , "override" );
  $dp->setAttribute( 'serviceRef' , $sdata->{serviceid} );
  $dp->setAttribute( 'type' , "turnaround" );
  $root->appendChild( $dp );

  my $per = $odoc->createElement( 'Period' );
  $per->setAttribute( 'start' , $startdate . "T00:00:00Z" );
  $per->setAttribute( 'end' , $startdate . "T23:59:59Z" );
  $dp->appendChild( $per );

  my $done = 0;

  my $d1 = $sth->fetchrow_hashref();

  if( (not defined $d1) or ($d1->{start_time} gt "$startdate 23:59:59") ) {
    $self->CloseWriter( $odoc );
    $sth->finish();
    return;
  }

  my $lasteventid = $self->ReadLastEventId( $sdata->{id} );

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
      error( "Lysis: Adjusted endtime for $chd->{xmltvid}: " . 
             "$d1->{end_time} => $d2->{start_time}" );

      $d1->{end_time} = $d2->{start_time}
    }        
      

    $self->WriteEntry( $odoc, $dp, $d1, $chd, $lasteventid )
      unless $d1->{title} eq "end-of-transmission";

    if( $d2->{start_time} gt "$startdate 23:59:59" ) {
      $done = 1;
      last;
    }
    $d1 = $d2;

    $lasteventid++;
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
      $self->WriteEntry( $odoc, $dp, $d1, $chd, $lasteventid )
        unless $d1->{title} eq "end-of-transmission";

      $lasteventid++;
    }
    else
    {
      error( "Lysis: Missing end-time for last entry for " .
             "$chd->{xmltvid}_$date" ) 
	  unless $date gt $self->{LastRequiredDate};
    }
  }

  $self->WriteLastEventId( $sdata->{id}, $lasteventid );

  $self->CloseWriter( $odoc );
  $sth->finish();
}

sub CreateWriter
{
  my $self = shift;
  my( $edata, $ndata, $sdata, $chd, $date ) = @_;

  my $xmltvid = $chd->{xmltvid};

  my $path = $self->{Root} . "/" . $edata->{name};
  my $filename = sprintf( "EPG%d_NET%d_SID%d_%s.xml", $edata->{id}, $ndata->{nid}, $sdata->{serviceid}, $date );

  #progress( "Lysis: $filename" );

  $self->{writer_path} = $path;
  $self->{writer_filename} = $filename;
  $self->{writer_entries} = 0;

  # Make sure that writer_entries is always true if we don't require data
  # for this date.
  $self->{writer_entries} = "0 but true" 
    if( ($date gt $self->{LastRequiredDate}) or $chd->{empty_ok} );

  my $odoc = XML::LibXML::Document->new( "1.0", $ndata->{charset} );
  $self->{networkcharset} = $ndata->{charset};

  my $c1 = $odoc->createComment( " Created by Gonix (www.gonix.net) at " . DateTime->now . " " );
  $odoc->appendChild( $c1 );

  my $c2 = $odoc->createComment( " Schedule for '" . $sdata->{servicename} . "' service at EPG server '" . $edata->{name}. "' ");
  $odoc->appendChild( $c2 );

  #my $dtd  = $odoc->createInternalSubset( "event-information", undef, "event-information.dtd" );

  my $root = $odoc->createElement('ScheduleProvider');
  $root->setAttribute( 'id' => "1" );
  $root->setAttribute( 'name' => "Gonix" );
  $root->setAttribute( 'scheduleDate' => DateTime->now . "Z" );
  $root->setAttribute( 'xmlns:xsi' => "http://www.w3.org/2001/XMLSchema-instance" );
  $odoc->setDocumentElement($root);
  
  return($odoc, $root);
}

sub CloseWriter
{
  my $self = shift;
  my( $w ) = @_;

  my $path = $self->{writer_path};
  my $filename = $self->{writer_filename};
  delete $self->{writer_filename};
  my $networkcharset = $self->{networkcharset};

  my $docstring = $w->toString( 1 );

  open( my $fh, '>', $path . "/" . $filename . ".new" );
  binmode $fh;
  print $fh $docstring;
  close( $fh );

  #progress("Lysis: Service schedule exported to $filename");

  if( -f "$path/$filename" )
  {
    system("diff $path/$filename.new $path/$filename > /dev/null");
    if( $? )
    {
      move( "$path/$filename.new", "$path/$filename" );
      progress( "Lysis: Exported $filename" );
      if( not $self->{writer_entries} )
      {
        error( "Lysis: $filename is empty" );
      }
      elsif( $self->{writer_entries} > 0 )
      {
      }
    }
    else
    {
      unlink( "$path/$filename.new" );
    }
  }
  else
  {
    move( "$path/$filename.new", "$path/$filename" );
    progress( "Lysis: Exported $filename" );
    if( not $self->{writer_entries} )
    {
      error( "Lysis: $filename is empty" );
    }
    elsif( $self->{writer_entries} > 0 )
    {
    }
  }

  if( $self->{exportedlist} ){
    $self->ExportFileNameToList( "$path/$filename" );
  }
}

sub WriteEntry
{
  my $self = shift;
  my( $odoc, $parent, $data, $chd, $evno ) = @_;

  my $ds = $self->{datastore};

  Lingua::Translate::config
  (
    back_end => 'Google',
    #api_key  => '',
    referer  => 'http://www.gonix.net/',
  );

  my $xl8r = Lingua::Translate->new( src => $chd->{sched_lang}, dest => 'en' );

  $self->{writer_entries}++;

  my $networkcharset = $self->{networkcharset};

  my $start_time = create_dt( $data->{start_time}, "UTC" );
  $start_time->set_time_zone( "Europe/Zagreb" );
  
  my $end_time = create_dt( $data->{end_time}, "UTC" );
  $end_time->set_time_zone( "Europe/Zagreb" );
  
  my $duration = EventDuration( $data->{start_time}, $data->{end_time} );

  my $programme = $odoc->createElement( 'Programme' );
  $programme->setAttribute( 'isCatchUp' => "false" );
  $programme->setAttribute( 'id' => $data->{schedule_id} || $evno );
  $programme->setAttribute( 'title' => $data->{title} );
  $parent->appendChild( $programme );

    my $per = $odoc->createElement( 'Period' );
    $per->setAttribute( 'start' , $start_time . "Z" );
    $per->setAttribute( 'duration' , $duration );
    $programme->appendChild( $per );

    my $epgdesc;

    $epgdesc = $odoc->createElement( 'EpgDescription' );
    $programme->appendChild( $epgdesc );

      my $epgel;

      $epgel = $odoc->createElement( 'EpgElement' );
      $epgel->setAttribute( 'key' , "SeriesId" );
      $epgel->appendText( $data->{title_id} || 0 );
      $epgdesc->appendChild( $epgel );

      $epgel = $odoc->createElement( 'EpgElement' );
      $epgel->setAttribute( 'key' , "Episode_Number_Display" );
      if( $data->{episode} ){
        my( $epno ) = ( $data->{episode} =~ /^.*\.\s+(\d+)\s+\..*$/ );
        $epgel->appendText( $epno );
      } else {
        $epgel->appendText( 0 );
      }
      $epgdesc->appendChild( $epgel );

      $epgel = $odoc->createElement( 'EpgElement' );
      $epgel->setAttribute( 'key' , "Rating" );
      $epgel->appendText( $data->{rating} || 0 );
      $epgdesc->appendChild( $epgel );

      my $dvbcategory = DVBCategory( $ds, $data->{category}, $data->{program_type} );
      $epgel = $odoc->createElement( 'EpgElement' );
      $epgel->setAttribute( 'key' , "DVB_Content" );
      $epgel->appendText( $dvbcategory );
      $epgdesc->appendChild( $epgel );

    # local Epg title and description
    $epgdesc = $odoc->createElement( 'EpgDescription' );
    $epgdesc->setAttribute( 'locale' , $chd->{sched_lang} . "_" . uc( $chd->{sched_lang} ) || "en_GB" );
    $programme->appendChild( $epgdesc );

      $epgel = $odoc->createElement( 'EpgElement' );
      $epgel->setAttribute( 'key' , "Title" );
      $epgel->appendText( $data->{title} );
      $epgdesc->appendChild( $epgel );

      $epgel = $odoc->createElement( 'EpgElement' );
      $epgel->setAttribute( 'key' , "Description" );
      $epgel->appendText( $data->{description} || "" );
      $epgdesc->appendChild( $epgel );

#    # English Epg title and description
#    $epgdesc = $odoc->createElement( 'EpgDescription' );
#    $epgdesc->setAttribute( 'locale' , "en_GB" );
#    $programme->appendChild( $epgdesc );
#
#      $epgel = $odoc->createElement( 'EpgElement' );
#      $epgel->setAttribute( 'key' , "Title" );
#      $epgel->appendText( $xl8r->translate( $data->{title} ) );
#      $epgdesc->appendChild( $epgel );
#
#      $epgel = $odoc->createElement( 'EpgElement' );
#      $epgel->setAttribute( 'key' , "Description" );
#      $epgel->appendText( $xl8r->translate( "Bok Pero" ) );
#      $epgdesc->appendChild( $epgel );

# transcoding
#      my $enctitle;
#      $enctitle = myEncode( $networkcharset, $data->{title} );
#      $epgel->appendText( $enctitle );

}

sub ExportFileNameToList
{
  my( $self ) = shift;
  my( $filename ) = @_;

  open( ELF, '>>' . $self->{exportedlist} );
  print ELF "$filename\n";
  close( ELF ); 
}

#
# Write description of all networks to networks.xml
#
sub ExportNetworks
{
  my( $self ) = shift;
  my( $epgserver ) = @_;

  my $ds = $self->{datastore};

  my $now = my $keep_date = DateTime->now;

  my $odoc = XML::LibXML::Document->new( "1.0", $self->{Encoding} );

  my $c1 = $odoc->createComment( " Created by Gonix (www.gonix.net) at " . DateTime->now . " " );
  $odoc->appendChild( $c1 );

  my $dtd  = $odoc->createInternalSubset( "network-information", undef, "network-information.dtd" );

  my $root = $odoc->createElement('network-information');
  $odoc->setDocumentElement($root);

  my $equery = "SELECT * from epgservers WHERE active=1";
  $equery .= " AND name='$epgserver'" if $epgserver;

  my( $eres, $esth ) = $ds->sa->Sql( $equery );

  while( my $edata = $esth->fetchrow_hashref() )
  {
    progress("Lysis: Exporting network information for epg server '$edata->{name}'");

    my $nquery = "SELECT * from networks WHERE epgserver=$edata->{id} AND active=1";
    my( $nres, $nsth ) = $ds->sa->Sql( $nquery );
    while( my $ndata = $nsth->fetchrow_hashref() )
    {
      progress("Lysis: Exporting network $ndata->{id} ($ndata->{name})");

      my $net = $odoc->createElement( 'network' );
      $net->setAttribute( 'network-id' => $ndata->{id} );
      $net->setAttribute( 'operator' => $ndata->{operator} );
      $net->setAttribute( 'description' => $ndata->{description} );
      $net->setAttribute( 'character-set' => $ndata->{charset} );
      $root->appendChild( $net );

      my $lt = $odoc->createElement( 'local-time' );
      $lt->setAttribute( 'country-code' => '900' );
      $lt->setAttribute( 'country-region-id' => '0' );
      $lt->setAttribute( 'local-time-offset-polarity' => 'NEGATIVE' );
      $lt->setAttribute( 'local-time-offset' => '60' );
      $lt->setAttribute( 'time-of-change' => $now->ymd('-') . " " . $now->hms(':') );
      $lt->setAttribute( 'next-time-offset' => '120' );
      $net->appendChild( $lt );

      my $squery = "SELECT * from services WHERE network=$ndata->{id} AND active=1";
      my( $sres, $ssth ) = $ds->sa->Sql( $squery );
      while( my $sdata = $ssth->fetchrow_hashref() )
      {
        progress("Lysis: Adding service $sdata->{id} ($sdata->{servicename}) to network $ndata->{id}");

        my $srv = $odoc->createElement( 'service' );
        $srv->setAttribute( 'service-name' => $sdata->{servicename} );
        $srv->setAttribute( 'logical-channel-number' => $sdata->{logicalchannelnumber} );
        $srv->setAttribute( 'service-id' => $sdata->{serviceid} );
        $srv->setAttribute( 'description' => $sdata->{description} );
        $srv->setAttribute( 'nvod' => $sdata->{nvod} );
        $srv->setAttribute( 'service-type-id' => $sdata->{servicetypeid} );
        $net->appendChild( $srv );
      }
    }

    my $outfile = "$self->{Root}/$edata->{name}/network-information.xml";
    open( my $fh, '>:encoding(' . $self->{Encoding} . ')', $outfile )
      or logdie( "Lysis: cannot write to $outfile" );

    $odoc->toFH( $fh, 1 );
    close( $fh );

    progress("Lysis: Network information exported to $outfile");
  }
}

#
# Remove old xml-files and xml files. 
#
sub RemoveOld
{
  my( $self ) = @_;

  my $removed = 0;
  my $ds = $self->{datastore};
 
  # Keep files for the last week.
  my $keep_date = DateTime->today->subtract( days => 8 )->ymd("-");

  my $f = File::Util->new();

  my @dirs = $f->list_dir( $self->{Root}, '--no-fsdots' );
  foreach my $dir( @dirs ){

  my $ftype = join(',', File::Util->file_type( $self->{Root} . "/" . $dir ) );
    if( $ftype =~ /DIRECTORY/ )
    {
      progress( "Lysis: Removing old files in directory $dir" );

      my @files = glob( $self->{Root} . "/$dir/" . "*" );
      foreach my $file (@files)
      {
        my($date) = ($file =~ /(\d\d\d\d-\d\d-\d\d)\.xml/);

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
    }
  }

  progress( "Lysis: Removed $removed files" ) if( $removed > 0 );
}

sub myEncode
{
  my( $encoding, $str ) = @_;
#print "\n----------------------------------------------------------\n$str\n";

  #hdump( $str );

  my $encstr = encode( $encoding, $str );

  #hdump( $encstr );

  return $encstr;
}

sub hdump {
    my $offset = 0;
    my(@array,$format);
    foreach my $data (unpack("a16"x(length($_[0])/16)."a*",$_[0])) {
        my($len)=length($data);
        if ($len == 16) {
            @array = unpack('N4', $data);
            $format="0x%08x (%05d)   %08x %08x %08x %08x   %s\n";
        } else {
            @array = unpack('C*', $data);
            $_ = sprintf "%2.2x", $_ for @array;
            push(@array, '  ') while $len++ < 16;
            $format="0x%08x (%05d)" .
               "   %s%s%s%s %s%s%s%s %s%s%s%s %s%s%s%s   %s\n";
        } 
        $data =~ tr/\0-\37\177-\377/./;
        printf $format,$offset,$offset,@array,$data;
        $offset += 16;
    }
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
  
