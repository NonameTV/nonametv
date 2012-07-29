package NonameTV::Exporter::Dreampark;

use strict;
use warnings;

=pod

The exporter for Dreampark (www.dreampark.com) middleware.

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

use NonameTV::Exporter;
use NonameTV::Language qw/LoadLanguage/;
use NonameTV qw/norm/;

use NonameTV::Log qw/progress error d p w StartLogSection EndLogSection SetVerbosity/;

use base 'NonameTV::Exporter';

=pod

Export data in xml format.

Options:

  --verbose
    Show which datafiles are created.

  --epgserver <servername>
    Export data only for the epg server specified.

  --quiet 
    Show only fatal errors.

  --export-metadata
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

    $self->{OptionSpec} = [ qw/export-metadata remove-old force-export 
			    epgserver=s exportedlist=s
			    verbose quiet help/ ];

    $self->{OptionDefaults} = { 
      'export-metadata' => 0,
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
                                   "exporter-dreampark", $ds );

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

  --export-metadata
    Generate an xml-file with Dreampark metadata

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

  StartLogSection( "Dreampark", 0 );

  if( $p->{'export-metadata'} )
  {
    $self->ExportMetaDataFile( $epgserver );
    return;
  }

  if( $p->{'remove-old'} )
  {
    $self->RemoveOld();
    return;
  }

  my $exportedlist = $p->{'exportedlist'};
  if( $exportedlist ){
    $self->{exportedlist} = $exportedlist;
    progress("Dreampark: The list of exported files will be available in '$exportedlist'");
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

  my $equery = "SELECT * from epgservers WHERE `active`=1 AND `type`='Dreampark'";
  $equery .= " AND name='$epgserver'" if $epgserver;

  my( $eres, $esth ) = $ds->sa->Sql( $equery );

  while( my $edata = $esth->fetchrow_hashref() )
  {
    progress("Dreampark: Exporting schedules for services on epg server '$edata->{name}'");
    $self->{epgserver} = $edata->{name};

    my $nquery = "SELECT * from networks WHERE epgserver=$edata->{id} AND active=1";
    my( $nres, $nsth ) = $ds->sa->Sql( $nquery );
    while( my $ndata = $nsth->fetchrow_hashref() )
    {
      my $squery = "SELECT * from services WHERE network=$ndata->{id} AND active=1";
      my( $sres, $ssth ) = $ds->sa->Sql( $squery );
      while( my $sdata = $ssth->fetchrow_hashref() )
      {
        #progress("Dreampark: Exporting service $ndata->{id}/$sdata->{serviceid} - $sdata->{servicename}");
        $self->ExportData( $edata, $ndata, $sdata, $todo );
      }
      $ssth->finish();
    }
    $nsth->finish();
  }
  $esth->finish();

  $self->WriteState( $update_started );

  EndLogSection( "Dreampark" );
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
      my $odoc = $self->CreateWriter( $edata, $ndata, $sdata, $chd, $date );
      my $fragment = $odoc->createDocumentFragment();

      $self->ExportMetaData( $chd, $odoc, $fragment, $ndata );
      $self->ExportPrograms( $chd, $odoc, $fragment, $sdata, $date );

      $self->CloseWriter( $odoc, $fragment );
    }
  }
}

sub ReadState {
  my $self = shift;

  my $ds = $self->{datastore};
 
  my $last_update = $ds->sa->Lookup( 'state', { name => "dreampark_last_update" },
                                 'value' );

  if( not defined( $last_update ) )
  {
    $ds->sa->Add( 'state', { name => "dreampark_last_update", value => 0 } );
    $last_update = 0;
  }

  return $last_update;
}

