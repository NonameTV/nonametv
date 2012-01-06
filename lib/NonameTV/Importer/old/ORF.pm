package NonameTV::Importer::ORF;

use strict;
use warnings;

=pod

Importer for data from ORF (www.orf.at)
The data is in RSS format.

Channels: ORF1, ORF2

Features:

=cut

use DateTime;
use XML::RSS::Parser;

use NonameTV qw/MyGet norm AddCategory/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Vienna" );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContent
{
  my $self = shift;

  my( $batch_id, $cref, $chd ) = @_;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;

  my $p = XML::RSS::Parser->new;
  my $feed;
  eval { $feed = $p->parse_string($$cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse $@" );
    return 0;
  }

  my $feed_title = $feed->query('/channel/title');
  progress( "ORF: $chd->{xmltvid}: Parsing RSS feed '" . $feed_title->text_content . "'" );

  my $itemcount = $feed->item_count;
  progress( "ORF: $chd->{xmltvid}: Found $itemcount shows." );

  my $currdate = "x";

  foreach my $item ( $feed->query('//item') ) { 

    my $date = $item->query('dc:date')->text_content;
    $date =~ s/T.*//;

    if( $date ne $currdate ) {

      $dsh->StartDate( $date , "00:00" );
      $currdate = $date;

      progress("ORF: $channel_xmltvid: Date is: $date");
    }

    my $time = $item->query('title')->text_content;
    my $url = $item->query('link')->text_content;
    my $title = $item->query('description')->text_content;
    my $genre = $item->query('dc:subject')->text_content;

    progress( "ORF: $channel_xmltvid: $time - $title" );

    my $ce = {
      channel_id => $channel_id,
      title => $title,
      start_time => $time,
    };

    if( $genre ){
      my($program_type, $category ) = $ds->LookupCat( 'ORF', $genre );
      AddCategory( $ce, $program_type, $category );
    }

    $ce->{url} = $url if $url;

    $dsh->AddProgramme( $ce );
  }
  
  
  # Success
  return 1;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my $url = $self->{UrlRoot} . "/" . $data->{grabber_info};
  progress("ORF: fetching data from $url");

  my( $content, $code ) = MyGet( $url );
  return( $content, $code );
}

1;
