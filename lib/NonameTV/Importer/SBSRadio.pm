package NonameTV::Importer::SBSRadio;

use strict;
use utf8;
use warnings;

=pod

Importer for SBS Radio (Mix Megapol, The Voice and more)
The file downloaded is in JSON format.

=cut

use DateTime;
use JSON -support_by_pp;
use HTTP::Date;
use Data::Dumper;

use NonameTV qw/ParseXml normUtf8 AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w progress error f/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

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

  my( $date ) = ($objectname =~ /_(.*)/);
  my( $year, $month, $day ) = split( /-/, $date );
  
  my $url = $self->{UrlRoot} . $chd->{grabber_info} . "/epg/" . $year . $month . $day . ".json";

  return( $url, undef );
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;
  
  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};
  
  my $currdate = "x";
  
  my( $date ) = ($batch_id =~ /_(.*)/);
  $dsh->StartDate( $date , "00:00" );

  my $json = new JSON;

  my $doc  = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($$cref);

 	 foreach my $sc (@{$doc})
  	{
		# Date
		my $date = $sc->{date};
		
		my $start_time = $sc->{start};
		
		my $end_time = $sc->{end};
		
	
		my $title = $sc->{name};
		my $desc = $sc->{descr};
		#my $url = $sc->findvalue( './link' );

		progress("SBSRadio: $chd->{xmltvid}: $start_time - $title");

  	my $ce = {
  		channel_id	=> $chd->{id},
  		title 	  	=> normUtf8($title),
 	  	start_time  => $start_time,
 	  	end_time 		=> $end_time,
 	  	description	=> normUtf8($desc),
 	  	#url => $url,
   	};
	
  	  $dsh->AddProgramme( $ce );
 	 }
 	 
 	 #$dsh->EndBatch( 1 );

  # Success
  return 1;
}

1;