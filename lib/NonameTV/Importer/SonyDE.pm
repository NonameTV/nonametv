package NonameTV::Importer::SonyDE;

use strict;
use warnings;

=pod

Imports data for Sony Television Germany Gmbh. The files are sent through MAIL and is in XML format.

Channels: Animax, AXN, Sony Television

=cut

use utf8;

use DateTime;
use XML::LibXML;
use IO::Scalar;
use Data::Dumper;
use Text::Unidecode;
use File::Slurp;
use Encode;

use NonameTV qw/ParseXml norm normLatin1 normUtf8 AddCategory MonthNumber AddCountry/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Berlin" );
  $self->{datastorehelper} = $dsh;

  # use augment
  $self->{datastore}->{augment} = 1;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xml$/i ){
    $self->ImportXML( $file, $chd );
  }

  return;
}

sub ImportXML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};
  $ds->{SILENCE_END_START_OVERLAP}=1;
  $ds->{SILENCE_DUPLICATE_SKIP}=1;

  progress( "SonyDE: $chd->{xmltvid}: Processing XML $file" );

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "SonyDE: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

    # the grabber_data should point exactly to one worksheet
    my $progs = $doc->findnodes( "//broadcast" );

    if( $progs->size() == 0 ) {
      error( "SonyDE: $chd->{xmltvid}: No Rows found" ) ;
      return;
    }

    foreach my $prog ($progs->get_nodelist) {
        my ($start, $end);
        my $title = norm($prog->findvalue( 'title' ) );

        my $date = norm($prog->findvalue( 'start_date' ) );

        if( $date ne $currdate ){
            progress("SonyDE: Date is $date");

            if( $currdate ne "x" ) {
                $dsh->EndBatch( 1 );
            }

            my $batch_id = $chd->{xmltvid} . "_" . $date;
            $dsh->StartBatch( $batch_id , $chd->{id} );
            $dsh->StartDate( $date , "00:00" );
            $currdate = $date;
        }

        # TNT SERIE & TNT FILM
        $start = $prog->findvalue( 'start_time' );
        $end   = $prog->findvalue( 'end_time' );

        my $desc = $prog->findvalue( 'longtext[@type="psynopsis"]' );

        my $ce = {
            channel_id => $chd->{id},
            title => norm($title),
            start_time => $start,
            end_time => $end,
            description => norm($desc),
        };

        # Extra info
        my $title_org = $prog->findvalue( 'origtitle' );
        my $subtitle  = $prog->findvalue( 'eptitle' );
        my $country   = $prog->findvalue( 'country' );
        my $year      = $prog->findvalue( 'year' );

        my $episode   = $prog->findvalue( 'episode' );
        my $episodeco = $prog->findvalue( 'episodecount' );

        if(my($season, $episode2) = ($ce->{description} =~ /Staffel\s+(\d+),\s+Episode\s+(\d+)/i)) {
            $ce->{episode} = sprintf( "%d . %d .", $season-1, $episode2-1 ) if $season ne "" and $season > 0;
        } elsif(my($season2, $episode3) = ($ce->{description} =~ /(\d+)\s*\s+Staffel\s*\s+Episode\s+(\d+)/i)) {
            $ce->{episode} = sprintf( "%d . %d .", $season2-1, $episode3-1 ) if $season2 ne "" and $season2 > 0;
        } elsif(my($season3, $episode4) = ($ce->{description} =~ /Staffel\s+(\d+),\s+(\d+)\s*/i)) {
            $ce->{episode} = sprintf( "%d . %d .", $season3-1, $episode4-1 ) if $season3 ne "" and $season3 > 0;
        } elsif($episode and $episode ne "") {
            if($episodeco ne "") {
                $ce->{episode} = sprintf( " . %d/%d .", $episode-1, $episodeco );
            } else {
                $ce->{episode} = sprintf( " . %d .", $episode-1 );
            }
        }

        if($year =~ /(\d\d\d\d)/) {
            $ce->{production_date} = "$1-01-01";
        }

        my $genre = $prog->findvalue( 'category[@type="genre"]' );
        my $type  = $prog->findvalue( 'programme_type' );

        my ($program_type, $category ) = $ds->LookupCat( "SonyDE_genre", $genre );
		AddCategory( $ce, $program_type, $category );

        my ($program_type2, $category2 ) = $ds->LookupCat( "SonyDE_type", $type );
		AddCategory( $ce, $program_type2, $category2 );

        my ($country2 ) = $ds->LookupCountry( "SonyDE", $country );
		AddCountry( $ce, $country2 );

        # add them
        ParseCredits( $ce, 'actors',     $prog, 'person[@type="cast"]/name' );
        ParseCredits( $ce, 'directors',  $prog, 'person[@type="director"]/name' );

        $ce->{subtitle} = norm($subtitle) if defined $subtitle and $subtitle ne "";
        $ce->{original_title} = norm($title_org) if defined $title_org and norm($title_org) ne norm($title) and norm($title_org) ne "";

        progress( "SonyDE: $chd->{xmltvid}: $start - $title" );
        $dsh->AddProgramme( $ce );
    }
  #  $column = undef;

  $dsh->EndBatch( 1 );

  return 1;
}

# call with sce, target field, sendung element, xpath expression
# e.g. ParseCredits( \%sce, 'actors', $sc, './programm//besetzung/darsteller' );
# e.g. ParseCredits( \%sce, 'writers', $sc, './programm//stab/person[funktion=buch]' );
sub ParseCredits
{
  my( $ce, $field, $root, $xpath) = @_;

  my @people;
  my $nodes = $root->findnodes( $xpath );
  foreach my $node ($nodes->get_nodelist) {
    my $person = $node->to_literal();

    if( norm($person) ne '' ) {
      push( @people, split( '&', $person ) );
    }
  }

  foreach (@people) {
    $_ = norm( $_ );
  }

  AddCredits( $ce, $field, @people );
}


sub AddCredits
{
  my( $ce, $field, @people) = @_;

  if( scalar( @people ) > 0 ) {
    if( defined( $ce->{$field} ) ) {
      $ce->{$field} = join( ';', $ce->{$field}, @people );
    } else {
      $ce->{$field} = join( ';', @people );
    }
  }
}

1;