package NonameTV::Importer::HRT;

use strict;
use warnings;

=pod

Importer for data from HRT. 
One file per channel and 4-day period downloaded from their site.
The downloaded file is in xml-format.

Features:

=cut

use DateTime;
use XML::LibXML;
use Encode qw/encode decode/;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
    
    # use augment
    $self->{datastore}->{augment} = 1;

    return $self;
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse $@" );
    return 0;
  }
  
  # Find all "programme"-entries.
  my $ns = $doc->find( "//programme" );
  
  foreach my $sc ($ns->get_nodelist)
  {
    
    #
    # start time
    #
    my $start = $self->create_dt( $sc->findvalue( './@start' ) );
    if( not defined $start )
    {
      error( "$batch_id: Invalid starttime '" . $sc->findvalue( './@start' ) . "'. Skipping." );
      next;
    }

    #
    # end time
    #
    my $end = $self->create_dt( $sc->findvalue( './@stop' ) );
    if( not defined $end )
    {
      error( "$batch_id: Invalid endtime '" . $sc->findvalue( './@stop' ) . "'. Skipping." );
      next;
    }
    
    #
    # title, subtitle
    #
    my $title;
#    eval{ $title = decode( "utf-8", $sc->getElementsByTagName('title') ); };
#    if( $@ ne "" ){
#      error( "Failed to decode title $@" );
#    }
    $title = $sc->getElementsByTagName('title');
    my $org_title = $sc->getElementsByTagName('sub-title');
    my $subtitle = $sc->getElementsByTagName('sub-title');
    
    $title =~ s/\(R\)//g if $title;
    $title =~ s/^Filmski maraton://;
    my ($newtitle, $cat) = ($title =~ /(.*),(.*)/);
    if(defined $cat) {
        $title = norm($newtitle);
    }

    $title =~ s/\((\d+)\)//;
    $title =~ s/\((\d+)\/(\d+)\)//;
    $title =~ s/\.$//;
    
    
    #
    # description
    #
    my $desc  = $sc->getElementsByTagName('desc');
    
    #
    # genre
    #
    my $genre = $sc->find( './/category' );

    #
    # url
    #
    my $url = $sc->getElementsByTagName( 'url' );

    #
    # production year
    #
    my $production_year = $sc->getElementsByTagName( 'date' );

    #
    # episode number
    #
    my $episode = undef;
    if( $sc->getElementsByTagName( 'episode-num' ) ){
      my $ep_nr = int( $sc->getElementsByTagName( 'episode-num' ) );
      my $ep_se = 0;
      if( ($ep_nr > 0) and ($ep_se > 0) )
      {
        $episode = sprintf( "%d . %d .", $ep_se-1, $ep_nr-1 );
      }
      elsif( $ep_nr > 0 )
      {
        $episode = sprintf( ". %d .", $ep_nr-1 );
      }
    }

    # The director and actor info are children of 'credits'
    my $directors = $sc->getElementsByTagName( 'director' );
    my $actors = $sc->getElementsByTagName( 'actor' );
    my $writers = $sc->getElementsByTagName( 'writer' );
    my $adapters = $sc->getElementsByTagName( 'adapter' );
    my $producers = $sc->getElementsByTagName( 'producer' );
    my $presenters = $sc->getElementsByTagName( 'presenter' );
    my $commentators = $sc->getElementsByTagName( 'commentator' );
    my $guests = $sc->getElementsByTagName( 'guest' );

    my $ce = {
      channel_id   => $chd->{id},
      title        => norm($title) || norm($org_title),
      subtitle     => norm($subtitle),
      description  => norm($desc),
      start_time   => $start->ymd("-") . " " . $start->hms(":"),
      end_time     => $end->ymd("-") . " " . $end->hms(":"),
      #aspect       => $sixteen_nine ? "16:9" : "4:3",
      directors    => norm($directors),
      actors       => norm($actors),
      writers      => norm($writers),
      adapters     => norm($adapters),
      producers    => norm($producers),
      presenters   => norm($presenters),
      commentators => norm($commentators),
      guests       => norm($guests),
      url          => norm($url),
    };

    if( defined( $episode ) and ($episode =~ /\S/) )
    {
      $ce->{episode} = norm($episode);
      $ce->{program_type} = 'series';
    }
    
    # (episodenum/of_episods)
  	my ( $ep2, $eps2 ) = ($ce->{title} =~ /\((\d+)\/(\d+)\)/ );
  	$ce->{episode} = sprintf( " . %d/%d . ", $ep2-1, $eps2 ) if defined $eps2;
  	$ce->{title} =~ s/\(.*\)//g;
    $ce->{title} = norm($ce->{title});
    
	my( $title_split, $genre_split ) = split( ',', norm($ce->{title}) );
    $ce->{title} = norm($title_split);

	my($program_type, $category ) = undef;

	if(defined($genre)) {
	    foreach my $g ($genre->get_nodelist)
        {
		    ($program_type, $category ) = $ds->LookupCat( "HRT", $g->to_literal );
		    AddCategory( $ce, $program_type, $category );
		}
	}
	
	if(defined($org_title) and defined($program_type)) {
		my ( $season ) = ($org_title =~ /(\d+)$/ );
			
		# Season
		if(defined($season) and defined($program_type) and $program_type eq "series") {
			$ce->{episode} = $season-1 . $ce->{episode};
			
			if("$org_title" ne "") {
				$org_title =~ s/\d+$//g;
				$org_title = ucfirst(lc($org_title));
				$org_title = norm($org_title);
				$org_title =~ s/,$//g;
				
				$ce->{subtitle} = undef;
				$ce->{original_title} = norm($ce->{title});
				$ce->{title} = norm($org_title);
			}
		} elsif(defined($program_type) and $program_type eq "movie" and $org_title ne "") {
			$org_title = ucfirst(lc($org_title));
			$ce->{original_title} = norm($ce->{title});
			$ce->{title} = norm($org_title);
			$ce->{subtitle} = undef;
		}
	}
	
    if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
    {
      $ce->{production_date} = "$1-01-01";
    }
    $ce->{subtitle} = undef;
    progress("HRT: $chd->{xmltvid}: $start - $ce->{title}");

    $ds->AddProgramme( $ce );
  }
  
  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  
  my $year = substr( $str , 0 , 4 );
  my $month = substr( $str , 4 , 2 );
  my $day = substr( $str , 6 , 2 );
  my $hour = substr( $str , 8 , 2 );
  my $minute = substr( $str , 10 , 2 );
  my $second = substr( $str , 12 , 2 );
  my $offset = substr( $str , 15 , 5 );

  if( not defined $year )
  {
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

sub Object2Url {
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my $url = $self->{UrlRoot} . "\?$data->{grabber_info}";

  return( $url, undef );
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

1;
