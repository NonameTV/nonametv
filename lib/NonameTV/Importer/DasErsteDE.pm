package NonameTV::Importer::DasErsteDE;

=pod

This importer imports data from DasErste's press site. The data is fetched
as one xml-file per day and channel.

Features:

Episode-info parsed from description.

This mode of access is documented at https://presse.daserste.de/pages/programm/xmldownload.aspx
and https://presse.daserste.de/pages/senderguide/xmldownload.aspx explains the (new?) optional
parameter to choose one of the 18 available channels.

=cut

use strict;
use utf8;
use warnings;

use DateTime;
use Encode qw/from_to/;
use Switch;
use XML::LibXML;

use NonameTV qw/AddCategory norm ParseXml/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/d p w f/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    defined( $self->{Username} ) or die "You must specify Username";
    defined( $self->{Password} ) or die "You must specify Password";

    # how many days are available every days of the week?
    my $DaysOnSite = 5*7 + 4;

    if ($self->{MaxDays} == 32) {
      # default to all data
      $self->{MaxDays} = $DaysOnSite;
    } elsif ($self->{MaxDays} > $DaysOnSite) {
      w ($self->{Type} . ": limiting MaxDays to availible data");
      $self->{MaxDays} = $DaysOnSite;
    }

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
    $self->{datastorehelper} = $dsh;

