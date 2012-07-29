package NonameTV::Importer::RTVSlo;

=pod

This importer imports data from www.rtvslo.si. The data is fetched
as one html-file per day and channel.

=cut

use strict;
use warnings;

use DateTime;
use XML::LibXML;

use NonameTV qw/MyGet norm Html2Xml ParseXml FindParagraphs/;
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

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $xmltvid, $date ) = ($objectname =~ /^(.*)_(.*)$/);

  my $u = URI->new($self->{UrlRoot});
  $u->query_form( {
    c_mod => 'rspored-v2',
    izbran_program => $chd->{grabber_info},
    izbran_dan => $date,
  });

  progress( "RTVSlo: $xmltvid: Fetching data from " . $u->as_string() );
  return( $u->as_string(), undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  my $doc = Html2Xml( $$cref );

  if( not defined $doc ) {
    return (undef, "Html2Xml failed" );
  }

  #my $paragraphs = FindParagraphs( $doc, "//body//." );
  my $paragraphs = FindParagraphs( $doc, "//div[\@id=\"main\"]//." );

  my $str = join( "\n", @{$paragraphs} );

  return( \$str, undef );
}


sub ContentExtension {
  return 'html';
}

sub FilteredExtension {
  return 'txt';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  $self->{batch_id} = $batch_id;

  my $xmltvid=$chd->{xmltvid};
  my $channel_id = $chd->{id};

  my( $date ) = ($batch_id =~ /_(.*)/);

  my $dsh = $self->{datastorehelper};

  my @paragraphs = split( /\n/, $$cref );
  if( scalar(@paragraphs) == 0 ) {
    error( "$batch_id: No paragraphs found." ) ;
    return 0;
  }

  $dsh->StartDate( $date, "06:00" );

  my $ce = undef;

  my( $time, $title );

  foreach my $text (@paragraphs) {

#print ">$text<\n";

    # skip on some strings
    next if( $text =~ /^Legenda:/i );
    next if( $text =~ /^- /i );
    next if( $text =~ /^V primeru/i );

    if( isDate( $text ) ){

      progress( "RTVSlo: $xmltvid: Date is $text" );

    } elsif( $text =~ /^\d{2}:\d{2}$/ ){

      my( $hour, $min ) = ( $text =~ /^(\d{2}):(\d{2})$/ );
      $hour -= 24 if $hour gt 24;

      $time = $hour . ":" . $min;

    } else {

      $title = $text;

      next if( ! $time );
      next if( ! $title );

      progress( "RTVSlo: $xmltvid: $time - $title" );

      $ce = {
        channel_id => $channel_id,
        start_time => $time,
        title => norm($title),
      };

      $dsh->AddProgramme( $ce );
    }

  }

  return 1;
}

sub isDate
{
  my( $text ) = @_;

  # format 'TV Slovenija 1, nedelja 8. feb. 2009'
  if( $text =~ /^.*,\s*(ponedeljek|torek|sreda|cetrtek|petek|sobota|nedelja)\s+\d+\.\s+(jan|feb)\.\s+\d+$/i ){
    return 1;
  }

  return 0;
}

1;
