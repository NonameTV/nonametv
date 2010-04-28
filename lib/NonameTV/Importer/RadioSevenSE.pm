package NonameTV::Importer::RadioSevenSE;

use strict;
use warnings;

=pod

Sample importer for http-based sources.
See xxx for instructions. 

=cut

use Encode;
use Switch;
use HTML::TableExtract;
use HTML::Parse;
use Unicode::String;

use NonameTV qw/MyGet norm Html2Xml ParseXml/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/p w f/;

use NonameTV qw/Html2Xml/;

use NonameTV::Importer::BaseOne;

use base 'NonameTV::Importer::BaseOne';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    if (!defined ( $self->{UrlRoot} )) {
      $self->{UrlRoot} = 'http://www.radioseven.se/default.asp?page=tabla';
    }

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  # Only one url to look at and no error
  return ([$self->{UrlRoot}], undef);
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  # fix buggy html
  $$cref =~ s|charset=charset=|charset=|g;

  # fix CRLF line endings
  $$cref =~ s|||g;

  $$cref = Unicode::String::latin1 ($$cref)->utf8 ();

  my $doc = Html2Xml( $$cref );
  
  if( not defined $doc ) {
    return (undef, "Html2Xml failed" );
  } 

  # remove head
  foreach my $node ($doc->find ("//head")->get_nodelist) {
    $node->unbindNode ();
  }

  # save program table
  my $saveddata;
  my @nodes =$doc->find ("//div/table/tr/td/table")->get_nodelist();
  $saveddata = $nodes[1];
  $nodes[1]->unbindNode ();

  # drop body content
  foreach my $node ($doc->find ("/html/body")->get_nodelist) {
    $node->removeChildNodes ();
    $node->addChild ($saveddata);
  }

  # reattach program table


  my $ns = $doc->find( "//@*" );
  # Remove all attributes that we ignore anyway.
  foreach my $attr ($ns->get_nodelist) {
    $attr->unbindNode();
  }

  $ns = $doc->find( "//font" );
  # Remove all attributes that we ignore anyway.
  foreach my $attr ($ns->get_nodelist) {
    my @temp = $attr->getChildNodes ();
    foreach my $node (@temp) {
      $attr->getParentNode->insertBefore ($node, $attr);
    }
    $attr->unbindNode();
  }

  $ns = $doc->find( "//a" );
  # Remove all attributes that we ignore anyway.
  foreach my $attr ($ns->get_nodelist) {
    my @temp = $attr->getChildNodes ();
    foreach my $node (@temp) {
      $attr->getParentNode->insertBefore ($node, $attr);
    }
    $attr->unbindNode();
  }

  $ns = $doc->find( "//b" );
  # Remove all attributes that we ignore anyway.
  foreach my $attr ($ns->get_nodelist) {
    my @temp = $attr->getChildNodes ();
    foreach my $node (@temp) {
      $attr->getParentNode->insertBefore ($node, $attr);
    }
    $attr->unbindNode();
  }

  $ns = $doc->find( "//strong" );
  # Remove all attributes that we ignore anyway.
  foreach my $attr ($ns->get_nodelist) {
    my @temp = $attr->getChildNodes ();
    foreach my $node (@temp) {
      $attr->getParentNode->insertBefore ($node, $attr);
    }
    $attr->unbindNode();
  }

  my $str = $doc->toString(1);

  $str =~ s|<br /><br />|<br /><br />\n|g;
  $str =~ s|</table>|</table>\n|g;
  $str =~ s| <br />|<br />|g;
  $str =~ s| <br />|<br />|g;

  return( \$str, undef );
}

sub ContentExtension {
  return 'html';
}

sub FilteredExtension {
  return 'html';
}

sub ImportContent {
  my $self = shift;

  my( $batch_id, $xmldata, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  # find first <td>.*DAG</td>
  my $firstday = ($$xmldata =~ m|<td>(.*)DAG</td>|);

  # find start DateTime
  #my $firstday = $hierkommtshin;
  $firstday =~ s|\n||g;
#  $firstday =~ s|^[[:space:]]*||g;
#  $firstday =~ s|[[:space:]]*$||g;
  $firstday = lc ($firstday);
  switch ($firstday) {
    case "måndag" { $firstday=1 }
    case "tisdag" { $firstday=2 }
    case "onsdag" { $firstday=3 }
    case "torsdag" { $firstday=4 }
    case "fredag" { $firstday=5 }
    case "lördag" { $firstday=6 }
    case "söndag" { $firstday=7 }
    else { print $firstday }
  }

  my $today = DateTime->today (time_zone => 'Europe/Stockholm');
  my $firstdate = $today->clone ();
  if ($today->day_of_week == $firstday) {
  } elsif ($today->day_of_week()%7 == $firstday+1%7) {
    $firstdate->add (day => 1);
  } elsif ($today->day_of_week()%7 == $firstday-1%7) {
    $firstdate->sub (day => 1);
  } else {
    # ERROR
  }
  
  $dsh->StartDate ($firstdate->ymd, $firstdate->hms);

  foreach my $programme (split(/\n/, $$xmldata)) {
    if ($programme =~ m|[[:digit:]]+ - [[:digit:]]+ ((?!<).)+<br />((?!<).)+<br /><br />|) {
      my ($h1, $h2, $t, $desc) = ($programme =~ m|([[:digit:]]+) - ([[:digit:]]+) (.+)<br />(.+)<br /><br />|);

      my $ce = {
        start_time => $h1.":00",
        end_time => $h2.":00",
        title => $t,
        description => $desc
      };

      $dsh->AddProgramme( $ce );
    }
  }

  return 1;
}

1;
