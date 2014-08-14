package NonameTV::Importer::TV7;

=pod

This importer imports data for TV7 Heaven TV.
Including the Finnish, Estland, Swedish channels.

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use Roman;
use Data::Dumper;

use NonameTV qw/norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $id, $lang ) = split( /:/, $chd->{grabber_info} );

  my $url = 'http://amos.tv7.fi/exodus/public/programs.jsp?cid=' . $id . '&lang=' . $lang;

  return( $url, undef );
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
  my $dsh = $self->{datastorehelper};

  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse: $@" );
    return 0;
  }

  # Find all "program"-entries.
  my $ns = $doc->find( "//day" );
  if( $ns->size() == 0 )
  {
    error( "$batch_id: No days found" );
    return 0;
  }

  foreach my $day ($ns->get_nodelist) {
    my $str = $day->findvalue( './@date' );
    $str =~ s/(.*)\s+//;

    my( $dag, $month, $year ) = ( $str =~ /(\d+).(\d+).(\d+)/ );
    my $date = $year."-".$month."-".$dag;

    $dsh->StartDate( $date );

    progress("$batch_id: Date is ".$date);

    my $ns2  = $day->findnodes( ".//program" );

    if( $ns2->size() == 0 )
    {
        error( "$batch_id: No programs found" );
        return 0;
    }

    foreach my $pgm ($ns2->get_nodelist)
    {
        my $starttime = $pgm->findvalue( 'time' );
        my $title     = $pgm->findvalue( 'programName' );
        my $subtitle  = $pgm->findvalue( 'episodeName' );
        my $shortdesc = $pgm->findvalue( 'shortdesc' );
        my $epdesc    = $pgm->findvalue( 'episodeShortdesc' );
        my $desc      = $epdesc || $shortdesc;

        my $ce = {
              title       	 => norm($title),
              start_time  	 => $starttime,
              description    => norm($desc),
            };

        $ce->{subtitle} = norm($subtitle) if defined($subtitle) and $subtitle ne "";

        # Episode
        if(defined $ce->{subtitle} and $ce->{subtitle} =~ /, del (\d+)$/i) {
            my $episode = ($ce->{subtitle} =~ /, del (\d+)$/i);
            $ce->{subtitle} =~ s/, del (\d+)$//i;
            $ce->{episode} = sprintf( ". %d .", $episode-1 );
        }

        progress($date." ".$starttime." - ".$ce->{title});
        $dsh->AddProgramme( $ce );
    }
  }



  # Success
  return 1;
}


1;
