package NonameTV::Importer::RadioSevenSE;

use strict;
use utf8;
use warnings;

=pod

Importer for RadioSeven.se
Downloaded format is XML, its the current week.

=cut

use DateTime;
use XML::LibXML;
use HTTP::Date;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;
 
  my $url = $self->{UrlRoot};

  return( $url, undef );
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  
  my $xml = XML::LibXML->new;
  my $doc;
  eval { $doc = $xml->parse_string($$cref); };
  if( $@ ne "" )
  {
    f "Failed to parse $@";
    return 0;
  }
 
 	 # Find all "z:row"-entries.
 	 my $ns = $doc->find( "//program" );

 	 if( $ns->size() == 0 )
 	 {
 	   f "No data found";
 	   return 0;
 	 }
  
  	 
 	 foreach my $sc ($ns->get_nodelist)
  	{
		
		# Date
		my $start = $self->create_dt( $sc->findvalue( './start' ) );
		my $start_time = $start->ymd("-").' '.$start->hms(":");
		
		my $end = $self->create_dt( $sc->findvalue( './end' ) );
		my $end_time = $end->ymd("-").' '.$end->hms(":");
		
	
		my $title = $sc->findvalue( './title' );
		my $desc = $sc->findvalue( './description' );
		my $url = $sc->findvalue( './link' );

		progress("RadioSeven: $chd->{xmltvid}: $start_time - $title");

  	my $ce = {
  		channel_id	=> $chd->{id},
  		title 	  	=> norm($title),
 	  	start_time  => $start_time,
 	  	end_time 		=> $end_time,
 	  	description	=> norm($desc),
 	  	url => $url,
   	};
   	
   	if( my( $presenters ) = ($desc =~ /med\s*(.*)/ ) )
    {
      $ce->{presenters} = parse_person_list( $presenters );
    }
	
  	  $ds->AddProgramme( $ce );
 	 }

  # Success
  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
  
  my( $year, $month, $day, $hour, $minute ) = 
      ($str =~ /(\d+)-(\d+)-(\d+) (\d+):(\d+)$/ );

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'Europe/Stockholm',
                          );
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

# From Kanal5_util
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

  return join( ", ", grep( /\S/, @persons ) );
}
    
1;
