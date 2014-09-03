package NonameTV::Importer::Axess;

use strict;
use warnings;

=pod

Importer for files in the format provided by Axess Television.
This is supposedly the format defined by TTSpektra. 

=cut

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV qw/ParseXml ParseDescCatSwe AddCategory norm/;

use DateTime;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
    defined( $self->{LoginUrl} ) or die "You must specify LoginUrl";
    defined( $self->{Username} ) or die "You must specify Username";
    defined( $self->{Password} ) or die "You must specify Password";

    $self->{datastore}->{SILENCE_END_START_OVERLAP} = 1;
    return $self;
}

sub InitiateDownload {
  my $self = shift;

  my $mech = $self->{cc}->UserAgent();

  $mech->get($self->{LoginUrl});

  $mech->submit_form(
      with_fields => { 
	'ctl00$body$loginControl$UserName' => $self->{Username},
	'ctl00$body$loginControl$Password' => $self->{Password},
      },
      button => 'ctl00$body$loginControl$LoginButton',
  );

  if( $mech->content =~ /<TTSTVR/ ) {
    return undef;
  }
  else {
    return "Login failed";
  }
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $date ) = ( $objectname =~ /_(.*)$/ );
 
  my $url = $self->{UrlRoot} . $date;

  # Only one url to look at and no error
  return ([$url], undef);
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  if( $$cref eq "" ) {
    return (undef, "No data found." );
  }

  if( $$cref !~ /^\s*<\?xml/ ) {
    # This happens when we try to fetch data for yesterday.
    return (undef, "Data is not xml.");
  }

  my $doc = ParseXml( $cref );
  
  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  } 

  my $xp = XML::LibXML::XPathContext->new($doc);
  
  # Create namespace
  # http://perl-xml.sourceforge.net/faq/#namespaces_xpath
  $xp->registerNs(tt => 'http://www.ttspektra.se' );
  
  # Remove all OtherBroadcast since they change
  # each time the data for today is downloaded.
  my $ns = $xp->find( "//tt:OtherBroadcast" );

  foreach my $n ($ns->get_nodelist) {
    $n->unbindNode();
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

sub ImportContent {
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};

  my $doc = ParseXml( $cref );
  my $xp = XML::LibXML::XPathContext->new($doc);
  
  # Create namespace
  # http://perl-xml.sourceforge.net/faq/#namespaces_xpath
  $xp->registerNs(tt => 'http://www.ttspektra.se' );
  
  my $ns = $xp->find( "//tt:TVRProgramBroadcast" );

  if( $ns->size() == 0 ) {
    error( "$batch_id: No data found" );
    return 0;
  }
  
  foreach my $pb ($ns->get_nodelist)
  {
    my $start = $xp->findvalue( 
      'tt:TVRBroadcast/tt:BroadcastDateTime/tt:StartDateTime', $pb );
    my $end = $xp->findvalue( 
      'tt:TVRBroadcast/tt:BroadcastDateTime/tt:EndDateTime', $pb );
    my $url = $xp->findvalue( 
      'tt:TVRBroadcast/tt:BroadcastInformation/tt:WebPage/@URL', $pb );
    my $title = norm( $xp->findvalue( 'tt:TVRProgram/tt:Title', $pb ) );
    my $subtitle = norm( 
      $xp->findvalue( 'tt:TVRProgram/tt:VersionableInfo/tt:Version/tt:EpisodeTitle', $pb ) );

    if( $title eq $subtitle ) {
      my( $title2, $subtitle2 ) = ( $title =~ /(.*?) - (.*)/ );
      if( defined( $subtitle2 ) ) {
        $title = $title2;
        $subtitle = $subtitle2;
      }
      else {
        $subtitle = "";
      }
    }

    my $intro = $xp->findvalue( 'tt:TVRProgram/tt:Intro', $pb );
    my $description = $xp->findvalue( 
      'tt:TVRProgram/tt:Description/tt:TextDesc', $pb );
    my $episodenum = $xp->findvalue( 'tt:TVRProgram/tt:EpisodeNumber', $pb );

		# Del 3 av 13 in description - of_episod is not in use at the moment
    my ( $ep_nr, $eps ) = ($description =~ /Del\s+(\d+)\s+av\s+(\d+)/ );

    my $ce = {
      channel_id  => $chd->{id},
      start_time  => ParseDateTime( $start ),
      title       => norm( $title ),
      description => norm( "$intro $description" ),
      url         => $url,
    };

	my ( $program_type, $category ) = ParseDescCatSwe( $ce->{description} );
  	AddCategory( $ce, $program_type, $category );
    
    if( my( $dumperino, $year ) = ($description =~ /(Produktions.r|Produktion.r):\s+(\d\d\d\d)\./) )
    {
      $ce->{production_date} = "$year-01-01";
    }

    # original title
    if( my( $orgtitle ) = ($description =~ /Originaltitel:\s+(.*?)\./) )
    {
        $ce->{original_title} = norm($orgtitle);
    }

    if( $end ne "" ) {
	$ce->{end_time} = ParseDateTime( $end );
    }

    if( $subtitle ne "" ) {
      $ce->{subtitle} = norm( $subtitle );
    }

    if( $episodenum ne "" ) {
      $ce->{episode} = " . " . ($episodenum-1) . " . ";
    }
    
    
    if( defined($ep_nr) ) {
      $ce->{episode} = sprintf( " . %d/%d . ", $ep_nr-1, $eps );
    }

    $ds->AddProgramme( $ce );
  }

  return 1;
}

sub ParseDateTime {
  my( $str ) = @_;

  my( $year, $month, $day, $hour, $minute, $second ) = ($str =~ /
    ^(\d{4})-(\d{2})-(\d{2})T
     (\d{2}):(\d{2}):(\d{2})$/x );

  my $dt;
  eval {
    $dt = DateTime->new(
    year => $year,
    month => $month,
    day => $day,
    hour => $hour,
    minute => $minute,
    time_zone => 'local' );
  };

  error( "$@" ) if $@;

  return undef if not defined $dt;
  
  if( $second > 0 ) {
    $dt->add( minutes => 1 );
  }
  
  $dt->set_time_zone( 'UTC' );
  
  return $dt->ymd() . " " . $dt->hms();
}

# Kanal5 Util
sub parse_person_list
{
  my( $str ) = @_;

  # Remove all variants of m.fl.
  $str =~ s/\s*m[\. ]*fl\.*\b//;
  
  # Remove trailing '.'
  $str =~ s/\.$//;

  $str =~ s/\boch\b/,/;
  $str =~ s/\bsamt\b/,/;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    s/^.*\s+-\s+//;
  }

  return join( ";", grep( /\S/, @persons ) );
}

1;
