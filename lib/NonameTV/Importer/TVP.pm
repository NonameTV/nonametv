package NonameTV::Importer::TVP;

use strict;
use warnings;

=pod

Importer for TVP
Channels: TVPolonia, TVP, TVP2, TVPKultura, more.

=cut

use utf8;

use NonameTV qw/AddCategory ParseXml norm/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/w f progress/;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    $self->{datastorehelper} = NonameTV::DataStore::Helper->new( $self->{datastore} );

    $self->{datastore}->{augment} = 0;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;
  my( $year, $month, $day ) = ( $objectname =~ /(\d+)-(\d+)-(\d+)$/ );


 	my( $folder, $endtag ) = split( /:/, $chd->{grabber_info} );
 
  my $url = sprintf( "%s%sxml/p%02d%02d_%s.xml",
                     $self->{UrlRoot}, $folder, 
                     $month, $day, $endtag );

  # Only one url to look at and no error
  return ([$url], undef);
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my ($batch_id, $cref, $chd) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $doc = ParseXml ($cref);
  
  if (not defined ($doc)) {
    f ("$batch_id: Failed to parse.");
    return 0;
  }

  # The data really looks like this...
  my $ns = $doc->find ('//ROOT');
  if( $ns->size() == 0 ) {
    f ("$batch_id: No data found");
    return 0;
  }

  my $date = $doc->findvalue( '//ROOT/DZIEN' );
  $date =~ s|(\d+)\.(\d+)\.(\d+)|$3-$2-$1|;
  
  $dsh->StartDate( $date , '00:00' );


	my $ns2 = $doc->find ('//POZYCJA_PROGRAMOWA');
  foreach my $programme ($ns2->get_nodelist) {
  	# Time
    my ($time) = ($programme->findvalue ('./GODZINA_EMISJI') =~ m|(\d+\:\d+)|);
    if( !defined( $time ) ){
      w( 'programme without start time!' );
    }else{
    	$time = ParseTime($time);
    	
    	
    	# Title
      my ($title) = norm($programme->findvalue ('./TYTUL_CYKLU'));
      if(!$title) {
      	$title = norm($programme->findvalue ('TYTUL'));
      }

      my ($year) = $programme->findvalue ('./ROK_PRODUKCJI');

      my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => $title
      };

			# Episode
			my ($ep) = $programme->findvalue ('./NR_ODCINKA');
			
			# Use year as season if found
  		if( ($ep) and ($year) )
   		{
        $ce->{episode} = sprintf( "%d . %d .", $year-1, $ep-1 );
   		} elsif(($ep) and (!$year)) {
   			$ce->{episode} = sprintf( ". %d .", $ep-1 );
   		}
			

			# Stereo (It's actually in the correct form)
			my ($stereo) = $programme->findvalue ('./DZWIEK');
			$ce->{stereo} = norm($stereo) if $stereo;

			# Aspect (It's actually in the correct form)
			my ($aspect) = $programme->findvalue ('./FORMAT_OBRAZU');
			$ce->{aspect} = norm($aspect) if $aspect;

			# Actors (It's actually in the correct form)
			my ($actors) = $programme->findvalue ('./WYKONAWCY');
			$ce->{actors} = norm($actors) if $actors;

			# Presenters (It's actually in the correct form)
			my ($presenters) = $programme->findvalue ('./REZYSER');
			$ce->{presenters} = norm($presenters) if $presenters;

			# Genre
      my ($genre) = $programme->findvalue ('./RODZAJ');
      my ( $program_type, $categ ) = $self->{datastore}->LookupCat( "TVP", $genre );
      AddCategory( $ce, $program_type, $categ );
      
      # Production Year
      if( $year ){
        $ce->{production_date} = $year . '-01-01';
      }

			#progress("TVP: $chd->{xmltvid}: $time - $title");
      $dsh->AddProgramme( $ce );
    }
  }

  return 1;
}


sub ParseTime {
  my( $text ) = @_;

  my( $hour , $min );

  if( $text =~ /^\d+:\d+$/ ){
    ( $hour , $min ) = ( $text =~ /^(\d+):(\d+)$/ );
  }
  
  # Sometimes hour is 24, then it is 00
  if ($hour eq '24') {
  	$hour = '00';
  }
  
  # Sometimes hour is 25, then it is 01
  if ($hour eq '25') {
  	$hour = '01';
  }
  
  
  
  return sprintf( "%02d:%02d", $hour, $min );
}

1;
