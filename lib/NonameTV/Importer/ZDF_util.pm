package NonameTV::Importer::ZDF_util;

use strict;
use warnings;

=pod

Importer for data in ZDF/3sat DTD.
One file per channel and week in xml-format.

=cut

use DateTime;
use XML::LibXML;
use Switch;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/progress w error/;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # set the version for version checking
    $VERSION     = 0.1;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/ParseData ParseWeek/;
}
our @EXPORT_OK;

sub ParseData
{
  my( $batch_id, $cref, $chd, $ds ) = @_;

  $ds->{SILENCE_END_START_OVERLAP}=1;
#  $ds->{SILENCE_DUPLICATE_SKIP}=1;
 
  my $doc;
  eval { $doc = ParseXml ($cref); };
  if( $@ ne "" )
  {
    error( "$batch_id: Failed to parse $@" );
    return 0;
  }
  
  # Find all "sendung"-entries.
  my $ns = $doc->find( '//sendung' );
  if( $ns->size() == 0 ){
    error( "$batch_id: No 'sendung' blocks found" );
    return 0;
  }
  progress("Found " . $ns->size() . " shows");
  
  foreach my $sc ($ns->get_nodelist)
  {
    my %sce = (
        channel_id  => $chd->{id},
    );

    # the id of the program
    my $id  = $sc->findvalue( './id ' );

    # the title
    my $title = $sc->findvalue( './programm//sendetitel' );
    if ($title) {
      $title = clean_sendetitel (\%sce, $title);
    }
    $sce{title} = norm($title);

    # the subtitle
    my $subtitle = $sc->findvalue( './programm//untertitel' );
    if ($subtitle) {
      $subtitle = clean_untertitel ($ds, \%sce, $subtitle);
    }

    # additional info to the title
    my @addinfo;
    my $zusatz = $sc->findnodes( './programm//zusatz' );
    foreach my $zs ($zusatz->get_nodelist) {
      push( @addinfo, $zs->string_value() );
    }

    # episode title
    my $episodetitle = $sc->findvalue( './programm//folgentitel' );

    # episode number
    my $episodenr = $sc->findvalue( './programm//folgenr' );

    # genre
    my $genre = $sc->findvalue( './programm//progart' );

    # category
    my $category = $sc->findvalue( './programm//kategorie' );

    # thember (similar to genre?? example - 'Reisen/Urlaub/Touristik')
    my $thember = $sc->findvalue( './programm//thember' );

    # info about the origin
    my $origin = $sc->findvalue( './programm//herkunftsender' );

    # short description
    my $shortdesc = $sc->findvalue( './programm//pressetext//kurz' );

    # long description
    my $longdesc = $sc->findvalue( './programm//pressetext//lang' );

    # whole description (ZDF/ZDFneo)
    my $wholedesc = $sc->findvalue( './programm//pressetext' );

    # moderation
    my $moderation = $sc->findvalue( './programm//moderation' );

    # there can be more than one broadcast times
    # so we have to find each 'ausstrahlung'
    # and insert the program for each of them
    my $ausstrahlung = $sc->find( './ausstrahlung' );

    foreach my $as ($ausstrahlung->get_nodelist)
    {
      # start time
      my $startzeit = $as->getElementsByTagName( 'startzeit' );
      my $starttime = create_dt( $startzeit );
      if( not defined $starttime ){
        error( "$batch_id: Invalid starttime for programme id $id - Skipping." );
        next;
      }

      # end time
      my $biszeit = $as->getElementsByTagName( 'biszeit' );
      my $endtime = create_dt_incomplete( $biszeit, $starttime );
      if( not defined $endtime ){
        error( "$batch_id: Invalid endtime for programme id $id - Skipping." );
        next;
      }

      # duration
      my $dauermin = $as->getElementsByTagName( 'dauermin' );

      # attributes
      my $attribute = $as->getElementsByTagName( 'attribute' );

      progress("$chd->{xmltvid}: $starttime - $title");

      my %ce = (
        start_time  => $starttime->ymd("-") . " " . $starttime->hms(":"),
        end_time    => $endtime->ymd("-") . " " . $endtime->hms(":"),
      );

      # append shared ce to this ce
      @ce{keys %sce} = values %sce;

      foreach my $attribut (split (" ", $attribute)) {
        switch ($attribut) {
          # DreiSat
          case /auddes/ {} # stereo = audio description
          case /dolby/  {$ce{stereo} = "dolby"}
          case /dolbyd/ {$ce{stereo} = "dolby digital"}
          case /f16zu9/ {$ce{aspect} = "16:9"}
          case /gbsp/   {} # sign language
          case /&gs;/   {} # sign language
          case /stereo/ {$ce{stereo} = "stereo"}
          case /sw/     {} # colour=no
          case /&sw;/   {} # colour=no
          case /videot/ {} # subtitles=teletext
          case /zweika/ {$ce{stereo} = "bilingual"}
          # ZDF
          case /&ad;/   {} # audio description
          case /&dd;/   {$ce{stereo} = "dolby digital"}
          case /&ds;/   {$ce{stereo} = "dolby"}
          case /&f16;/  {$ce{aspect} = "16:9"}
          case /&hd;/   {$ce{quality} = "HDTV"}
          case /&st;/   {$ce{stereo} = "stereo"}
          case /&vo;/   {} # video text
          # ZDFneo
          case /&zw;/   {$ce{stereo} = "bilingual"} 
          else          { w ("unhandled attribute: $attribut") } 
        }
      }

      # form the subtitle out of 'episodetitle' and ignore 'subtitle' completely
      # the information is usually duplicated in the longdesc anyway and of no
      # use for automated processing
      if ($episodetitle) {
        $episodetitle = clean_untertitel ($ds, \%ce, $episodetitle);
        if ($episodetitle) {
          $ce{subtitle} = norm($episodetitle);
        }
      }

      # form the description out of 'zusatz', 'shortdesc', 'longdesc', 'wholedesc'
      # 'origin'
      my $description;
      if( @addinfo ){
        foreach my $z ( @addinfo ){
          $description .= $z . "\n";
        }
      }
      $description .= norm($longdesc) || norm($shortdesc) || norm($wholedesc);
      if ($description) {
        $ce{description} = $description;
      }

      # episode number
      if( $episodenr ){
        $ce{episode} = ". " . ($episodenr-1) . " .";
      }

      my ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_genre", $genre );
      AddCategory( \%ce, $program_type, $categ );

      ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_category", $category );
      AddCategory( \%ce, $program_type, $categ );

      ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_thember", $thember );
      AddCategory( \%ce, $program_type, $categ );

      $ds->AddProgramme( \%ce );
    }

  }
  
  # Success
  return 1;
}

