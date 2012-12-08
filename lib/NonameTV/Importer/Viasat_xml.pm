package NonameTV::Importer::Viasat_xml;

use strict;
use warnings;

=pod

Importer for data from Viasat.
The data is a day-seperated feed of programmes.
<programtable>
	<day date="2012-09-10>
		<program>
		</program>
	</day>
</programtable>

Use this instead of Viasat.pm as the TAB-seperated is
a dumb idea. If an employee of MTG drops a tab in the desc
it think its a new field.
=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;
use Data::Dumper;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new( @_ );
    bless ($self, $class);


    $self->{MinWeeks} = 0 unless defined $self->{MinWeeks};
    $self->{MaxWeeks} = 4 unless defined $self->{MaxWeeks};
    
    $self->{datastore}->{augment} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );

  my $url = 'http://press.viasat.tv/press/cm/listings/'. $chd->{grabber_info} . $year . '-' . $week.'.xml';

  return( $url, undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  $$cref =~ s| xmlns="http://www.mtg.se/xml/weeklisting"||g;
  $$cref =~ s|\?>|\?>\n|g;

  my $doc = ParseXml( $cref );
 
  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  } 

  my $str = $doc->toString(1);

  return (\$str, undef);
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $xmltvid=$chd->{xmltvid};

  my $channel_id = $chd->{id};
  my $ds = $self->{datastore};

  my $doc = ParseXml( $cref );
  
  if( not defined( $doc ) ) {
    f "Failed to parse";
    return 0;
  }
  
  # Find all paragraphs.
  my $ns = $doc->find( "//day" );
  
  if( $ns->size() == 0 ) {
    f "No days found";
    return 0;
  }

  foreach my $sched_date ($ns->get_nodelist) {
  	# Date
    my( $date ) = norm( $sched_date->findvalue( '@date' ) );
    
    # Programmes
    my $ns2 = $sched_date->find('program');
    foreach my $emission ($ns2->get_nodelist) {
      # General stuff
      my $start_time = $emission->findvalue( 'startTime' );
      my $other_name = $emission->findvalue( 'name' );
      my $original_name = $emission->findvalue( 'orgName' );
      my $name = $original_name || $other_name;
      $name =~ s/#//g; # crashes the whole importer
      
      # Category and genre
      my $category = $emission->findvalue( 'category' ); # category_series, category_movie, category_news
      $category =~ s/category_//g; # remove category_
      my $genre = $emission->findvalue( 'genre' );
      
      # Description
      my $desc_episode = $emission->findvalue( 'synopsisThisEpisode' );
      my $desc_series = $emission->findvalue( 'synopsis' );
      my $desc_logline = $emission->findvalue( 'logline' );
      my $desc = $desc_episode || $desc_series || $desc_logline;
      
      # Season and episode
      my $episode = $emission->findvalue( 'episode' );
      my $season = $emission->findvalue( 'season' );
      my $eps = "";
      ( $episode, $eps ) = ($desc =~ /del\s+(\d+):(\d+)/ );
      ( $episode, $eps ) = ($desc =~ /Del\s+(\d+):(\d+)/ );
      $desc =~ s/Del (\d+):(\d+)//g;
      
      # Extra stuff
      my $prodyear = $emission->findvalue( 'productionYear' );
      
      # Actors and directors
      my @actors;
      my @directors;

      my $ns2 = $emission->find( './/castMember' );
      foreach my $act ($ns2->get_nodelist)
	  {
	  	push @actors, $act;
	  }
	  
	  
	  my $ce = {
	      title       => norm($name),
	      description => norm($desc),
	      start_time  => $date." ".$start_time,
      };
      
      
      if( scalar( @actors ) > 0 )
	  {
	      $ce->{actors} = join ", ", @actors;
	  }
	
		$ce->{directors} = norm($emission->findvalue( 'director' )) if $emission->findvalue( 'director' );
      
    }
  }

  return 1;
}
1;