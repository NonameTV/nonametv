package NonameTV::Importer::DreiSat;

use strict;
use warnings;

=pod

Importer for data from DreiSat. 
One file per channel and week downloaded from their site.
The downloaded file is in xml-format.

=cut

use DateTime;
use XML::LibXML;
use Switch;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/progress w error/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    # url is linked from public web site so make it the default
    defined( $self->{UrlRoot} ) or $self->{UrlRoot} = "http://programmdienst.3sat.de/wspressefahne/Dateien";
    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );
 
  my $url = sprintf( "%s/3sat_Woche%02d%02d.xml", $self->{UrlRoot}, $week, $year%100 );

  progress("DreiSat: fetching data from $url");

  return( $url, undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my $doc = ParseXml( $cref );

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  } 

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//programmdaten" );

  if( $ns->size() == 0 ) {
    return (undef, "No channels found" );
  }
  
  my $str = $doc->toString( 1 );

  return( \$str, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;
 
  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse $@" );
    return 0;
  }
  
  # Find all "sendung"-entries.
  my $ns = $doc->find( '//sendung' );
  if( $ns->size() == 0 ){
    error( "$batch_id: No 'sendung' blocks found" );
    return 0;
  }
  progress("DreiSat: Found " . $ns->size() . " shows");
  
  foreach my $sc ($ns->get_nodelist)
  {
    # the id of the program
    my $id  = $sc->findvalue( './id ' );

    # the title
    my $title = $sc->findvalue( './programm//sendetitel' );
    $title = $self->clean_sendetitel ($title);

    # the subtitle
    my $subtitle = $sc->findvalue( './programm//untertitel' );
    # strip "repeat"
    $subtitle =~ s|\(Wh\.\)||;

    # additional info to the title
    my @addinfo;
    my $zusatz = $sc->findnodes( './programm//zusatz' );
    foreach my $zs ($zusatz->get_nodelist) {
      push( @addinfo, $zs->string_value() );
    }

    # episode title
    my $episodetitle = $sc->findvalue( './programm//folgentitel' );

    # episode number
    my $episodenr = $sc->findvalue( './programm//folgenr' );

    # genre
    my $genre = $sc->findvalue( './programm//progart' );

    # category
    my $category = $sc->findvalue( './programm//kategorie' );

    # thember (similar to genre?? example - 'Reisen/Urlaub/Touristik')
    my $thember = $sc->findvalue( './programm//thember' );

    # info about the origin
    my $origin = $sc->findvalue( './programm//herkunftsender' );

    # short description
    my $shortdesc = $sc->findvalue( './programm//pressetext//kurz' );

    # long description
    my $longdesc = $sc->findvalue( './programm//pressetext//lang' );

    # moderation
    my $moderation = $sc->findvalue( './programm//moderation' );

    # there can be more than one broadcast times
    # so we have to find each 'ausstrahlung'
    # and insert the program for each of them
    my $ausstrahlung = $sc->find( './ausstrahlung' );

    foreach my $as ($ausstrahlung->get_nodelist)
    {
      # start time
      my $startzeit = $as->getElementsByTagName( 'startzeit' );
      my $starttime = $self->create_dt( $startzeit );
      if( not defined $starttime ){
        error( "$batch_id: Invalid starttime for programme id $id - Skipping." );
        next;
      }

      # end time
      my $biszeit = $as->getElementsByTagName( 'biszeit' );
      my $endtime = $self->create_dt_incomplete( $biszeit, $starttime );
      if( not defined $endtime ){
        error( "$batch_id: Invalid endtime for programme id $id - Skipping." );
        next;
      }

      # duration
      my $dauermin = $as->getElementsByTagName( 'dauermin' );

      # attributes
      my $attribute = $as->getElementsByTagName( 'attribute' );

      progress("DreiSat: $chd->{xmltvid}: $starttime - $title");

      my $ce = {
        channel_id  => $chd->{id},
        start_time  => $starttime->ymd("-") . " " . $starttime->hms(":"),
        end_time    => $endtime->ymd("-") . " " . $endtime->hms(":"),
        title       => norm($title),
      };

      foreach my $attribut (split (" ", $attribute)) {
        switch ($attribut) {
          # DreiSat
          case /auddes/ {} # stereo = audio description
          case /dolby/  {$ce->{stereo} = "dolby"}
          case /dolbyd/ {$ce->{stereo} = "dolby digital"}
          case /f16zu9/ {$ce->{aspect} = "16:9"}
          case /gbsp/   {} # sign language
          case /stereo/ {$ce->{stereo} = "stereo"}
          case /sw/     {} # colour=no
          case /videot/ {} # subtitles=teletext
          case /zweika/ {$ce->{stereo} = "bilingual"}
          # ZDF
          case /&ad;/   {} # audio description
          case /&dd;/   {$ce->{stereo} = "dolby digital"}
          case /&ds;/   {$ce->{stereo} = "dolby"}
          case /&f16;/  {$ce->{aspect} = "16:9"}
          case /&hd;/   {} # high definition
          case /&st;/   {$ce->{stereo} = "stereo"}
          case /&vo;/   {} # video text
          # ZDFneo
          case /&zw;/   {$ce->{stereo} = "bilingual"} 
          else          { w ($self->{Type} . ": unhandled attribute:" . $attribut) }
        }
      }

      # form the subtitle out of 'episodetitle' and 'subtitle'
      my $st;
      if( $episodetitle ){
        $st = $episodetitle;
        if( $subtitle ){
          $st .= " : " . $subtitle;
        }
      } elsif( $subtitle ){
        $st = $subtitle;
      }
      $ce->{subtitle} = norm($st);

      # form the description out of 'zusatz', 'shortdesc', 'longdesc'
      # 'origin'
      my $description;
      if( @addinfo ){
        foreach my $z ( @addinfo ){
          $description .= $z . "\n";
        }
      }
      $description .= norm($longdesc) || norm($shortdesc);
      if( $origin ){
        $description .= "<br/>" . $origin . "\n";
      }
      $ce->{description} = $description;

      # episode number
      if( $episodenr ){
        $ce->{episode} = ". " . ($episodenr-1) . " .";
      }

      my $lookup_genre = $self->{Type}. "_genre";
      my ( $program_type, $categ ) = $ds->LookupCat( $lookup_genre, $genre );
      AddCategory( $ce, $program_type, $categ );

      my $lookup_categ = $self->{Type}. "_category";
      ( $program_type, $categ ) = $ds->LookupCat( $lookup_categ, $category );
      AddCategory( $ce, $program_type, $categ );

      $ds->AddProgramme( $ce );
    }

  }
  
  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my $str = shift;

  my( $date, $time ) = split( 'T', $str );
  if( not defined $time )
  {
    return undef;
  }

  my( $year, $month, $day );

  if( $date =~ /(\d{4})\.(\d+)\.(\d+)/ ){
    ( $year, $month, $day ) = ( $date =~ /(\d{4})\.(\d+)\.(\d+)/ );
  } elsif( $date =~ /(\d+)\.(\d+)\.(\d{4})/ ){
    ( $day, $month, $year ) = ( $date =~ /(\d+)\.(\d+)\.(\d{4})/ );
  }

  my( $hour, $minute, $second ) = ( $time =~ /(\d{2}):(\d{2}):(\d{2})/ );
  
  if( $second > 59 ) {
    return undef;
  }

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => 'Europe/Berlin',
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

sub create_dt_incomplete
{
  my $self = shift;
  my $str = shift;
  my $start = shift;

  my $dt;

  if ($str =~ /\d{6}/) {
    my ($hour, $minute, $second) = ($str =~ /(\d{2})(\d{2})(\d{2})/ );
    $dt = $start->clone();
    $dt->set_hour ($hour);
    $dt->set_minute ($minute);
    $dt->set_second ($second);
  } else {
    $dt = $self->create_dt ($str)
  }

  return $dt;
}

sub clean_sendetitel
{
  my $self = shift;
  my $title = shift;

  # remove episode numbers from title
  $title =~ s| \(\d+/\d+\)$||;

  return $title;
}

1;
