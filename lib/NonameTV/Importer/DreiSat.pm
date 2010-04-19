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

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

#return( undef, undef ) if ( $objectname =~ /3sat\.tv\.gonix\.net_2009-14/ );

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );
 
  my $url = sprintf( "%s/3Sat_%04d%02d.XML", $self->{UrlRoot}, $year, $week );

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

    # the subtitle
    my $subtitle = $sc->findvalue( './programm//untertitel' );

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
      my $endtime = $self->create_dt( $biszeit );
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
        #aspect      => $sixteen_nine ? "16:9" : "4:3", 
      };

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
        $description .= "<br>" . $origin . "\n";
      }
      $ce->{description} = $description;

      # episode number
      if( $episodenr ){
        $ce->{episode} = ". " . ($episodenr-1) . " .";
      }

      my ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_genre", $genre );
      AddCategory( $ce, $program_type, $categ );

      ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_category", $category );
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
  my( $str ) = @_;

  my( $date, $time ) = split( 'T', $str );
  if( not defined $time )
  {
    return undef;
  }

  my( $year, $month, $day );

  if( $date =~ /(\d{4})\.(\d{2})\.(\d{2})/ ){
    ( $year, $month, $day ) = ( $date =~ /(\d{4})\.(\d{2})\.(\d{2})/ );
  } elsif( $date =~ /(\d{2})\.(\d{2})\.(\d{4})/ ){
    ( $day, $month, $year ) = ( $date =~ /(\d{2})\.(\d{2})\.(\d{4})/ );
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
                          time_zone => 'Europe/Zagreb',
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

1;
