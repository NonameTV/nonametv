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

use NonameTV::Importer::BaseWeekly;

use base 'NonameTV::Importer::BaseWeekly';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  	$self->{datastorehelper} = $dsh;
  	
  	$self->{MinWeeks} = 0;
    $self->{MaxWeeks} = 0;

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
  #my $dsh = $self->{datastorehelper};
  #my $currdate = "x";
  
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
		
		my $end = $self->create_dt_end( $sc->findvalue( './end' ) );
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

sub create_dt_end
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
    
1;