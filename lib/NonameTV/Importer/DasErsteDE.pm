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
use NonameTV::Log qw/p progress w f/;

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

    $self->{SkipYesterday} =1; # there is no data for the past

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
    $subtitle1 = $self->parse_subtitle ($ce, $subtitle1);
    my $subtitle2 = $pgm->findvalue( 'Untertitel2' );
    $subtitle2 = $self->parse_subtitle ($ce, $subtitle2);

    # take unparsed subtitle
    # TODO else add them to description
    my $subtitle;
    if ($subtitle1) {
      if ($subtitle2) {
        $subtitle = $subtitle1 . " " . $subtitle2;
      } else {
        $subtitle = $subtitle1;
      }
    } elsif ($subtitle2) {
      $subtitle = $subtitle2;
    }
    if ($subtitle) {
      $ce->{subtitle} = $subtitle;
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

    my $writers= $pgm->findnodes ('.//Buch');
    my @writers_array;
    foreach my $writer ($writers->get_nodelist()) {
      my @fixup = split (" und ", $writers->string_value());
      @writers_array = (@writers_array, @fixup);
    }
    if (@writers_array) {
      $ce->{writers} = join (", ", @writers_array);
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

sub parse_subtitle
{
  my $self = shift;
  my $sce = shift;
  my $subtitle = shift;

  if (!$subtitle) {
    return undef;
  }

  # match program type, production county, production year
  if ($subtitle =~ m|^\S+ \S+ \d{4}$|) {
    my ($program_type, $production_countries, $production_year) = ($subtitle =~ m|^(\S+) (\S+) (\d{4})$|);
    $sce->{production_date} = $production_year . "-01-01";
    my ( $type, $categ ) = $self->{datastore}->LookupCat( "DasErste_type", $program_type );
    AddCategory( $sce, $type, $categ );
    $subtitle = undef;
  } elsif ($subtitle =~ m|^Moderation: \S+ \S+$|) {
    my ($presenter) = ($subtitle =~ m|^Moderation: (\S+ \S+)$|);
    if ($sce->{presenters}) {
      $sce->{presenters} = join (", ", $sce->{presenters}, $presenter);
    } else {
      $sce->{presenters} = $presenter;
    }
    $subtitle = undef;
  } elsif ($subtitle =~ m|^mit [A-Z]\S+ [A-Z]\S+$|) {
    # match "mit First Lastname" but not "mit den Wildgaensen"
    my ($presenter) = ($subtitle =~ m|^mit (\S+ \S+)$|);
    if ($sce->{presenters}) {
      $sce->{presenters} = join (", ", $sce->{presenters}, $presenter);
    } else {
      $sce->{presenters} = $presenter;
    }
    $subtitle = undef;
  } elsif ($subtitle =~ m|^mit [A-Z]\S+ [A-Z]\S+, [A-Z]\S+ [A-Z]\S+ und [A-Z]\S+ [A-Z]\S+$|) {
    # match "mit First Lastname" but not "mit den Wildgaensen"
    my ($presenter) = ($subtitle =~ m|^mit (\S+ \S+), (\S+ \S+) und (\S+ \S+)$|);
    if ($sce->{presenters}) {
      $sce->{presenters} = join (", ", $sce->{presenters}, $presenter);
    } else {
      $sce->{presenters} = $presenter;
    }
    $subtitle = undef;
  } elsif ($subtitle =~ m|^Moderation: \S+ \S+ und \S+ \S+$|) {
    my ($presenter1, $presenter2) = ($subtitle =~ m|^Moderation: (\S+ \S+) und (\S+ \S+)$|);
    if ($sce->{presenters}) {
      $sce->{presenters} = join (", ", $sce->{presenters}, $presenter1, $presenter2);
    } else {
      $sce->{presenters} = join (", ", $presenter1, $presenter2);
    }
    $subtitle = undef;
  } elsif ($subtitle =~ m|^\S+teili\S+ \S+ \S+ \d{4}$|) {
    # 14-teiliger Spielfilm Deutschland 2000
    # vierteiliger Spielfilm Deutschland 2000
    my ($program_type, $production_countries, $production_year) = ($subtitle =~ m|^\S+ (\S+) (\S+) (\d{4})$|);
    $sce->{production_date} = $production_year . "-01-01";
    my ( $type, $categ ) = $self->{datastore}->LookupCat( "DasErste_type", $program_type );
    AddCategory( $sce, $type, $categ );
    $subtitle = undef;
  } elsif ($subtitle =~ m|^\S+teili\S+ \S+ und \S+erie \S+ \d{4}$|) {
    # 13-teilige Kinder- und Familienserie Deutschland 2009
    my ($program_type, $production_countries, $production_year) = ($subtitle =~ m|^\S+ (\S+ \S+ \S+) (\S+) (\d{4})$|);
    $sce->{production_date} = $production_year . "-01-01";
    my ( $type, $categ ) = $self->{datastore}->LookupCat( "DasErste_type", $program_type );
    AddCategory( $sce, $type, $categ );
    $subtitle = undef;
  } elsif ($subtitle =~ m|^Film von [A-Z]\S+ [A-Z]\S+$|) {
    my ($producer) = ($subtitle =~ m|^Film von (\S+ \S+)$|);
    if ($sce->{producers}) {
      $sce->{producers} = join (", ", $sce->{producers}, $producer);
    } else {
      $sce->{producers} = $producer;
    }
    $subtitle = undef;
  } elsif ($subtitle =~ m|^Film von [A-Z]\S+ [A-Z]\S+ und [A-Z]\S+ [A-Z]\S+$|) {
    my ($producer1, $producer2) = ($subtitle =~ m|^Film von (\S+ \S+) und (\S+ \S+)$|);
    if ($sce->{producers}) {
      $sce->{producers} = join (", ", $sce->{producers}, $producer1, $producer2);
    } else {
      $sce->{producers} = join (", ", $producer1, $producer2);
    }
    $subtitle = undef;
  } elsif ($subtitle =~ m|^\(Vom \d+\.\d+\.\d{4}\)$|) {
    my ($psd) = ($subtitle =~ m|^Vom (\S+)$|);
    # is a repeat from $previously shown date
    $subtitle = undef;
  } elsif ($subtitle =~ m|^\(.*\)$|) {
    my ($title_orig) = ($subtitle =~ m|^\((.*)\)$|);
    # original title
    $subtitle = undef;
  } elsif ($subtitle =~ m|^Reporter: \S+ \S+$|) {
    my ($presenter) = ($subtitle =~ m|^Reporter: (\S+ \S+)$|);
    if ($sce->{presenters}) {
      $sce->{presenters} = join (", ", $sce->{presenters}, $presenter);
    } else {
      $sce->{presenters} = $presenter;
    }
    $subtitle = undef;
  } else {
    progress ("unhandled subtitle: $subtitle");
  }

  return $subtitle;
}

1;
