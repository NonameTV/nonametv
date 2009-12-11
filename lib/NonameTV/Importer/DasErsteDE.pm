package NonameTV::Importer::DasErsteDE;

=pod

This importer imports data from SvT's press site. The data is fetched
as one html-file per day and channel.

Features:

Episode-info parsed from description.

=cut

use strict;
use utf8;
use warnings;

use DateTime;
use Switch;
use XML::LibXML;

use NonameTV qw/AddCategory MyGet norm ParseXml/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/p w f/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{Username} ) or die "You must specify Username";
    defined( $self->{Password} ) or die "You must specify Password";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

#    $self->{datastore}->{SILENCE_DUPLICATE_SKIP} = 1;

    return $self;
}

sub Object2Url {
  my $self = shift;
  my( $objectname, $chd ) = @_;

  # https://presse.daserste.de/export/programmablauf.aspx?user=xml&pass=lmx&datum=31.07.2009&zeitraum=tag&pressetext=true

  my( $date ) = ($objectname =~ /_(.*)/);

  my( $year, $month, $day ) = split( '-', $date );
  my $dt = DateTime->new( 
                          year  => $year,
                          month => $month,
                          day   => $day 
                          );

  my $u = URI->new('https://presse.daserste.de/export/programmablauf.aspx');
  $u->query_form ({
    user => $self->{Username},
    pass => $self->{Password},
    datum => $dt->dmy ("."),
    zeitraum => "tag",
    pressetext => "true"});

  return( $u->as_string(), undef );
}

sub FilterContent {
  my $self = shift;
  my( $cref, $chd ) = @_;

  if ($$cref =~ m/^\r\n\r\n/ ) {
    # data for yesterday is not availible
    return (undef, "Webservice returned failure instead of content");
  }
  if ($$cref =~ m|<title>Unbekannte Seite</title>| ) {
    # data for yesterday is not availible
    return (undef, "Webservice returned failure instead of content");
  }

  $$cref =~ s|<Pressetext>([^<]*)</Pressetext>|<Pressetext xml:space="preserve">$1</Pressetext>|g;
  $$cref =~ s|&#13;&#10;|\n|g;

  my $doc = ParseXml( $cref );
 
  if( not defined $doc ) {
    return (undef, "ParseXml failed" );
  } 

  my $str = $doc->toString(1);

  return (\$str, undef);
}

sub ContentExtension {
  return 'xml';
}

sub FilteredExtension {
  return 'xml';
}

sub ImportContent {
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
#  $ds->{SILENCE_END_START_OVERLAP}=1;
  my $dsh = $self->{datastorehelper};
  $self->{currxmltvid} = $chd->{xmltvid};

  my( $date ) = ($batch_id =~ /_(.*)$/);

  {
    my( $year, $month, $day ) = split("-", $date);
    $self->{currdate} = DateTime->new( year => $year,
                                       month => $month, 
                                       day => $day );
  }

  my $doc = ParseXml( $cref );
  
  if( not defined( $doc ) )
  {
    error( "$batch_id: Failed to parse." );
    return 0;
  }

  # Check that we have downloaded data for the correct day.
  my $daytext = $doc->findvalue( '//@Datum' );
  my( $day ) = ($daytext =~ /^(\d{2})/);

  if( not defined( $day ) )
  {
    error( "$batch_id: Failed to find date in page ($daytext)" );
    return 0;
  }

  my( $dateday ) = ($date =~ /(\d\d)$/);

  if( $day != $dateday )
  {
    error( "$batch_id: Wrong day: $daytext" );
    return 0;
  }
        
  # The data really looks like this...
  my $ns = $doc->find( "//Sendung" );
  if( $ns->size() == 0 )
  {
    error( "$batch_id: No data found" );
    return 0;
  }

  $dsh->StartDate( $date, "05:30" );
  
  my $programs = 0;

  foreach my $pgm ($ns->get_nodelist)
  {
    my $startTime = $pgm->findvalue( 'Sendebeginn' );
    my $endTime = $pgm->findvalue( 'Sendeende' );
    my $title = $pgm->findvalue( 'Sendetitel' );
    $title =~ s| \(\d+\)$||g;

    my $ce = {
      start_time  => $startTime,
      end_time    => $endTime,
      title       => $title,
    };

    my $desc  = $pgm->findvalue( 'Pressetext' );
    # strip running time
    $desc =~ s|^Laufzeit:\s+\d+ Min[^<]*\n\n||;
    $desc =~ s||\"|g;
    # replace 
    $desc =~ s||...|g;
    # keep the short description only
    my @descs = split (/\n\Q*\E\n/, $desc);
    $desc = $descs[0];
    if ($desc) {
      $ce->{description} = $desc;
    }

    my $episode = $pgm->findvalue( 'FolgenNummer' );
    my $episodeCount = $pgm->findvalue( 'FolgenGesamt' );
    if ($episode) {
      if ($episodeCount) {
        $ce->{episode} = ". " . ($episode-1) . "/" . $episodeCount . " .";
      } else {
        $ce->{episode} = ". " . ($episode-1) . " .";
      }
    }

    my $subtitle1 = $pgm->findvalue( 'Untertitel1' );
    if ($subtitle1 =~ /^Spielfilm/ ) {
      $ce->{program_type} = "movie";
    }
    my $subtitle2 = $pgm->findvalue( 'Untertitel2' );
    if ($subtitle2 =~ /^Spielfilm/ ) {
      $ce->{program_type} = "movie";
    }

    my $url = $pgm->findvalue( 'Internetlink' );
    if ($url) {
      $ce->{url} = $url;
    }

    my $attributes = $pgm->findnodes ('//Sendeattribut');
    foreach my $attribute ($attributes->get_nodelist()) {
      my $str = $attribute->string_value();
      switch ($str) {
        case "Audiodeskription" { ; }
        case "Breitbild 16:9"   { $ce->{aspect} = "16:9" }
        case "Dolby Digital"    { $ce->{stereo} = "dolby digital" }
        case "Dolby Surround"   { $ce->{stereo} = "surround" }
        case "HD"               { ; }
        case "Kinderprogramm"   { ; } # to many false positives
        case "Schwarzweiß"      { ; }
        case "Stereo"           { $ce->{stereo} = "stereo" }
        case "Videotext"        { ; }
        else { w ("DasErsteDE: unknown attribute: " . $str) }
      }
    }

    my $actors = $pgm->findnodes ('.//Rolle');
    my @actors_array;
    foreach my $actor($actors->get_nodelist()) {
      push (@actors_array, $actor->string_value());
    }
    if (@actors_array) {
      $ce->{actors} = join (", ", @actors_array);
    }

    my $directors = $pgm->findnodes ('.//Regie');
    my @directors_array;
    foreach my $director ($directors->get_nodelist()) {
      my @fixup = split (" und ", $director->string_value());
      @directors_array = (@directors_array, @fixup);
    }
    if (@directors_array) {
      $ce->{directors} = join (", ", @directors_array);
    }

    my $production_date = $pgm->findvalue( 'Produktionsjahr' );
    if ($production_date) {
      $ce->{production_date} = $production_date."-01-01";
    }

    # TODO how do we handle programmes that are "inside" other programmes?
    my $DazwischenSendung = $pgm->findvalue( 'DazwischenSendung' );
    if ($DazwischenSendung ne "True") {
        $dsh->AddProgramme ($ce);
    }
  }
  return 1;
}

1;
