package NonameTV::Importer::Kanal23;

use strict;
use warnings;

=pod

Importer for data from Kanal23 (Kanal Hovedstaden).
One file per channel and 45-day period downloaded from their site.
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
    # title
    #
    my $title = $sc->getElementsByTagName('title');
    my $subtitle = $sc->getElementsByTagName('subtitle');
    $subtitle =~ s/^-//;

    if( ($title eq "Ingen programinformation") )
    {
        # break
      	next;
    }

    #
    # description
    #
    my $desc  = $sc->getElementsByTagName('desc');

    #
    # genre
    #
    my $genre = $sc->find( './/category' );

    #
    # production year
    #
    my $production_year = $sc->getElementsByTagName( 'date' );

    #
    # credits
    #
    my( $directors, $actors, $writers, $adapters, $producers, $presenters, $commentators, $guests );
    my $credits = $sc->findnodes( './/credits' );
    if( $credits->size() > 0 ){

      foreach my $credit ($credits->get_nodelist)
      {

        # actors
        my $actornodes = $credit->findnodes( './/actor' );
        if( $actornodes->size() > 0 ){
          foreach my $actor ($actornodes->get_nodelist)
          {
            $actors .= $actor->textContent . ";";
          }
          $actors =~ s/;$//;
        }

        # producers
        my $producernodes = $credit->findnodes( './/producer' );
        if( $producernodes->size() > 0 ){
          foreach my $producer ($producernodes->get_nodelist)
          {
            $producers .= $producer->textContent . ";";
          }
          $producers =~ s/;$//;
        }

      }

    }

    my $ce = {
      channel_id   => $chd->{id},
      title        => norm($title),
      subtitle     => ucfirst(norm($subtitle)),
      description  => norm($desc),
      start_time   => $start->ymd("-") . " " . $start->hms(":"),
      end_time     => $end->ymd("-") . " " . $end->hms(":"),
    };

	if(defined($genre)) {
	    foreach my $g ($genre->get_nodelist)
        {
		    my ($program_type, $category ) = $ds->LookupCat( "Kanal23", $g->to_literal );
		    AddCategory( $ce, $program_type, $category );
		}
	}

    if( defined( $production_year ) and ($production_year =~ /(\d\d\d\d)/) )
    {
      $ce->{production_date} = "$1-01-01";
    }

    my( $t, $dummy, $st ) = ($ce->{title} =~ /(.*)(\:| \-) (.*)/);
    if( defined( $st ) )
    {
      # This program is part of a series and it has a colon in the title.
      # Assume that the colon separates the title from the subtitle.
      $ce->{title} = norm($t);
      $ce->{subtitle} = norm($st);
    }

    my ( $episode ) = ($ce->{title} =~ /\((\d+)\)$/i );
    if(defined($episode) and $episode) {
        $ce->{episode} = ". " . ($episode-1) . " .";
    }

    $ce->{title} =~ s/\((\d+)\)$//i;
    $ce->{title} = norm($ce->{title});

    # Subtitle
    if($ce->{subtitle} eq "ingen programinformation") {
        $ce->{subtitle} = undef;
    }

    # Special case
    if(($ce->{title} eq "Vesterbro Lokaltv" or $ce->{title} eq "Vesterbro Lokal TV") and $ce->{subtitle} ne "") {
        $ce->{title} = $ce->{title}. " - ".$ce->{subtitle};
        $ce->{subtitle} = undef;
    }

    $ce->{actors} = norm($actors) if defined($actors);
    $ce->{producers} = norm($producers) if defined($producers);

    progress("$batch_id: $chd->{xmltvid}: $start - $ce->{title}");

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

  if( not defined $year )
  {
    return undef;
  }

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          );

  $dt->set_time_zone( "UTC" );

  return $dt;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my $url = sprintf( "http://www.kanal23.dk/xmltv/kanalhovedstaden-45dage.xml");

  return( $url, undef );
}

1;