package NonameTV::Augmenter::PreviouslyShown;

use strict;
use warnings;

use Data::Dumper;
use Encode;
use utf8;

use NonameTV qw/norm/;
use NonameTV::Augmenter::Base;
use NonameTV::Config qw/ReadConfig/;
use NonameTV::Log qw/w d/;
use DateTime;
use DateTime::Format::MySQL;

use base 'NonameTV::Augmenter::Base';


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

#    print Dumper( $self );

#    defined( $self->{Language} ) or die "You must specify Language";

    # need config for main content cache path
    my $conf = ReadConfig( );

    return $self;
}

sub AugmentProgram( $$$ ){
  	my( $self, $ceref, $ruleref ) = @_;

 	# empty hash to get all attributes to change
  	my $resultref = {};
  	# result string, empty/false for success, message/true for failure
  	my $result = '';
  	
	# So, we have a channelgroup which we want previously_shown for.
	# It first checks so it got everything it needs, which is:
	# title, episode, subtitle (if it exists)
	#
	# Match_by needs to be the grabber name.
	#
	# It fetches all channels for that specific channelgroup (grabber).
	# Then grabs the programs with start which is the AugmentProgram's
	# starttime-50mins

	my $matchdone = 0;

	# Date Time
	my $dt_org = DateTime::Format::MySQL->parse_datetime( $ceref->{start_time} );
	my $dt = $dt_org->clone->subtract( minutes => 50);
	my $dt_new = $dt->ymd("-")." ".$dt->hms(":");
	
	#print Dumper($dt_new);

	
	# Both
	if( $ruleref->{remoteref} ) {
		if( !$matchdone && $ceref->{'title'} ){
		
			# Grabber null
			if($ruleref->{remoteref} eq "") {
				$result = "channel id $ceref->{channel_id} need to have grabber in the remoteref";
			    w( $result );
			    $resultref = undef;
			}
			
			#print Dumper(@channels);
			my @cids = ();
			my @c = $self->{datastore}->FindGrabberChannels( $ruleref->{remoteref} );
			
			foreach my $fooArray (@c)
			{
			  foreach my $fooCell (@$fooArray)
			  {
				push( @cids , $fooCell->{id} );
			  }
			}
			
			my $cids_string = join(', ', @cids);
		
			# Match a movie (they not have subtitles nor episode info)
			if( !$matchdone && $ceref->{program_type} eq "movie" )
			{
			  my ( $res, $sth ) = $self->{datastore}->sa->Sql( "
		          SELECT c.xmltvid, p.start_time from programs p
		          LEFT JOIN channels c ON c.id = p.channel_id
		          WHERE p.channel_id IN ( ".$cids_string." ) and p.title = ? and p.end_time <= ? and p.end_time != '0000-00-00 00:00' and p.program_type = ?
		          ORDER BY p.start_time asc, p.end_time desc
		          LIMIT 1", 
		        [$ceref->{title}, $dt_new, $ceref->{program_type}] );
		      my $ce;
		      
		      
		      
		      #die();
		      
		      while( defined( my $ce = $sth->fetchrow_hashref() ) ) {
		        print("FILM: $ceref->{title} - old: $ceref->{start_time} - prev: $ce->{start_time}\n");
		        $resultref->{previously_shown} = $ce->{xmltvid}."|".$ce->{start_time};
		        
		        
		        $matchdone=1;
		      }
			}
		
			# Match by episode
			if( !$matchdone && $ceref->{episode} && $ceref->{episode} ne '' ) {
				#w("Match by episode");
				
				my ( $res, $sth ) = $self->{datastore}->sa->Sql( "
		          SELECT c.xmltvid, p.start_time from programs p
		          LEFT JOIN channels c ON c.id = p.channel_id
		          WHERE p.channel_id IN ( ".$cids_string." ) and p.title = ? and p.episode = ? and p.end_time <= ? and p.end_time != '0000-00-00 00:00' and p.program_type = ?
		          ORDER BY p.start_time asc, p.end_time desc
		          LIMIT 1", 
		        [$ceref->{title}, $ceref->{episode}, $dt_new, $ceref->{program_type}] );
		        
		      my $ce;
		      while( defined( my $ce = $sth->fetchrow_hashref() ) ) {
		        print("$ceref->{title} - old: $ceref->{start_time} - prev: $ce->{start_time}\n");
		        $resultref->{previously_shown} = $ce->{xmltvid}."|".$ce->{start_time};
		        
		        $matchdone=1;
		      }
			}
			
			# Match by episode title
			if( !$matchdone && $ceref->{subtitle} && $ceref->{subtitle} ne '' ) {
				#w("Match by subtitle");
				
				my ( $res, $sth ) = $self->{datastore}->sa->Sql( "
		          SELECT c.xmltvid, p.start_time from programs p
		          LEFT JOIN channels c ON c.id = p.channel_id
		          WHERE p.channel_id IN ( ".$cids_string." ) and p.title = ? and p.subtitle = ? and p.end_time <= ? and p.end_time != '0000-00-00 00:00' and p.program_type = ?
		          ORDER BY p.start_time asc, p.end_time desc
		          LIMIT 1", 
		        [$ceref->{title}, $ceref->{subtitle}, $dt_new, $ceref->{program_type}] );
		      my $ce;
		      while( defined( my $ce = $sth->fetchrow_hashref() ) ) {
		        print("SUB: $ceref->{title} - old: $ceref->{start_time} - prev: $ce->{start_time}\n");
		        $resultref->{previously_shown} = $ce->{xmltvid}."|".$ce->{start_time};
		        
		        $matchdone=1;
		      }
			}
		}
	} else {
		if( !$matchdone && $ceref->{'title'} ){
			# Match a movie (they not have subtitles nor episode info)
			if( !$matchdone && $ceref->{program_type} eq "movie" )
			{
			  my ( $res, $sth ) = $self->{datastore}->sa->Sql( "
		          SELECT c.xmltvid, p.start_time from programs p
		          LEFT JOIN channels c ON c.id = p.channel_id
		          WHERE p.channel_id = ? and p.title = ? and p.end_time <= ? and p.end_time != '0000-00-00 00:00' and p.program_type = ?
		          ORDER BY p.start_time asc, p.end_time desc
		          LIMIT 1", 
		        [$ceref->{channel_id}, $ceref->{title}, $dt_new, $ceref->{program_type}] );
		      my $ce;
		      while( defined( my $ce = $sth->fetchrow_hashref() ) ) {
		        print("FILM: $ceref->{title} - old: $ceref->{start_time} - prev: $ce->{start_time}\n");
		        $resultref->{previously_shown} = $ce->{xmltvid}."|".$ce->{start_time};
		        
		        $matchdone=1;
		      }
			}
		
			# Match by episode
			if( !$matchdone && $ceref->{episode} && $ceref->{episode} ne '' ) {
				#w("Match by episode");
				
			  my ( $res, $sth ) = $self->{datastore}->sa->Sql( "
		          SELECT c.xmltvid, p.start_time from programs p
		          LEFT JOIN channels c ON c.id = p.channel_id
		          WHERE p.channel_id = ? and p.title = ? and p.episode = ? and p.end_time <= ? and p.end_time != '0000-00-00 00:00' and p.program_type = ?
		          ORDER BY p.start_time asc, p.end_time desc
		          LIMIT 1", 
		        [$ceref->{channel_id}, $ceref->{title}, $ceref->{episode}, $dt_new, $ceref->{program_type}] );
		      my $ce;
		      while( defined( my $ce = $sth->fetchrow_hashref() ) ) {
		        print("$ceref->{title} - old: $ceref->{start_time} - prev: $ce->{start_time}\n");
		        $resultref->{previously_shown} = $ce->{xmltvid}."|".$ce->{start_time};
		        
		        $matchdone=1;
		      }
			}
			
			# Match by episode title
			if( !$matchdone && $ceref->{subtitle} && $ceref->{subtitle} ne '' ) {
				my ( $res, $sth ) = $self->{datastore}->sa->Sql( "
		          SELECT c.xmltvid, p.start_time from programs p
		          LEFT JOIN channels c ON c.id = p.channel_id
		          WHERE p.channel_id = ? and p.title = ? and p.subtitle = ? and p.end_time <= ? and p.end_time != '0000-00-00 00:00' and p.program_type = ?
		          ORDER BY p.start_time asc, p.end_time desc
		          LIMIT 1", 
		        [$ceref->{channel_id}, $ceref->{title}, $ceref->{subtitle}, $dt_new, $ceref->{program_type}] );
		      my $ce;
		      while( defined( my $ce = $sth->fetchrow_hashref() ) ) {
		        print("SUB: $ceref->{title} - old: $ceref->{start_time} - prev: $ce->{start_time}\n");
		        $resultref->{previously_shown} = $ce->{xmltvid}."|".$ce->{start_time};
		        
		        $matchdone=1;
		      }
			}
		}
	}
	
	
	return( $resultref, $result );
}


1;
