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

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Copenhagen" );
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
	if($date ne $currdate ) {
		if( $currdate ne "x" ) {
			#$ds->EndBatch( 1 );
		}

		my $batchid = $chd->{xmltvid} . "_" . $date;
		#$dsh->StartBatch( $batchid );
		$dsh->StartDate( $date );
		$currdate = $date;

		progress("TV2: Date is: $date");
	}
  	
    my $start  = ParseDateTime($pgm->findvalue( 'time' ));
    my $title = $pgm->findvalue( 'title' );
    $title =~ s/\((\d+):(\d+)\)//g if $title;
    $title =~ s/\((\d+)\)//g if $title;
    my $genre = $pgm->findvalue( 'category' );
    my $cast  = $pgm->findvalue( 'cast' );
    my $year  = $pgm->findvalue( 'year' );
    
    if(defined($pgm->findvalue( 'original_title' ))){
  	  my ( $original_title , $year_series ) = ( $pgm->findvalue( 'original_title' ) =~ /^(.*)-(.*)$/ );
  	  
  	  if(norm($original_title) ne "") {
  	 	 $title = $original_title;
  	  } else {
  	  	
  	  }
  	}
    
    my $ce = {
      title       => norm($title),
      start_time 	=> $start->hms(":"),
      channel_id  => $chd->{id},
      batch_id		=> $batch_id,
    };
    
    progress( "TV2: $chd->{xmltvid}: $start - $title" );
    
    # Desc
    if(defined($pgm->findvalue( 'description' ))) {
    	$ce->{description} = norm($pgm->findvalue( 'description' ));
    }
    
    # Subtitle
    if(defined($pgm->findvalue( 'original_episode_title' ))) {
    	if(norm($pgm->findvalue( 'original_episode_title' )) ne "") {
    		$ce->{subtitle} = norm($pgm->findvalue( 'original_episode_title' ));
    		$ce->{subtitle} =~ s/ - part/: Part/g if $title;
    	}
    }
    
    if( $genre ){
			my($program_type, $category ) = $ds->LookupCat( 'TV2Denmark', $genre );
			AddCategory( $ce, $program_type, $category );
	}
	
	if( defined( $year ) and ($year =~ /(\d\d\d\d)/) ) {
		$ce->{production_date} = "$1-01-01";
	}
	
	my( $dumpy, $directors ) = ($cast =~ /(\s)nstruktion:\s*(.*).$/ );
	if( $directors ) {
		$ce->{directors} = norm(parse_person_list( $directors ));
	}
    
    $dsh->AddProgramme( $ce );
  }
  
  #$ds->EndBatch( 1 );
  
  # Success
  return 1;
}


sub parse_person_list
{
  my( $str ) = @_;

  $str =~ s/\bog\b/,/;
  $str =~ s/\bsamt\b/,/;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    # The Cast-entry is sometimes cutoff, which means that the
    # character name might be missing a trailing ).
    #s/\s*\(.*$//;
    #s/.*\s+-\s+//;
  }
  
  Dumper(@persons);

  return join( ", ", grep( /\S/, @persons ) );
}

# The start and end-times are in the format 2007-12-31T01:00:00
# and are expressed in the local timezone.
sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) = 
      ($str =~ /^(\d+)-(\d+)-(\d+) (\d+):(\d+):(\d+)/ );

  my $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
    second => $second,
#    time_zone => "Europe/Copenhagen"
      );

#  $dt->set_time_zone( "UTC" );

  return $dt;
}

1;