sub WriteState {
  my $self = shift;
  my( $update_started ) = @_;

  my $ds = $self->{datastore};

  $ds->sa->Update( 'state', { name => "dreampark_last_update" }, 
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

sub EventStartTime {
  my( $text ) = @_;

  my( $year, $month, $day, $hour, $min, $sec ) = ( $text =~ /^(\d+)-(\d+)-(\d+)\s+(\d+):(\d+):(\d+)$/ );

  my $dt = DateTime->new(
                       year => $year,
                       month => $month,
                       day => $day,
                       hour => $hour,
                       minute => $min,
                       second => $sec,
                       time_zone => "Europe/Zagreb"
  );

  return sprintf( "%04d-%02d-%02dT%02d:%02d:%02dZ" , $year, $month, $day, $hour, $min, $sec );
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

  return $duration->delta_minutes;
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

  die( "Dreampark: Unknown time format $str" )
    unless defined $day;

  return DateTime->new(
                       year => $year,
                       month => $month,
                       day => $day,
                       time_zone => $tz );
}

#######################################################
#
# Dreampark-specific methods.
#

sub ExportPrograms {
  my $self = shift;
  my( $chd, $odoc, $frag, $sdata, $date ) = @_;

  my $programs = $odoc->createElement( 'programs' );
  $frag->appendChild( $programs );

  $self->ExportFile( $chd, $odoc, $programs, $sdata, $date );
}

sub ExportFile {
  my $self = shift;
  my( $chd, $odoc, $node, $sdata, $date ) = @_;

  my $startdate = $date;
  my $enddate = create_dt( $date, 'UTC' )->add( days => 1 )->ymd('-');

  my( $res, $sth ) = $self->{datastore}->sa->Sql( "
        SELECT * from programs
        WHERE (channel_id = ?) 
          and (start_time >= ?)
          and (start_time < ?) 
        ORDER BY start_time", 
      [$chd->{id}, "$startdate 00:00:00", "$enddate 23:59:59"] );
  
  my $done = 0;

  my $d1 = $sth->fetchrow_hashref();

  if( (not defined $d1) or ($d1->{start_time} gt "$startdate 23:59:59") ) {
    $self->CloseWriter( $odoc, $node );
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
      error( "Dreampark: Adjusted endtime for $chd->{xmltvid}: " . 
             "$d1->{end_time} => $d2->{start_time}" );

      $d1->{end_time} = $d2->{start_time}
    }        
      

    $self->WriteEntry( $odoc, $node, $d1, $chd, $lasteventid )
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
      $self->WriteEntry( $odoc, $node, $d1, $chd, $lasteventid )
        unless $d1->{title} eq "end-of-transmission";

      $lasteventid++;
    }
    else
    {
      error( "Dreampark: Missing end-time for last entry for " .
             "$chd->{xmltvid}_$date" ) 
	  unless $date gt $self->{LastRequiredDate};
    }
  }

  $self->WriteLastEventId( $sdata->{id}, $lasteventid );

  $sth->finish();
}

sub CreateWriter
{
  my $self = shift;
  my( $edata, $ndata, $sdata, $chd, $date ) = @_;

  $self->{xmltvid} = $chd->{xmltvid};
  $self->{epgservername} = $edata->{name};
  $self->{date} = $date;
  $self->{writer_entries} = 0;

  # Make sure that writer_entries is always true if we don't require data
  # for this date.
  $self->{writer_entries} = "0 but true" 
    if( ($date gt $self->{LastRequiredDate}) or $chd->{empty_ok} );

  my $odoc = XML::LibXML::Document->new( "1.0", $ndata->{charset} );
  $self->{networkcharset} = $ndata->{charset};

  my $c1 = $odoc->createComment( " Created by Gonix (www.gonix.net) for " . $edata->{name} . "/" . $ndata->{name} . " at " . DateTime->now . " " );
  $odoc->appendChild( $c1 );

  my $c2 = $odoc->createComment( " Schedule for '" . $sdata->{servicename} . "' service at EPG server '" . $edata->{name}. "' "
 );
  $odoc->appendChild( $c2 );

  my $dtd  = $odoc->createInternalSubset( "event-information", undef, "event-information.dtd" );

  return($odoc);
}