sub create_dt
{
  my $str = shift;

  my( $date, $time ) = split( 'T', $str );
  if( not defined $time )
  {
    return undef;
  }

  my( $year, $month, $day );

  if( $date =~ /(\d{4})\.(\d+)\.(\d+)/ ){
    ( $year, $month, $day ) = ( $date =~ /(\d{4})\.(\d+)\.(\d+)/ );
  } elsif( $date =~ /(\d+)\.(\d+)\.(\d{4})/ ){
    ( $day, $month, $year ) = ( $date =~ /(\d+)\.(\d+)\.(\d{4})/ );
  }

  my( $hour, $minute, $second ) = ( $time =~ /(\d{2}):(\d{2}):(\d{2})/ );
  
  if( $second > 59 ) {
    return undef;
  }

  my $dt;
  eval {
  $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => 'Europe/Berlin',
                          );
  };
  if ($@){
    error ("Could not convert time! Check for daylight saving time border.");
    return undef;
  };
  
  $dt->set_time_zone( "UTC" );
  
  return $dt;
}

sub create_dt_incomplete
{
  my $str = shift;
  my $start = shift;

  my $dt;

  if ($str =~ /\d{6}/) {
    my ($hour, $minute, $second) = ($str =~ /(\d{2})(\d{2})(\d{2})/ );
    $dt = $start->clone();
    $dt->set_hour ($hour);
    $dt->set_minute ($minute);
    $dt->set_second ($second);
  } else {
    $dt = create_dt ($str)
  }

  return $dt;
}