#    $self->{datastore}->{SILENCE_DUPLICATE_SKIP} = 1;

    $self->{SkipYesterday} = 1; # there is no data for the past

    $self->{datastore}->{augment} = 1;

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

  my $senderid = $chd->{grabber_info};
  if( !defined( $senderid )  || ( $senderid eq '' )){
    # set sender id to the implicit default
    $senderid = 1;
  }

  my $u = URI->new('https://presse.daserste.de/export/programmablauf.aspx');
  $u->query_form ({
    user => $self->{Username},
    pass => $self->{Password},
    datum => $dt->dmy ("."),
    zeitraum => "tag",
    sender => $senderid,
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
  $$cref =~ s|<Zusatztext>([^<]*)</Zusatztext>|<Zusatztext xml:space="preserve">$1</Zusatztext>|g;
  $$cref =~ s|&#13;&#10;|\n|g;

  # header says utf-8 but it's really windows-1252 in entities
  $$cref =~ s|&#(\d+);|chr($1)|eg;
  from_to ($$cref, "windows-1252", "utf-8");

  # remove date of export
  $$cref =~ s| - Programmablauf Stand \d+.\d+.\d{4} \d{2}:\d{2}:\d{2}||;
  $$cref =~ s|Programmablauf Stand=".*"|Programmablauf|;

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
    f( "$batch_id: Failed to parse." );
    return 0;
  }

  # Check that we have downloaded data for the correct day.
  my $daytext = $doc->findvalue( '//@Datum' );
  my( $day ) = ($daytext =~ /^(\d{2})/);

  if( not defined( $day ) )
  {
    f( "$batch_id: Failed to find date in page ($daytext)" );
    return 0;
  }

  my( $dateday ) = ($date =~ /(\d\d)$/);

  if( $day != $dateday )
  {
    f( "$batch_id: Wrong day: $daytext" );
    return 0;
  }
        
  # The data really looks like this...
  my $ns = $doc->find( "//Sendung" );
  if( $ns->size() == 0 )
  {
    w( "$batch_id: No programmes found" );
    return 0;
  }

  $dsh->StartDate( $date, "05:30" );
  
  my $programs = 0;

  foreach my $pgm ($ns->get_nodelist)
  {
    my $startTime = $pgm->findvalue( 'Sendebeginn' );
    my $endTime = $pgm->findvalue( 'Sendeende' );
    my $title = $pgm->findvalue( 'Sendetitel' );
    $title =~ s| \(\d+/\d+\)$||g;
    $title =~ s| \(\d+\)$||g;
    $title =~ s/ \(WH(?: von \w{2}|)\)$//g;
    # clean up for HR
    $title =~ s/\s+Kinemathek-Nacht:.*$//g;

    my $ce = {
      start_time  => $startTime,
      # FIXME using end_time leaves gaps between programmes
      # end_time    => $endTime,
      title       => $title,
    };

    my $desc  = $pgm->findvalue( 'Pressetext' );
    if (!$desc) {
      $desc = $pgm->findvalue( 'Zusatztext' );
    }
    # cleanup some characters
    # ellipsis
    $desc =~ s|…|...|g;
    # quotation mark
    $desc =~ s|„|\"|g;
    # turn space before elipsis into non-breaking space (german usage)
    $desc =~ s| \.\.\.$| ...|;
    # strip running time
    $desc =~ s|^Laufzeit:\s+ca.\s+\d+ Min[^<]*\n\n||;
    $desc =~ s|^Laufzeit:\s+\d+ Min[^<]*\n\n||;
    # keep the short description only
    my @descs = split (/\n\Q*\E\n/, $desc);
    $desc = $descs[0];
    if ($desc) {
      if ($desc =~ m|^\(Vom \d+\.\d+\.\d{4}\)$|) {
        my ($psd) = ($desc =~ m|^Vom (\S+)$|);
        # is a repeat from $previously shown date
        $desc = undef;
      }
    }
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
    }else{
      # no episode number from the xml elements, see if there is something appended to the title
      my $episodeNumTitle = $pgm->findvalue( 'Sendetitel' );
      ($episode, $episodeCount)=($episodeNumTitle =~ m/\s+\((\d+)(?:\/(\d+)|)\)$/);
      if ($episode) {
        if ($episodeCount) {
          $ce->{episode} = ". " . ($episode-1) . "/" . $episodeCount . " .";
        } else {
          $ce->{episode} = ". " . ($episode-1) . " .";
        }
      }
    }


    my $subtitle1 = $pgm->findvalue( 'Untertitel1' );
    $subtitle1 = $self->parse_subtitle ($ce, $subtitle1);
    $subtitle1 = $self->parse_subtitle ($ce, $subtitle1);
    $subtitle1 = $self->parse_subtitle ($ce, $subtitle1);
    my $subtitle2 = $pgm->findvalue( 'Untertitel2' );
    $subtitle2 = $self->parse_subtitle ($ce, $subtitle2);
    $subtitle2 = $self->parse_subtitle ($ce, $subtitle2);
    $subtitle2 = $self->parse_subtitle ($ce, $subtitle2);

    # take unparsed subtitle
    # TODO else add them to description
    my $subtitle;
    if ($subtitle1) {
      if ($subtitle2) {
        $subtitle = $subtitle1 . $subtitle2;
        $subtitle = $self->parse_subtitle ($ce, $subtitle);
        $subtitle = $self->parse_subtitle ($ce, $subtitle);
        $subtitle = $self->parse_subtitle ($ce, $subtitle);
      } else {
        $subtitle = $subtitle1;
      }
    } elsif ($subtitle2) {
      $subtitle = $subtitle2;
    }
    if ($subtitle) {
      $ce->{subtitle} = $subtitle;
    }

    # strip episode number and title from description
    if( defined( $episode ) && defined( $subtitle ) && defined( $ce->{description} ) ) {
      my $candidate = "$episode. $subtitle";
      # strip part number from multipart episodes
      $candidate =~ s|\s*\(.*?\)$||;
      # strip initial line if it begins with the episode number and title
      $ce->{description} =~ s|^$candidate.*?\n||s;
    }

    my $url = $pgm->findvalue( 'Internetlink' );
    if ($url) {
      $ce->{url} = $url;
    }

    my $attributes = $pgm->findnodes ('Sendeattribute/Sendeattribut');
    foreach my $attribute ($attributes->get_nodelist()) {
      my $str = $attribute->string_value();
      switch ($str) {
        case "Audiodeskription" { ; } # audio for the visually impaired
        case "Breitbild 16:9"   { $ce->{aspect} = "16:9" }
        case "Dolby Digital"    { $ce->{stereo} = "dolby digital" }
        case "Dolby Surround"   { $ce->{stereo} = "surround" }
        case "FSK 6"            { $ce->{rating} = "FSK 6"; }  # FIXME should be system=FSK rating=6
        case "FSK 12"           { $ce->{rating} = "FSK 12"; } # should be system=FSK rating=12
        case "FSK 16"           { $ce->{rating} = "FSK 16"; } # should be system=FSK rating=16
        case "FSK 18"           { $ce->{rating} = "FSK 18"; } # should be system=FSK rating=18
        case "HD"               { $ce->{quality} = "HDTV"; }
        case "Kinderprogramm"   { ; } # to many false positives
        case "Schwarzweiß"      { ; } # colour=no
        case "Stereo"           { $ce->{stereo} = "stereo" }
        case "Videotext"        { ; } # subtitles=teletext
        case "Zweikanalton"     { $ce->{stereo} = "bilingual" }
        else { w ("DasErsteDE: unknown attribute: " . $str) }
      }
    }

    my $actors = $pgm->findnodes ('.//Rolle');
    my @actors_array;
    foreach my $actor($actors->get_nodelist()) {
      # TODO handle special roles like "Moderator" and "Kontakt", see br-alpha
      push (@actors_array, $actor->string_value());
    }
    if (@actors_array) {
      $ce->{actors} = join (", ", @actors_array);
    }

    my $directors = $pgm->findnodes ('.//Regie');
    my @directors_array;
    # fixup one entry containing two directors joined by " und "
    foreach my $director ($directors->get_nodelist()) {
      my @fixup = split (" und ", $director->string_value());
      @directors_array = (@directors_array, @fixup);
    }
    my @directors_array_2nd;
    # fixup one entry containing two directors joined by " / "
    foreach my $director (@directors_array){
      my @fixup = split (/\s*\/\s*/, $director);
      @directors_array_2nd = (@directors_array_2nd, @fixup);
    }
    if (@directors_array_2nd) {
      $ce->{directors} = join (", ", @directors_array_2nd);
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

#  this breaks subtitles split over untertitel1/2 with the space exactly on the merge point
#  $subtitle = norm ($subtitle);

  # strip Themenwoche
  if( $subtitle =~ m/(?:\s*-\s*|)ARD-Themenwoche \".*\"$/ ){
    $subtitle =~ s/(?:\s*-\s*|)ARD-Themenwoche \".*\"$//;
  }

  # match program type, production county, production year
  if ($subtitle =~ m|^\S+ \S+ \d{4}$|) {
    my ($program_type, $production_countries, $production_year) = ($subtitle =~ m|^(\S+) (\S+) (\d{4})$|);
    $sce->{production_date} = $production_year . "-01-01";
    my ( $type, $categ ) = $self->{datastore}->LookupCat( "DasErste_type", $program_type );
    AddCategory( $sce, $type, $categ );
    $subtitle = undef;
  } elsif ($subtitle =~ m|^Moderation: |) {
    my ($presenters) = ($subtitle =~ m|^Moderation: (.*)$|);
    # split ", " and " und "
    my (@presenter) = split (", ", join (", ", split (" und ", $presenters)));
    if ($sce->{presenters}) {
      $sce->{presenters} = join (", ", $sce->{presenters}, @presenter);
    } else {
      $sce->{presenters} = join (@presenter);
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
  } elsif ($subtitle =~ m|^\S+teili\S+ \S+ \S+ \d{4}$|) {
    # 14-teiliger Spielfilm Deutschland 2000
    # vierteiliger Spielfilm Deutschland 2000
    my ($program_type, $production_countries, $production_year) = ($subtitle =~ m|^\S+ (\S+) (\S+) (\d{4})$|);
    $sce->{production_date} = $production_year . "-01-01";
    my ( $type, $categ ) = $self->{datastore}->LookupCat( "DasErste_type", $program_type );
    AddCategory( $sce, $type, $categ );
    $subtitle = undef;
  } elsif ($subtitle =~ m/\s*-*\s*\S+film[,]{0,1} .*? \d{4}\s*/) {
    # Spielfilm USA 2009 (Stolen Lives)
    # Spielfilm Irland/USA 2009 (ONDINE)
    # Spielfilm Großbritannien / USA / Italien 2001
    # Fernsehfilm Österreich / Deutschland 2005
    # Kinderspielfilm Argentinien / Spanien 2008 (El Ratón)
    # (Myrin) Spielfilm, Island 2006
    my ($program_type, $production_countries, $production_year) = ($subtitle =~ m/\s*-*\s*(\S+film)[,]{0,1} (.*?) (\d{4})\s*/);
    $sce->{production_date} = $production_year . "-01-01";
    my ( $type, $categ ) = $self->{datastore}->LookupCat( "DasErste_type", $program_type );
    AddCategory( $sce, $type, $categ );
    $subtitle =~ s!\s*-*\s*\S+film[,]{0,1} (.*?) \d{4}\s*!!;
  } elsif ($subtitle =~ m|^\S+teili\S+ \S+ und \S+erie \S+ \d{4}$|) {
    # 13-teilige Kinder- und Familienserie Deutschland 2009
    my ($program_type, $production_countries, $production_year) = ($subtitle =~ m|^\S+ (\S+ \S+ \S+) (\S+) (\d{4})$|);
    if( $production_year > 1800) {
      # no typos like 201 instead of 2010
      $sce->{production_date} = $production_year . "-01-01";
    }
    my ( $type, $categ ) = $self->{datastore}->LookupCat( "DasErste_type", $program_type );
    AddCategory( $sce, $type, $categ );
    $subtitle = undef;
  } elsif ($subtitle =~ m|^\d+-teilige \S+erie \S+$|) {
    # 52-teilige Zeichentrickserie Frankreich/
    my ($program_type, $production_countries) = ($subtitle =~ m|^\d+-teilige (\S+) (\S+)/$|);
    my ( $type, $categ ) = $self->{datastore}->LookupCat( "DasErste_type", $program_type );
    AddCategory( $sce, $type, $categ );
    $subtitle = undef;
  } elsif ($subtitle =~ m/^(?:Ein |)Film von [A-Z]\S+ [A-Z]\S+$/) {
    my ($producer) = ($subtitle =~ m/^(?:Ein |)Film von (\S+ \S+)$/);
    if ($sce->{producers}) {
      $sce->{producers} = join (", ", $sce->{producers}, $producer);
    } else {
      $sce->{producers} = $producer;
    }
    $subtitle = undef;
  } elsif ($subtitle =~ m/^(?:Ein |)Film von [A-Z]\S+ von [A-Z]\S+$/) {
    my ($producer) = ($subtitle =~ m/^(?:Ein |)Film von (\S+ von \S+)$/);
    if ($sce->{producers}) {
      $sce->{producers} = join (", ", $sce->{producers}, $producer);
    } else {
      $sce->{producers} = $producer;
    }
    $subtitle = undef;
  } elsif ($subtitle =~ m/^(?:Ein |)Film von [A-Z]\S+ [A-Z]\. [A-Z]\S+$/) {
    my ($producer) = ($subtitle =~ m/^(?:Ein |)Film von (\S+ \S+ \S+)$/);
    if ($sce->{producers}) {
      $sce->{producers} = join (", ", $sce->{producers}, $producer);
    } else {
      $sce->{producers} = $producer;
    }
    $subtitle = undef;
  } elsif ($subtitle =~ m/^(?:Ein |)Film von [A-Z]\S+ [A-Z]\S+ und [A-Z]\S+ [A-Z]\S+$/) {
    my ($producer1, $producer2) = ($subtitle =~ m/^(?:Ein |)Film von (\S+ \S+) und (\S+ \S+)$/);
    if ($sce->{producers}) {
      $sce->{producers} = join (", ", $sce->{producers}, $producer1, $producer2);
    } else {
      $sce->{producers} = join (", ", $producer1, $producer2);
    }
    $subtitle = undef;
  } elsif ($subtitle =~ m/^(?:Ein |)Film von [A-Z]\S+ [A-Z]\S+, [A-Z]\S+ [A-Z]\S+$/) {
    my ($producer1, $producer2) = ($subtitle =~ m/^(?:Ein |)Film von (\S+ \S+), (\S+ \S+)$/);
    if ($sce->{producers}) {
      $sce->{producers} = join (", ", $sce->{producers}, $producer1, $producer2);
    } else {
      $sce->{producers} = join (", ", $producer1, $producer2);
    }
    $subtitle = undef;
  } elsif ($subtitle =~ m!^\((?:BR|DFF|HR|MDR|NDR|SR|SWR|RBB|WDR|SWR/HR)\)!) {
    # begins with original station (no dollar at the end)
    $subtitle = undef;
  } elsif ($subtitle =~ m|^\(Vom \d+\.\d+\.\d{4}\)$|) {
    my ($psd) = ($subtitle =~ m|^Vom (\S+)$|);
    # is a repeat from $previously shown date
    $subtitle = undef;
  } elsif ($subtitle =~ m|^\(Pressetext siehe .*\)$|) {
    my ($psd) = ($subtitle =~ m|^\(Pressetext siehe (.*)\)$|);
    # is a repeat from $previously shown date
    $subtitle = undef;
  } elsif ($subtitle =~ m|^\(Wiederholung vo[nm] .*\)$|) {
    my ($psd) = ($subtitle =~ m|^\(Wiederholung vo[nm] (.*)\)$|);
    # is a repeat from $previously shown day or time
    $subtitle = undef;
  } elsif ($subtitle =~ m|^\(.*\)$|) {
    my ($title_orig) = ($subtitle =~ m|^\((.*)\)$|);
    # original title
    $sce->{original_title} = norm($title_orig);
    $subtitle = undef;
  } elsif ($subtitle =~ m|^Reporter: \S+ \S+$|) {
    my ($presenter) = ($subtitle =~ m|^Reporter: (\S+ \S+)$|);
    if ($sce->{presenters}) {
      $sce->{presenters} = join (", ", $sce->{presenters}, $presenter);
    } else {
      $sce->{presenters} = $presenter;
    }
    $subtitle = undef;
  } elsif ($subtitle =~ m|^\S+teiliger Film von [A-Z]\S+ [A-Z]\S+$|) {
    my ($producer) = ($subtitle =~ m|^\S+ Film von (\S+ \S+)$|);
    if ($sce->{producers}) {
      $sce->{producers} = join (", ", $sce->{producers}, $producer);
    } else {
      $sce->{producers} = $producer;
    }
    $subtitle = undef;
  } elsif ($subtitle =~ m|^\S+teiliger Film von [A-Z]\S+ [A-Z]\S+ und [A-Z]\S+ [A-Z]\S+$|) {
    my ($producer1, $producer2) = ($subtitle =~ m|^\S+ Film von (\S+ \S+) und (\S+ \S+)$|);
    if ($sce->{producers}) {
      $sce->{producers} = join (", ", $sce->{producers}, $producer1, $producer2);
    } else {
      $sce->{producers} = join (", ", $producer1, $producer2);
    }
    $subtitle = undef;
  } elsif (($subtitle =~ m|^mit den Wildgänsen$|) && ($sce->{title} =~ m|^Die wunderbare Reise des kleinen Nils Holgersson$|)) {
    $subtitle = undef;
    $sce->{title} = $sce->{title} . " mit den Wildgänsen";
  } elsif (($subtitle =~ m|^\d+\. |) && ($sce->{title} =~ m|^Die wunderbare Reise des kleinen Nils Holgersson mit den Wildgänsen$|)) {
    $subtitle =~ s|^\d+\. ||;
  } elsif ($subtitle =~ m|^\S+how mit [A-Z]\S+ [A-Z]\S+$|) {
    my ($genre, $presenter) = ($subtitle =~ m|^(\S+how) mit (\S+ \S+)$|);
    my ( $type, $categ ) = $self->{datastore}->LookupCat( "DasErste_type", $genre);
    AddCategory( $sce, $type, $categ );
    if ($sce->{presenters}) {
      $sce->{presenters} = join (", ", $sce->{presenters}, $presenter);
    } else {
      $sce->{presenters} = $presenter;
    }
    $subtitle = undef;
  } elsif ($subtitle =~ m|\bDeutsche Erstausstrahlung\b| ) {
    # Intergalaktische Bruchlandung Folge 1246 Familienserie Deutschland, 2014 Audiodeskription Deutsche Erstausstrahlung
    $subtitle =~ s|\s*Deutsche Erstausstrahlung\s*||;
  } elsif ($subtitle =~ m|\bAudiodeskription\b| ) {
    # Intergalaktische Bruchlandung Folge 1246 Familienserie Deutschland, 2014 Audiodeskription Deutsche Erstausstrahlung
    $subtitle =~ s|\s*Audiodeskription\s*||;
  } elsif ($subtitle =~ m|\b\S+erie \S+,? \d{4}\b| ) {
    # Intergalaktische Bruchlandung Folge 1246 Familienserie Deutschland, 2014 Audiodeskription Deutsche Erstausstrahlung
    my( $genre )=( $subtitle =~ s|\s*(\S+erie) \S+,? \d{4}\s*|| );
    my ( $type, $categ )= $self->{datastore}->LookupCat( "DasErste_type", $genre );
    AddCategory( $sce, $type, $categ );
  } elsif ($subtitle =~ m|\bFolge \d+\b| ) {
    # Intergalaktische Bruchlandung Folge 1246 Familienserie Deutschland, 2014 Audiodeskription Deutsche Erstausstrahlung
    my( $episode )=( $subtitle =~ s|\s*Folge (\d+)\s*|| );

    if( !defined( $sce->{episode} ) ){
      $sce->{episode} = ". " . ($episode-1) . " .";
    }
  } else {
    d ("unhandled subtitle: $subtitle");
  }

  return $subtitle;
}

1;
