package NonameTV::Importer::ZDF;

use strict;
use warnings;

=pod

Importer for data from ZDF. 
One file per channel and week downloaded from their site.
The downloaded file is in xml-format.
Same format as DreiSat.

=cut

use DateTime;
use NonameTV qw/ParseXml/;
use NonameTV::Log qw/progress w error/;

use NonameTV::Importer::DreiSat;

use base 'NonameTV::Importer::DreiSat';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{Username} ) or die "You must specify Username";
    defined( $self->{Password} ) or die "You must specify Password";

    $self->{datastore}->{augment} = 1;

    return $self;
}

sub InitiateDownload {
  my $self = shift;

  my $mech = $self->{cc}->UserAgent();

  my $response = $mech->get('https://pressetreff.zdf.de/index.php?id=vptzdf&user=' . $self->{Username} . '&pass=' . $self->{Password} . '&logintype=login&pid=83&redirect_url=&tx_felogin_pi1[noredirect]=0');

  if ($response->is_success) {
    return undef;
  } else {
    return $response->status_line;
  }
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  my( $year, $week ) = ( $objectname =~ /(\d+)-(\d+)$/ );
 
  my $station = "01"; # hd.zdf.de

  # get first day in the given batch
  my $first = DateTime->new( year=>$year, day => 4 );
  $first->add( days => $week * 7 - $first->day_of_week - 6 );
  # adjust first day by 2
  $first->add (days => -2);

  my $date = $first->dmy( '.' );

  my $url = 'https://pressetreff.zdf.de/index.php?id=386&tx_zdfprogrammdienst_pi1%5Bformat%5D=xml&tx_zdfprogrammdienst_pi1%5Blongdoc%5D=1&tx_zdfprogrammdienst_pi1%5Bstation%5D=' . $station . '&tx_zdfprogrammdienst_pi1%5Bdatestart%5D=' . $date . '&tx_zdfprogrammdienst_pi1%5Bweek%5D=' . $week . '&tx_zdfprogrammdienst_pi1%5Baction%5D=showDownloads&tx_zdfprogrammdienst_pi1%5Bcontroller%5D=Broadcast';

  progress("ZDF: fetching data from $url");

  return( $url, undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  # fixup entities
  $$cref =~ s|&amp;amp;ad|&ad;|g;
  $$cref =~ s|&amp;amp;dd|&dd;|g;
  $$cref =~ s|&amp;amp;ds|&ds;|g;
  $$cref =~ s|&amp;amp;f16|&f16;|g;
  $$cref =~ s|&amp;amp;hd|&hd;|g;
  $$cref =~ s|&amp;amp;st|&st;|g;
  $$cref =~ s|&amp;amp;vo|&vo;|g;

  my $doc = ParseXml( $cref );

  if( not defined $doc ) {
    return (undef, 'ParseXml failed' );
  } 

  # <programmdaten sender="ZDF" woche="201149" erstelldatum="05.12.2011 19:02:10">

  # Find all "Schedule"-entries.
#  my $gotweek = $doc->findvalue( '/programmdaten/@woche' );

#  if( $gotweek ne $year . $week ) {
#    return (undef, sprintf( 'wanted week %s but got week %s instead', $year.$week, $gotweek ) );
#  }

  # remove date of creation as its always changing
  foreach my $node ($doc->find ('/programmdaten/@erstelldatum')->get_nodelist) {
    $node->unbindNode ();
  }

  # fix attributes which are real xml entities in html encoding (doh)
  foreach my $node ($doc->find ('//attribute')->get_nodelist) {
    my $attribute = $node->textContent;
    $attribute =~ s|&amp;|&|g;
    $node->removeChildNodes();
    $node->appendTextNode( $attribute );
  }
  
  my $str = $doc->toString( 1 );

  return( \$str, undef );
}

1;