sub clean_sendetitel
{
  my $sce = shift;
  my $title = shift;

  # move episode numbers from title into episode
  if ($title =~ m| \(\d+/\d+\)$|) {
    my ($episodenr, $episodecnt) = ($title =~ m| \((\d+)/(\d+)\)$|);
    # if it's more than six episodes it's a series, otherwise it's likely a serial
    if ($episodecnt>6) {
      # we guess its a "normal" tv series, will get type series automatically
      $sce->{episode} = ". " . ($episodenr-1) . "/" . $episodecnt . " .";
    } else {
      # we guess its one programme thats broken in multiple parts or a serial
      # this will not get type series automatically
      $sce->{episode} = ". . " . ($episodenr-1) . "/" . $episodecnt;
    }
    $title =~ s| \(\d+/\d+\)$||;
  } elsif ($title =~ m| \(\d+\)$|) {
    my $episodenr = ($title =~ m| \((\d+)\)$|);
    $sce->{episode} = ". " . ($episodenr-1) . " .";
    $title =~ s| \(\d+\)$||;
  }

  return $title;
}

sub clean_untertitel
{
  my $ds = shift;
  my $sce = shift;
  my $subtitle = shift;

  if (!defined $subtitle) {
    return undef;
  }

  $subtitle = norm ($subtitle);

  # strip "repeat"
  if ($subtitle =~ m|^\(Wh\.\)$|) {
    return undef;
  }
  if ($subtitle =~ m|\s+\(Wh\..*\)$|) {
    $subtitle =~ s|\s+\(Wh\..*\)$||;
  }

  # strip "anschl. Wetter"
  if ($subtitle =~ m|^anschl\. 3sat-Wetter$|) {
    return undef;
  }

  # [format,] production countries [year of production]
  # Fernsehfilm, BRD 1980
  # Fernsehfilm, DDR 1973
  # Fernsehfilm, Deutschland 1990
  # Fernsehfilm, Rum<E4>nien/Frankreich/BRD 1968
  # Fernsehserie, BRD 1978
  # Historienfilm, <D6>sterreich/Deutschland 2001
  # Krimireihe, Schweden 1997
  # Kurzfilm, Belgien 2006
  # Serie, USA 2008
  # Spielfilm, Argentinien 2006
  # Stummfilm, Sowjetunion 1924
  # Zeichentrickfilm, USA/Australien 1997
  # 
  if ($subtitle =~ m|^[^ ,]+, [^ ]+ [0-9][0-9][0-9][0-9]$|) {
    my ($format, $pcountries, $pyear) = ($subtitle =~ m|^([^ ,]+), ([^ ]+) ([0-9]+)$|);

    $sce->{production_date} = "$pyear-01-01";
    # programme format is mostly reported in genre, too. so just reuse that
    my ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_genre", $format );
    AddCategory( $sce, $program_type, $categ );
    return undef;
  }
  #
  # production countries [year of production]
  # Deutschland/Polen 2008
  # Deutschland 2007
  #
  if ($subtitle =~ m|^[^ ]+ [0-9][0-9][0-9][0-9]$|) {
    my ($pcountries, $pyear) = ($subtitle =~ m|^([^ ]+) ([0-9]+)$|);

    $sce->{production_date} = "$pyear-01-01";
    return undef;
  }

  #
  # Französischer Spielfilm von 2003
  #
  if ($subtitle =~ m|^\S+ischer [\S+]ilm von [0-9][0-9][0-9][0-9]$|) {
    my ($pcountries, $pyear) = ($subtitle =~ m|^(\S+) \S+ von (\d+)$|);

    $sce->{production_date} = "$pyear-01-01";
    return undef;
  }

  # producers
  # Filmessay von Wolfgang Peschl und Christian Riehs
  # Filme von Wolfram Giese und Horst Brandenburg
  # Filmportr<E4>t von Gallus Kalt
  # Film von Adam Schmedes
  # Film von Alexander von Sobeck, Stephan Merseburger
  # Film von Alexia Sp<E4>th, Ralph Gladitz und Michael Mandlik
  # Film von Carsten Heider
  # Film von Carsten  Heider
  # Film von Claudia Buckenmaier, Anne Gellinek, Peter Kunz und
  # Film von Clara und Robert Kuperberg
  # Film von Mario Schmitt, Heribert Roth, Claudia Buckenmaier
  # Film von Peter Paul Huth und Maik Platzen, Deutschland 2010
  # Film von Rollo und Angelika Gebhard und Andrey Alexander
  # Film von Sabrina Hermsen und Ursula Hopf
  # Film von Sabrina Hermsen und Uschi Hopf
  # Film von Sandra Schlittenhardt, Faika Kalac,
  #
  if ($subtitle =~ m|^Film\S* von \S+ \S+$|) {
    progress ("parsing producer from subtitle: " . $subtitle);
    my ($format, $producer) = ($subtitle =~ m|^(\S+) von (\S+ \S+)$|);

    if ($sce->{producers}) {
      $sce->{producers} = join (", ", $sce->{producers}, $producer);
    } else {
      $sce->{producers} = $producer;
    }

    # programme format is mostly reported in genre, too. so just reuse that
    my ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_genre", $format );
    AddCategory( $sce, $program_type, $categ );

    return undef;
  }
  if ($subtitle =~ m|^Film\S* von \S+ \S+ und \S+ \S+$|) {
    progress ("parsing producers from subtitle: " . $subtitle);
    my ($format, $producer1, $producer2) = ($subtitle =~ m|^(\S+) von (\S+ \S+) und (\S+ \S+)$|);

    if ($sce->{producers}) {
      $sce->{producers} = join (", ", $sce->{producers}, $producer1, $producer2);
    } else {
      $sce->{producers} = join (", ", $producer1, $producer2);
    }

    # programme format is mostly reported in genre, too. so just reuse that
    my ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_genre", $format );
    AddCategory( $sce, $program_type, $categ );

    return undef;
  }

  # possible false positives / more data
  # Film von und mit Axel Bulthaupt
  # Film Otmar Penker und Klaus Feichtenberger
  # Kriminalserie von Herbert Reinecker
  # Portr<E4>tfilm von  Jesse A. Allaoua
  # Portr<E4>t von Friederike Mayr<F6>cker zum 85. Geburtstag
  # Portr<E4>t von Roland Adrowitzer, Ernst Johann Schwarz
  # Reisedokumentation von Thomas Radler und Volker Schmidt
  # Reportagen von Peter Resetarits, Petra Kanduth und Nora
  # Reportage von Alfred Schwarz und Julia Kovarik
  # Roman von Jaroslav Hasek, <D6>sterreich 1975
  # Fox Theatre, Oakland, Kalifornien, USA 2009
  # Gast: Annette Frier
  # Gespr<E4>chssendung mit J<F6>rg Thadeusz
  # Gestaltung: Anita Dollmanits
  # Goldener Saal des Wiener Musikvereins, April 2010
  # Gret Haller und Jean Ziegler im Gespr<E4>ch mit
  # G<E4>ste bei Wieland Backes
  # Harald Lesch und Wilhelm Vossenkuhl im Gespr<E4>ch
  # Historiker David Gugerli im Gespr<E4>ch mit Roger de Weck
  # im Gespr<E4>ch mit Norbert Bischofberger
  # Im Gespr<E4>ch mit Norbert Bischofberger
  # Literarische Comedy mit J<FC>rgen von der Lippe
  #
  # Mit 20 f<FC>r ein Jahr nach S<FC>dafrika
  # mit Alexandra Vacano
  # Mit Andrea Jansen und Mahara McKay
  # mit Anmerkungen von Elmar Theve<DF>en und Thomas Schmeken
  # Mit Claus Richter unterwegs
  # Mit dem Erzgebirgsensemble auf Tour
  # Mit dem Gast Egon Amman, Verleger
  # Mit Dietmar Schumann im vergessenen Osten
  # Mit Ulan &amp; Bator, Michl M<FC>ller und Matthias Reuter
  #
  # Moderation: Charlotte Roche und Giovanni di Lorenzo
  # Politsatire mit Priol und Schramm
  # Reportagen <FC>bers Ehrenamt
  # Sitcom in franz<F6>sischer Sprache
  # Sitcom in spanischer Sprache
  #



  return $subtitle;
}


sub ParseWeek
{
  my( $cref ) = @_;

  my $doc;
  eval { $doc = ParseXml ($cref); };
  if( $@ ne "" )
  {
    error( "Failed to parse $@" );
    return undef;
  }
  
  # Find all "sendung"-entries.
  my $ns = $doc->find( '/programmdaten/@woche' );
  if( $ns->size() != 1 ){
    error( "Multiple 'programmdaten' blocks found" );
    return undef;
  }

  my $week = substr ($ns, 0, 4) . "-" . substr ($ns, 4, 2);

  return $week;
}

1;
