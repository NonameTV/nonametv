package NonameTV::Importer::ORF_xml;

use strict;
use warnings;

=pod

Importer for data from ORF.
The data is downloaded from ORF's presservice at http://presse.orf.at/
Every day is handled as a separate batch.

Channels: ORF1, ORF2, DreiSat, (a lot of radio stations)

=cut

use DateTime;
use HTTP::Date;
use XML::LibXML;
use utf8;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w progress error f d/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{MinDays} = 0 unless defined $self->{MinDays};
    $self->{MaxDays} = 15 unless defined $self->{MaxDays};

    if( defined(  $self->{UrlRoot} ) ) {
      w( "UrlRoot is deprecated. No point in keeping it secret as it\'s login protected now. Set Username and Password instead." );
    } else {
      $self->{UrlRoot} = 'http://presse.orf.at/download.php?sender=';
    }

    defined( $self->{Username} ) or die "You must specify Username";
    defined( $self->{Password} ) or die "You must specify Password";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Vienna" );
    $self->{datastorehelper} = $dsh;
    
    $self->{datastore}->{augment} = 1;

    $self->{datastore}->{augment} = 1;

    return $self;
}

sub InitiateDownload {
  my $self = shift;

  my $mech = $self->{cc}->UserAgent();

  my $response = $mech->get('http://presse.orf.at/?login[action]=login&login[redirect]=&login[username]=' . $self->{Username} . '&login[password]=' . $self->{Password});

  if ($response->is_success) {
    return undef;
  } else {
    return $response->status_line;
  }
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $month, $day ) = ( $objectname =~ /(\d+)-(\d+)-(\d+)$/ );
 
  my $url = $self->{UrlRoot} .
    $chd->{grabber_info} . '&date=' . $year . $month . $day;

  return( $url, undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my( $chid ) = ($chd->{grabber_info} =~ /^(\d+)/);

  my $doc;
  $$cref =~ s|encoding="LATIN1"|encoding="windows-1252"|;
  $$cref =~ s|<programmablauf>\n</programmtag>|<programmablauf>\n<programmtag />|s;
  $doc = ParseXml( $cref );

  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  }

  # Find all "Schedule"-entries.
  my $ns = $doc->find( "//programmablauf" );

  if( $ns->size() == 0 ) {
    # TODO sometimes there seem to be no programs on sportplus
    return (undef, "No data found" );
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

my %genrewords = (
	'Abenteuerserie' => 1,
	'Actionserie' => 1,
	'Animation' => 1,
	'Anwaltsserie' => 1,
	'Familienserie' => 1,
	'Jugendserie' => 1,
	'Kriminalserie' => 1,
	'Krimiserie' => 1,
	'Medical Daily' => 1,
	'Mysteryserie' => 1,
	'Serie' => 1,
	'Sitcom' => 1,
	'Stop Motion Trick' => 1,
	'Telenovela' => 1,
	'Unterhaltungsserie' => 1,
	'Zeichentrickserie' => 1,
);


sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};
  
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;
 
  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    f "Failed to parse $@";
    return 0;
  }
  	my( $date ) = ($batch_id =~ /_(.*)$/);
	
	$dsh->StartDate( $date , "00:00" );
 
 	 # Find all "z:row"-entries.
 	 my $ns = $doc->find( "//sendung" );

 	 if( $ns->size() == 0 )
 	 {
 	   f "No data found";
 	   return 0;
 	 }
  
  	 
 	 foreach my $sc ($ns->get_nodelist)
  	{

	
	my $title = $sc->findvalue( './titel' );
	

   	 my $time = ParseTime( $sc->findvalue( './zeit' ) );


		d( "ORF_xml: $chd->{xmltvid}: $time - $title" );

  		my $ce = {
  	      title 	  => norm($title),
 	      start_time  => $time,
   		};
   	 
  	  	my $desc = $sc->findvalue( './info' );
		# strip repeat
		$desc =~ s|\(Wh\..+?\)||;
		my( $genre, $countries, $year )=( $desc =~ m|\((.+?), (.+?) (\d{4})\)| );
		if( $year ){
			$desc =~ s|\(.+?, .+? \d{4}\)||;
			$ce->{production_date} = $year . '-01-01';

			# split optional "original title - genre"
			$genre =~ s|^.+ - (.+?)$|$1|;
			my ( $program_type, $categ ) = $self->{datastore}->LookupCat( "ORF", $genre );
			# set category, unless category is already set!
			AddCategory( $ce, $program_type, $categ );
		}else{
			my( $genreword )=( $desc =~ m/^(.*?)(?:\n|$)/s );
			if( $genreword ){
				if( $genrewords{$genreword} ) {
					$desc =~ s/^.*?(?:\n|$)//s;
					my ( $program_type, $categ ) = $self->{datastore}->LookupCat( "ORF", $genreword );
					AddCategory( $ce, $program_type, $categ );
				}
			}
		}

		# TODO handle more jobs
		# Analytiker: Günther Neukirchner
		# Buch: Verena Kurth
		# Co-Kommentator: Alexander Wurz
		# Kommentator: Ernst Hausleitner
		# Moderation: Markus Mooslechner
		# Präsentator: Boris Kastner-Jirka
		# Ratespiel mit Elton Co-Produktion ZDF/ORF
		# 

		# not actors: Mit welchen Psychotricks werden wir beeinflusst, ohne es zu merken?
		my( $actors )=( $desc =~ m|^M[Ii]t ([A-Z].+?)$|m );
		if( $actors ){
			$desc =~ s|^M[Ii]t .+?$||m;
			$actors =~ s| u\.a\.$||;
			# TODO clean up the list of actors
			$ce->{actors} = norm($actors);
		}
		my( $directors )=( $desc =~ m|^Regie:\s+(.+?)$|m );
		if( $directors ){
			$desc =~ s|^Regie:\s+.+?$||m;
			# TODO clean up the list of directors
			$ce->{directors} = norm($directors);
		}
		my( $running_time )=( $desc =~ m|^(\d+\.\d+)$|m );
		if( $running_time ){
			$desc =~ s|^\d+\.\d+$||m;
			# TODO do we want to add running time?
		}
		( $running_time )=( $desc =~ m|^ca. (\d+)\'$|m );
		if( $running_time ){
			$desc =~ s|^ca. \d+\'$||m;
			# TODO do we want to add running time?
		}
	      #$ce->{description} = norm($desc) if $desc;

		my $subtitle =  $sc->findvalue( './subtitel' );
		if( $subtitle =~ m/^(?:Folge|Kapitel|Teil)\s+\d+\s+-\s+.+$/ ){
			my( $episodenum, $episodetitle )=( $subtitle =~ m/^(?:Folge|Kapitel|Teil)\s+(\d+)\s+-\s+(.+)$/ );
			$ce->{episode} = '. ' . ($episodenum - 1) . ' .';
	   	 	$ce->{subtitle} = norm( $episodetitle );
		}elsif( $subtitle =~ m/^(?:Folge|Kapitel|Teil)\s+\d+$/ ){
			my( $episodenum )=( $subtitle =~ m/^(?:Folge|Kapitel|Teil)\s+(\d+)$/ );
			$ce->{episode} = '. ' . ($episodenum - 1) . ' .';
		}elsif( $subtitle ){
	   	 	$ce->{subtitle} = norm( $subtitle );
		}
	
		my $stereo =  $sc->findvalue( './m' );
		if( $stereo eq 'True' ){
   	 		$ce->{stereo} = 'mono';
		}

		$stereo =  $sc->findvalue( './s' );
		if( $stereo eq 'True' ){
   	 		$ce->{stereo} = 'stereo';
		}

		# dolby surround sound
		$stereo =  $sc->findvalue( './dss' );
		if( $stereo eq 'True' ){
   	 		$ce->{stereo} = 'surround';
		}

		# dolby digital surround / AC-3 5.1
		$stereo =  $sc->findvalue( './dds' );
		if( $stereo eq 'True' ){
   	 		$ce->{stereo} = 'dolby digital';
		}

		$stereo =  $sc->findvalue( './zs' );
		if( $stereo eq 'True' ){
   	 		$ce->{stereo} = 'bilingual';
		}

		my $widescreen =  $sc->findvalue( './bb' );
		if( $widescreen eq 'True' ){
   	 		$ce->{aspect} = '16:9';
		}

#		my $captions =  $sc->findvalue( './ut' );
#		if( $captions eq 'True' ){
#   	 		$ce->{captions} = 'teletext';
#		}

		# TODO how does ORF signal HD? just slap quality=hdtv on everthing on channels with xmltvid hd.*
		if( $chd->{xmltvid} =~ m|^hd\.| ){
			$ce->{quality} = 'hdtv';
		}
	
  	  $dsh->AddProgramme( $ce );
 	 }
  
  # Success
  return 1;
}

sub ParseTime {
  my( $text ) = @_;

  my( $hour , $min );

  if( $text =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  }
  
  return sprintf( "%02d:%02d", $hour, $min );
}
    
1;
