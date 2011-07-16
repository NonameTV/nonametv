package NonameTV::Importer::TVP;

use strict;
use warnings;
use utf8;
use Unicode::String;

=pod

Import data from TVP's presservice at http://www.tvp.pl/prasa/.
The data is downloaded in ;-separated text-files.

=cut


use DateTime;
use Encode;

use NonameTV qw/AddCategory norm/;
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

    $self->{datastore}->{SILENCE_DUPLICATE_SKIP} = 1;

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $month, $day ) = ( $objectname =~ /(\d+)-(\d+)-(\d+)$/ );
 
 	my( $folder, $endtag ) = split( /:/, $chd->{grabber_info} );
 
  my $url = sprintf( "%s%sp%02d%02d_%s.txt",
                     $self->{UrlRoot}, $folder, 
                     $month, $day, $endtag );

  return( $url, undef );
}

sub ContentExtension {
  return 'txt';
}

sub FilteredExtension {
  return 'txt';
}

sub ImportContent {
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

	my $str = decode( "utf-8", $$cref );

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  # Decode the string into perl's internal format.
  # see perldoc Encode

  my( $year, $month, $day ) = ( $batch_id =~ /(\d+)-(\d+)-(\d+)$/ );
  my $date = $year."-".$month."-".$day;

  my $currdate = "x";
  my @rows = split("\n", $$cref );

  if( scalar( @rows < 2 ) )
  {
    error( "$batch_id: No data found" );
    return 0;
  }

  my $columns = [ split( "\t", $rows[0] ) ];

  	if( $date ) {

        progress("TVP: $chd->{xmltvid}: Date is $date");

        if( $date ne $currdate ) {

          #if( $currdate ne "x" ){
          #  $dsh->EndBatch( 1 );
          #}

         # $dsh->StartBatch( $batch_id, $chd->{channel_id} );
          $dsh->StartDate( $date , "00:00" ); 
          $currdate = $date;
        }
      }

  for ( my $i = 2; $i < scalar @rows; $i++ )
  {
  	
  	
  	my $test = norm($rows[$i]);
  	
  	if( isShow( $test ) ) {
  		my( $time, $title ) = ParseShow( norm($test) );
  		
  		
  		progress("TVP: $chd->{xmltvid}: $time - $title");
  		
  		
  		my $ce = {
        channel_id => $chd->{id},
        start_time => $time,
        title => norm($title),
      };
      
      $dsh->AddProgramme( $ce );
  	}


    #$self->extract_extra_info( $ce );
    #$dsh->AddProgramme( $ce );
  }

	# It would be stupid if we dont end the batch
	# $dsh->EndBatch( 1 );
  # Success
  return 1;
}

sub isShow {
  my ( $text ) = @_;

  # format '14.00 Gudstjänst med LArs Larsson - detta är texten'
  if( $text =~ /^\d+\:\d+\s+\S+/i ){
    return 1;
  }

  return 0;
}

sub ParseShow {
  my( $text ) = @_;

  my( $time, $title, $desc );

  ( $time, $title ) = ( $text =~ /^(\d+\:\d+)\s+(.*)$/ );

  # parse description
  # format '14.00 Gudstjänst med LArs Larsson - detta är texten'
  if( $title =~ /-\s+(.*)$/ ){
    ( $desc ) = ( $title =~ /-\s+(.*)$/ );
    $title =~ s/-\s+(.*)$//;
  }
  
  if( $title =~ /;\s+(.*)$/ ){
    ( $desc ) = ( $title =~ /;\s+(.*)$/ );
    $title =~ s/;\s+(.*)$//;
  }
 	
 	$title =~ s/\((.*)\)//g;


  my ( $hour , $min ) = ( $time =~ /^(\d+):(\d+)$/ );
  
  if($hour eq 24) {
  	$hour = 00;
  }
  
	$time = sprintf( "%02d:%02d", $hour, $min );

  return( $time, $title );
}

1;
