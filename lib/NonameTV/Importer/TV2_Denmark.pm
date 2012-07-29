package NonameTV::Importer::TV2_Denmark;

use strict;
use warnings;

=pod

Importer for data from TV2 Denmark,
(You should change the filestore at the bottom)
 
=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use Roman;
use Data::Dumper;

use NonameTV qw/MyGet norm ParseDescCatSwe AddCategory FixProgrammeData/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
    
    $self->{MinWeeks} = 0;
    $self->{MaxWeeks} = 3;

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    #$dsh->{DETECT_SEGMENTS} = 1;
    $self->{datastorehelper} = $dsh;

    # use augment
    $self->{datastore}->{augment} = 1;


    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ($objectname =~ /_(.*)/);
  
  my ( $year , $week ) = ( $date =~ /(\d+)-(\d+)$/ );
  my ($yearweek) = sprintf( "%04d-%02d", $year, $week );
  
  my $url = $self->{UrlRoot} . '?category=all&day=all&format=xml&how=xml&content=all&update=&updateswitch=0'
    . '&week=' . $yearweek
    . '&channel=' . $chd->{grabber_info};

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

  my( $date2 ) = ($batch_id =~ /_(.*)$/);
  my( $xmltvid ) = ($batch_id =~ /(.*)_/);
  my $currdate = "x";

  my $xml = XML::LibXML->new;
  my $doc;
  
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse: $@" );
    return 0;
  }
    # the grabber_data should point exactly to one worksheet
    my $rows = $doc->findnodes( ".//programs/program" );

    if( $rows->size() == 0 ) {
      error( "TV2 Denmark: $chd->{xmltvid}: No Rows found" ) ;
      return 0;
    }

	#$ds->StartBatch($batch_id);

  foreach my $pgm ($rows->get_nodelist)
  {
  	my $date  = $pgm->findvalue( 'date' );
  	
  	## Batch
  	
    my $time  = $pgm->findvalue( 'time' );
    my $title = $pgm->findvalue( 'title' );
    
    my $ce = {
      title       => norm($title),
      start_time 	=> $time,
      channel_id  => $chd->{id},
      batch_id		=> $batch_id,
    };
    
    progress( "TV2: $chd->{xmltvid}: $time - $title" );
    
    # Desc
    if(defined($pgm->findvalue( 'description' ))) {
    	$ce->{description} = norm($pgm->findvalue( 'description' ));
    }
    
    # Subtitle
    if(defined($pgm->findvalue( 'original_episode_title' ))) {
    	$ce->{subtitle} = norm($pgm->findvalue( 'original_episode_title' ));
    }
    
    $ds->AddProgrammeRaw( $ce );
  }
  
  #$ds->EndBatch( 1 );
  
  # Success
  return 1;
}

1;