sub CloseWriter
{
  my $self = shift;
  my( $w, $frag ) = @_;

  my $epgservername = $self->{epgservername};

  my $path = $self->{Root} . "/" . $self->{epgservername};
  my $filename =  $self->{xmltvid} . "_" . $self->{date} . ".xml";

  my $networkcharset = $self->{networkcharset};

  my $docstring = $w->toString( 1 );
  my $fragstring = $frag->toString( 1 );

  open( my $fh, '>', $path . "/" . $filename . ".new" );
  binmode $fh;
  print $fh $docstring;
  print $fh $fragstring;
  close( $fh );

  #progress("Dreampark: Service schedule exported to $filename");

  if( -f "$path/$filename" )
  {
    system("diff $path/$filename.new $path/$filename > /dev/null");
    if( $? )
    {
      move( "$path/$filename.new", "$path/$filename" );
      progress( "Dreampark: Exported $filename" );
      if( not $self->{writer_entries} )
      {
        error( "Dreampark: $filename is empty" );
      }
      elsif( $self->{writer_entries} > 0 )
      {
#        my @errors = ValidateFile( "$path/$filename" );
#        if( scalar( @errors ) > 0 )
#        {
#          error( "Dreampark: $filename contains errors: " . 
#                 join( ", ", @errors ) );
#        }
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
    progress( "Dreampark: Exported $filename" );
    if( not $self->{writer_entries} )
    {
      error( "Dreampark: $filename is empty" );
    }
    elsif( $self->{writer_entries} > 0 )
    {
#      my @errors = ValidateFile( "$path/$filename" );
#      if( scalar( @errors ) > 0 )
#      {
#        error( "Dreampark: $filename contains errors: " . 
#               join( ", ", @errors ) );
#      }
    }
  }

  if( $self->{exportedlist} ){
    $self->ExportFileNameToList( "$path/$filename" );
  }
}

sub WriteEntry
{
  my $self = shift;
  my( $odoc, $node, $data, $chd, $evno ) = @_;

  $self->{writer_entries}++;

  my $networkcharset = $self->{networkcharset};

  my $start_time = create_dt( $data->{start_time}, "UTC" );
  $start_time->set_time_zone( "Europe/Zagreb" );
  
  my $end_time = create_dt( $data->{end_time}, "UTC" );
  $end_time->set_time_zone( "Europe/Zagreb" );
  
  my $starttime = EventStartTime( $data->{start_time} );
  my $duration = EventDuration( $data->{start_time}, $data->{end_time} );

  my $pc1 = $odoc->createComment( " " . $data->{title} . " " );
  $node->appendChild( $pc1 );

  #
  # program details
  #
  my $event = $odoc->createElement( 'program' );
  $event->setAttribute( 'id' => $evno );
  $event->setAttribute( 'channel' => $chd->{id} );
  $event->setAttribute( 'originalTitle' => "" );
  $event->setAttribute( 'startTime' => $starttime );
  $event->setAttribute( 'duration' => $duration );
  $event->setAttribute( 'rating' => "" );
  $event->setAttribute( 'surround' => "" );
  $event->setAttribute( 'stereo' => "" );
  $event->setAttribute( 'ratio' => "" );
  $event->setAttribute( 'productionYear' => "" );
  $event->setAttribute( 'productionCountry' => "" );
  $event->setAttribute( 'image' => "" );
  $node->appendChild( $event );

  #
  # genre reference
  #
  my $genrerefs = $odoc->createElement( 'genreRefs' );
  $event->appendChild( $genrerefs );

  my $genre = $self->FindGenre( $data->{category} );
  my $genreref = $odoc->createElement( 'genreRef' );
  if( not $genre ){
    $genreref->setAttribute( 'id' => "" );
  } else {
    $genreref->setAttribute( 'id' => $genre->{genreid} );
  }
  $genrerefs->appendChild( $genreref );

  #
  # credits
  #
  my $credits = $odoc->createElement( 'credits' );
  $event->appendChild( $credits );

  # directors
  if( $data->{directors} ){
    my @directors = split( /\s*,\s*/ , $data->{directors} );
    foreach my $d (@directors) {
      my $director = $odoc->createElement( 'director' );
      $director->appendText( $d );
      $credits->appendChild( $director );
    }
  } else {
    my $director = $odoc->createElement( 'director' );
    $director->appendText( "" );
    $credits->appendChild( $director );
  }

  # actors
  if( $data->{actors} ){
    my @actors = split( /\s*,\s*/ , $data->{actors} );
    foreach my $a (@actors) {
      my $actor = $odoc->createElement( 'actor' );
      $actor->appendText( $a );
      $credits->appendChild( $actor );
    }
  } else {
    my $actor = $odoc->createElement( 'actor' );
    $actor->appendText( "" );
    $credits->appendChild( $actor );
  }

  #
  # descriptions
  #
  my $descriptions = $odoc->createElement( 'descriptions' );
  $event->appendChild( $descriptions );

  my $description = $odoc->createElement( 'description' );
  $description->setAttribute( 'lang' => "HR" );
  $description->setAttribute( 'title' => $data->{title} );
  $description->setAttribute( 'rating' => "" );
  $descriptions->appendChild( $description );

  #
  # short synopsis
  #
  my $shdesc = $odoc->createElement( 'shortSynopsis' );
  if( $data->{description} ){

    # the maximum length of the short description is 251
    my $encshortdesc = myEncode( $networkcharset, $data->{description} );
    my $trencshortdesc = truncstr( $encshortdesc, 100 );
    $shdesc->appendText( $trencshortdesc );

  } else {

    $shdesc->appendText( "" );

  }
  $description->appendChild( $shdesc );

  #
  # synopsis
  #
  my $exdesc = $odoc->createElement( 'synopsis' );
  if( $data->{description} ){

    # the maximum length of the long description is 251
    my $enclongdesc = myEncode( $networkcharset, $data->{description} );
    my $trenclongdesc = truncstr( $enclongdesc, 100000 );
    $exdesc->appendText( $trenclongdesc );

  } else {

    $exdesc->appendText( "" );

  }
  $description->appendChild( $exdesc );
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
# Write metadata to meta.xml
#
sub ExportMetaDataFile
{
  my( $self ) = shift;
  my( $epgserver ) = @_;

  my $ds = $self->{datastore};

  my $now = my $keep_date = DateTime->now;

  my $equery = "SELECT * from epgservers WHERE `active`=1 AND `type`='Dreampark'";
  $equery .= " AND name='$epgserver'" if $epgserver;

  my( $eres, $esth ) = $ds->sa->Sql( $equery );
  while( my $edata = $esth->fetchrow_hashref() )
  {
    progress("Dreampark: Exporting metadata for epg server '$edata->{name}'");

    my $nquery = "SELECT * from networks WHERE epgserver=$edata->{id} AND active=1";
    my( $nres, $nsth ) = $ds->sa->Sql( $nquery );
    while( my $ndata = $nsth->fetchrow_hashref() )
    {
      progress("Dreampark: Found $ndata->{type} network '$ndata->{name}' on $edata->{name}");

      my $odoc = XML::LibXML::Document->new( "1.0", $self->{Encoding} );

      my $c1 = $odoc->createComment( " Created by Gonix (www.gonix.net) for " . $edata->{name} . "/" . $ndata->{name} . " at " . DateTime->now . " " );
      $odoc->appendChild( $c1 );

      my $dtd  = $odoc->createInternalSubset( "dreampark", undef, "dreampark.dtd" );

      my $root = $odoc->createDocumentFragment();

      $self->ExportMetaData( undef, $odoc, $root, $ndata );

      my $outfile = "$self->{Root}$edata->{name}/meta.xml";
      open( my $fh, '>:encoding(' . $self->{Encoding} . ')', $outfile )
        or die( "Dreampark: cannot write to $outfile" );

        my $docstring = $odoc->toString( 1 );
        my $fragstring = $root->toString( 1 );

        binmode $fh;
        print $fh $docstring;
        print $fh $fragstring;
        close( $fh );

      progress("Dreampark: Metadata information exported to $outfile");
    }
    $nsth->finish();
  }
  $esth->finish();
}

sub ExportMetaData {
  my $self = shift;
  my( $chd, $odoc, $frag, $ndata ) = @_;

  # document fragment with meta data
  my $meta = $odoc->createElement( 'meta' );
  $frag->appendChild( $meta );

  my $genres = $odoc->createElement( 'genres' );
  $meta->appendChild( $genres );

  my @gens = $self->LoadGenres();
  foreach my $gid (@gens) {

    my $genre = $odoc->createElement( 'genre' );
    $genre->setAttribute( 'id' => $gid->{genreid} );
    $genres->appendChild( $genre );

    my $genrename = $odoc->createElement( 'name' );
    $genrename->setAttribute( 'lang' => "hr" );
    $genrename->appendText( $gid->{genre} );
    $genre->appendChild( $genrename );

  }

  my $channels = $odoc->createElement( 'channels' );
  $meta->appendChild( $channels );

  if( $chd ){
    my $channel = $odoc->createElement( 'channel' );
    $channel->setAttribute( 'id' => $chd->{id} );
    $channel->setAttribute( 'name' => $chd->{display_name} );
    $channels->appendChild( $channel );
  } else {
    my @chans = $self->LoadServices( $ndata );
    foreach my $cid (@chans) {
      my $channel = $odoc->createElement( 'channel' );
      $channel->setAttribute( 'id' => $cid->{serviceid} );
      $channel->setAttribute( 'name' => $cid->{servicename} );
      $channels->appendChild( $channel );
    }
  }
}

sub LoadGenres
{
  my $self = shift;
  my( $res, $sth ) = $self->{datastore}->sa->Sql( "
        SELECT * from genres
        WHERE 1;"
  );

  my @g;
  my $id = 0;
  while (my $hash_ref = $sth->fetchrow_hashref) {
    $hash_ref->{id} = ++$id;
    push( @g, $hash_ref );
  }

  $sth->finish();

  return @g;
}

sub FindGenre
{
  my $self = shift;
  my( $category ) = @_;

  return undef if not $category;

  my( $res, $sth ) = $self->{datastore}->sa->Sql( "
        SELECT * from genres
        WHERE (original = ?)",
      [$category] );
  
  my $g = $sth->fetchrow_hashref();

  $sth->finish();

  return $g;
}

sub LoadServices
{
  my $self = shift;
  my( $ndata ) = @_;

  my( $res, $sth ) = $self->{datastore}->sa->Sql( "
        SELECT * from services
        WHERE (network = ?) 
          and (active = 1)
        ORDER BY serviceid",
      [$ndata->{id}] );

  my @g;
  my $id = 0;
  while (my $hash_ref = $sth->fetchrow_hashref) {
    $hash_ref->{id} = ++$id;
    push( @g, $hash_ref );
  }

  $sth->finish();

  return @g;
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
      progress( "Dreampark: Removing old files in directory $dir" );

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

  progress( "Dreampark: Removed $removed files" ) if( $removed > 0 );
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

