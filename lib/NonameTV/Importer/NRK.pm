package NonameTV::Importer::NRK;

=pod

This importer imports data from the NRK presservice.
The data is fetched per day/channel.

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;
use Data::Dumper;

use NonameTV qw/MyGet norm Html2Xml/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);
    
    
    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";
    
    $self->{datastore}->{augment} = 1;
    
    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;
    
    return $self;
}

sub ImportContent
{
    my $self = shift;
    
    my( $batch_id, $cref, $chd ) = @_;
    
    my $ds = $self->{datastore};
    my $dsh = $self->{datastorehelper};
    
    $ds->{SILENCE_END_START_OVERLAP}=1;
    
    my( $date ) = ($batch_id =~ /_(.*)$/);
    
    my $xml = XML::LibXML->new;
    my $doc;
    
    eval { $doc = $xml->parse_string($$cref); };
    if( $@ ne "" )
    {
        error( "$batch_id: Failed to parse $@" );
        return 0;
    }
    
    # Find all "sending" entries
    my $ns = $doc->find( "//SENDING" );

    # Start date
    
    $dsh->StartDate( $date, "00:00" );
    
    foreach my $sc ($ns->get_nodelist)
    {
    
        my $start = $sc->findvalue( './ANNTID' );
        $start =~ s/\./:/;
               
        #my $stop = $sc->findvalue( './SLUTTID' );
        #$stop =~ s/\./:/;
        
        my $title = $sc->findvalue( './SERIETITTEL' );
        my $subtitle = $sc->findvalue( './SENDETITTEL' );
        if ($title eq "") {
            $title = $subtitle;
        }
        #my $bigtitle = "T$title - S$subtitle";
        #my $bigtitle = "$title: $subtitle" unless ($title eq $subtitle);
        #$bigtitle =~ s/^:.//;
        if ($title eq $subtitle) {
            $subtitle = "";
        } else {
            $title = "$title: $subtitle";
            
        }
        #if ($title eq "") {
        #    $title = $subtitle;
        #    $subtitle = "";
        #}
        
        my $desc = $sc->findvalue( './RUBRIKKTEKST' );
        my( $episode, $ep, $eps, $seas, $dummy );
        # Avsnitt 2:6
  			( $ep, $eps ) = ($desc =~ /\((\d+)\:(\d+)\)/ );
  			$desc =~ s/\((\d+)\:(\d+)\)//;
  			$desc = norm($desc);
        
        # Avsnitt 2
  			( $ep ) = ($desc =~ /\s+\((\d+)\)/ ) if not $ep;
  			$desc =~ s/\((\d+)\)$//;
  			$desc = norm($desc);
        
        # S�song 2
  			( $seas ) = ($desc =~ /Sesong\s*(\d+)/ );
				$desc =~ s/Sesong (\d+)$//;
				$desc = norm($desc);
        # my $text = $sc->findvalue( './TEKSTEKODE' );
        
        my ( $subtitles ) = ($desc =~ /\((.*)\)$/ );
        if($subtitles) {
        	my ( $realtitle, $realsubtitle ) = ($subtitles =~ /(.*)\:(.*)/ );
        	if(defined($realtitle)) {
        		$title = $realtitle;
        		$subtitles = $realsubtitle;
        	}
        	
        }
        $desc =~ s/\((.*)\)$//;
        $desc = norm($desc);
        
        #$subtitle = ($desc =~ /\((.*)\)$/ );
        
    # Episode info in xmltv-format
      if( (defined $ep) and (defined $seas) and (defined $eps) )
      {
        $episode = sprintf( "%d . %d/%d .", $seas-1, $ep-1, $eps );
      }
      elsif( (defined $ep) and (defined $seas) and !(defined $eps) )
      {
        $episode = sprintf( "%d . %d .", $seas-1, $ep-1 );
      }
      elsif( (defined $ep) and (defined $eps) and !(defined $seas) )
      {
        $episode = sprintf( ". %d/%s .", $ep-1, $eps );
      }
      elsif( (defined $ep) and !(defined $seas) and !(defined $eps) )
      {
        $episode = sprintf( ". %d .", $ep-1 );
      }
        
         
        my $ce = {
            start_time  => $start,
            #end_time   => $stop,
            description => norm($desc),
            title       => norm($title),
        };
        
        if(defined($subtitles) and ($subtitles ne "")) {
        	$ce->{subtitle} = norm($subtitles);
        }
        
        my ( $filmtitle ) = ($ce->{title} =~ /^Film\:(.*)$/ );
        if(defined($filmtitle) and ($filmtitle ne "")) {
        	 $ce->{program_type} = "movie";
        	 $ce->{title} = norm($filmtitle);
        }
        
        $ce->{episode} = $episode if $episode;
        
        # Directors
        if( my( $directors ) = ($desc =~ /Regi\:\s*(.*)$/) )
    		{
      		$ce->{directors} = parse_person_list( $directors );
      		$desc =~ s/Regi\:(.*)$//;
      		$desc = norm($desc);
    		}
        
        # Get actors
        if( my( $actors ) = ($desc =~ /Med\:\s*(.*)$/ ) )
    		{
      		$ce->{actors} = parse_person_list( $actors );
      		#$desc =~ s/Med\:(.*)$//;
      		#$desc = norm($desc);
   			}
        
        $dsh->AddProgramme( $ce );
    
    
    }
    
    return 1;
}

sub FetchDataFromSite
{

    my $self = shift;
    my( $batch_id, $data ) = @_;
    
    my( $date ) = ($batch_id =~ /_(.*)/);
    
    my ($year, $month, $day) = split(/-/, $date);

    my $u = URI->new($self->{UrlRoot});
    $u->query_form( {
    		d2_proxy_skip_encoding_all => 'true',
    		d2_proxy_komponent => '/!potkomp.d2d_pressetjeneste.fkt_pressesoket_flex',
        p_fom_dag => $day,
        p_tom_dag => $day,
        p_fom_mnd => $month,
        p_tom_mnd => $month,
        p_fom_ar  => $year,
        p_tom_ar  => $year,
        p_format  => "XML",
        p_type    => "prog",
        p_knapp   => "Last ned"
    });
    my $channeluri = $u->as_string."&".$data->{grabber_info};
    # print "DEBUG: $channeluri\n";
    my ( $content, $code ) = MyGet ($channeluri );
    
    return( $content, $code );
}


sub createDate
{
    my $self = shift;
    my( $str ) = @_;
    
    my $date = substr( $str, 0, 2 );
    my $month = substr( $str, 2, 2 );
    my $year = substr( $str, 4, 4 );
    
    return "$year-$month-$date";

}

sub parse_person_list
{
  my( $str ) = @_;
  
  # Remove all variants of m.fl.
  $str =~ s/\s*m[\. ]*fl\.*\b//;
  
  # Remove trailing '.'
  $str =~ s/\.$//;

  $str =~ s/\bog\b/,/;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    # The Cast-entry is sometimes cutoff, which means that the
    # character name might be missing a trailing ).
    s/\s*\(.*$//;
    s/.*\s+-\s+//;
    s/\.//;
  }

  return join( ", ", grep( /\S/, @persons ) );
}

1;

