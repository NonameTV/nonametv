package NonameTV::Importer::ZDF_util;

use strict;
use utf8;
use warnings;

=pod

Importer for data in ZDF/3sat DTD.
One file per channel and week in xml-format.

=cut

use DateTime;
use XML::LibXML;
use Switch;

use NonameTV qw/ParseXml norm AddCategory/;
use NonameTV::Log qw/d p w error/;

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
  p( "Found " . $ns->size() . " shows" );

  my $FixupDSTStarttime;
  if( ( $chd->{xmltvid} eq 'hd.zdf.de' ) ) {
#    $FixupDSTStarttime = 1;
  }
  # keep last endtime as a hint for DST switch issues
  my $lastendtime;
  
  foreach my $sc ($ns->get_nodelist)
  {
    my %sce = (
        channel_id  => $chd->{id},
    );

    # the id of the program
    my $id  = $sc->findvalue( './id' );

    # the title
    my $title = $sc->findvalue( './programm//sendetitel' );
    if ($title) {
      $title = clean_sendetitel (\%sce, $title);
    }
    $sce{title} = norm($title);

    # the original title
    my $original_title = norm( $sc->findvalue( './programm//originaltitel' ) );
    if ($original_title) {
      $sce{original_title} = $original_title;
    }

    # episode title
    my $episodetitle = $sc->findvalue( './programm//folgentitel' );

      # form the subtitle out of 'episodetitle' and ignore 'subtitle' completely
      # the information is usually duplicated in the longdesc anyway and of no
      # use for automated processing
      if ($episodetitle) {
        $episodetitle = clean_untertitel ($ds, \%sce, $episodetitle);
        if ($episodetitle) {
          $sce{subtitle} = norm($episodetitle);
          $sce{program_type} = 'series';
        }
      }

    # the subtitle, parse known good information and ignore the rest
    my $subtitles = $sc->findnodes( './programm//untertitel' );
    foreach my $subtitle ($subtitles->get_nodelist) {
      clean_untertitel( $ds, \%sce, $subtitle->string_value() );
    }

    # additional information, parse known good information and ignore the rest
    my $zusatz = $sc->findnodes( './programm//zusatz' );
    foreach my $zs ($zusatz->get_nodelist) {
      clean_untertitel( $ds, \%sce, $zs->string_value() );
    }

    # episode number
    my $episodenr = $sc->findvalue( './programm//folgenr' );
    #my $episodecount = $sc->findvalue( './programm//stafonr' );

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

    # darsteller, beteiligte, stab
    ParseCredits( \%sce, 'actors',     $sc, './programm//besetzung/darsteller' );
    ParseCredits( \%sce, 'writers',    $sc, './programm//drehbuch' );
    ParseCredits( \%sce, 'producers',  $sc, './programm//filmvon' );
    ParseCredits( \%sce, 'guests',     $sc, './programm//gast' );
    ParseCredits( \%sce, 'presenters', $sc, './programm//moderation' );
    ParseCredits( \%sce, 'directors',  $sc, './programm//regie' );
    ParseCredits( \%sce, 'writers',    $sc, './programm//stab/person[funktion=buch]' );

    # form the description out of 'zusatz', 'shortdesc', 'longdesc', 'wholedesc'
    # 'origin'
    my $description;
    $description .= norm($longdesc) || norm($shortdesc) || norm($wholedesc);
    if ($description) {
      $sce{description} = $description;
    }

    # episode number
    if( $episodenr ){
      my $ep = '. ' . ($episodenr-1) . ' .';
      if( !$sce{episode} ){
        $sce{episode} = '. ' . ($episodenr-1) . ' .';
      } elsif( $sce{episode} eq $ep ) {
        d( 'episode number from element is \'' . $ep . '\' but we knew that already' );
      } else {
        p( 'episode number from element is \'' . $ep . '\' but we already got \'' . $sce{episode} . '\'' );
      }
    }

    my $label = $sc->findvalue( './programm//label' );
    if( $label ) {
      # use label as title and push title to subtitle for some labels
      if( ( $label eq '37º' ) or ( $label eq '37°' ) ){
        d( "improving title '" . $sce{title} . "' with label '". $label . "'" );
        if( $sce{subtitle} ){
          $sce{subtitle} = $sce{title} . ' - ' . $sce{subtitle};
        }else{
          $sce{subtitle} = $sce{title};
        }
        $sce{title} = $label;
        $sce{program_type} = 'series';
      }else{
        p( "found label: ". $label );
      }
    }

    my ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_genre", $genre );
    AddCategory( \%sce, $program_type, $categ );

    ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_category", $category );
    AddCategory( \%sce, $program_type, $categ );

    ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_thember", $thember );
    AddCategory( \%sce, $program_type, $categ );


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

      # FIXME bugged day switchover on ZDFinfo files
      # the first starttime >= midnight is one day early
      my $fixedstart = $starttime->clone->add (days => 1);
      if (DateTime->compare ($fixedstart, $endtime) < 0) {
        $starttime->add (days => 1);
        w( "$batch_id: Garbled start date (one day early) for programme id $id - Adjusting." );
      }

      # check if starttime if off by about 60 minutes wrt the last endtime, it's a good hint
      # that we need to move it an hour earlier / later (fix DST disambiguities)
      if( $FixupDSTStarttime && $lastendtime ){
        my $deltaendstart = $starttime->subtract_datetime( $lastendtime );
        my $delta = $deltaendstart->in_units( 'minutes' );
        if( ( $delta > 50 )&&( $delta < 70 ) ){
          # there is a gap of 60+-10 minutes between the programs, move start time to an hour earlier
          w( 'gap of about an hour detected, moving start time (can happen around DST switch)' );
          $starttime->add( hours => -1 );
        }elsif( ( $delta > -70 )&&( $delta < -50 ) ){
          # there is an overlap of 60+-10 minutes between the programs, move start time to an hour later
          w( 'overlap of about an hour detected, moving start time (can happen around DST switch)' );
          $starttime->add( hours => 1 );
        }
      }

      # duration
      my $dauermin = $as->findvalue( 'dauermin' );
      if ($dauermin eq '0') {
        # fixup bugged programme on ZDFneo files, length 0 but end-start is one day
        p( "$batch_id: Zero length programme id $id - Skipping." );
        next;
      } else {
        # fixup for ZDF around DST switchover
        # replace endtime with starttime+duration (now that we fixed up the starttime)
        $endtime = $starttime->clone()->add( minutes => $dauermin );
      }

      # store corrected end time for fudging the next start time around start/end of DST
      $lastendtime = $endtime->clone();

      # attributes
      my $attribute = $as->getElementsByTagName( 'attribute' );

      d ("$chd->{xmltvid}: $starttime - $title");

      my %ce = (
        start_time  => $starttime->ymd("-") . " " . $starttime->hms(":"),
        # FIXME using end_time leaves gaps between programmes on ZDF
        # FIXME no end_time breaks neo / KiKa switch
        # end_time    => $endtime->ymd("-") . " " . $endtime->hms(":"),
      );

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
          # ZDFinfo
          case /&mhp;/  {} # DVB-MHP
          # ZDF new press site after fixups
          case /16zu9/            {$ce{aspect} = "16:9"}
          case /audiodeskription/ {} # audio description
          case /highdefinition/   {$ce{quality} = "HDTV"}
          case /zweikanalton/     {$ce{stereo} = "bilingual"}
          case /&zk;/             {$ce{stereo} = "bilingual"} 
          # new attributes 2012-10
          case /&mo;/   {$ce{stereo} = "mono"}
          case /&f43;/  {$ce{aspect} = "4:3"}
          else                    { w ("unhandled attribute: $attribut") } 
        }
      }

      # append shared ce to this ce
      @ce{keys %sce} = values %sce;

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
    error ("Could not convert time! Check for daylight saving time border. " . $year . "-" . $month . "-" . $day . " " . $hour . ":" . $minute);
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
      $sce->{episode} = '. ' . ($episodenr-1) . '/' . $episodecnt . ' .';
    } else {
      # we guess its one programme thats broken in multiple parts or a serial
      # this will not get type series automatically
      $sce->{episode} = '. . ' . ($episodenr-1) . '/' . $episodecnt;
    }
    $title =~ s| \(\d+/\d+\)$||;
  } elsif ($title =~ m| \(\d+\) - \(\d+\)$|) {
    my ($episodenrfirst, $episodenrlast) = ($title =~ m| \((\d+)\) - \((\d+)\)$|);
    w ("parsing (and ignoring) episode numbers $episodenrfirst-$episodenrlast from title \"$title\"");
    $title =~ s| \(\d+\) - \(\d+\)||;
  } elsif ($title =~ m| \(\d+\)$|) {
    my ($episodenr) = ($title =~ m| \((\d+)\)$|);
    d ("parsing episode number $episodenr from title \"$title\"");
    $sce->{episode} = '. ' . ($episodenr-1) . ' .';
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

  # strip "(german) premiere"
  if ($subtitle =~ m/\s*(?:Deutsche\s+|)Erstausstrahlung$/) {
    $subtitle =~ s/\s*(?:Deutsche\s+|)Erstausstrahlung$//;
  }

  # strip "repeat"
  if ($subtitle =~ m|^\(Wh\.\)$|) {
    return undef;
  }
  if ($subtitle =~ m|\s+\(Wh\..*\)$|) {
    $subtitle =~ s|\s+\(Wh\..*\)$||;
  }
  # strip repeat in ZDFneo style
  if ($subtitle =~ m|\s*\([Vv]om \d+\.\d+\.\d{4}\)$|) {
    $subtitle =~ s|\s*\([Vv]om \d+\.\d+\.\d{4}\)$||;
  }
  # strip repeat in ZDFneo style
  if ($subtitle =~ m|\s*\([Vv]on \d+\.\d{2} Uhr\)$|) {
    $subtitle =~ s|\s*\([Vv]on \d+\.\d{2} Uhr\)$||;
  }
  # strip repeat in ZDFneo style
  if ($subtitle =~ m|\s*\(ZDF \d+\.\d+\.\d{4}\)$|) {
    $subtitle =~ s|\s*\(ZDF \d+\.\d+\.\d{4}\)$||;
  }

  # strip "anschl. Wetter"
  if ($subtitle =~ m|^anschl\. 3sat-Wetter$|) {
    return undef;
  }

  # move foreign series title to programme title (for 3sat)
  if( $subtitle =~ m|^\(aus der .*Reihe \".*\"\)$| ) {
    my( $seriesname )=( $subtitle =~ m|^\(aus der .*Reihe \"(.*)\"\)$| );

    if( defined( $sce->{subtitle} ) ){
      $sce->{subtitle} = $sce->{title} . ": " . $sce->{subtitle};
    } else {
      $sce->{subtitle} = $sce->{title};
    }
    $sce->{title} = $seriesname;
    
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
  # [format,] production countries [year of production] (seen on 3sat)
  # Fernsehfilm, BRD 1980
  #
  if ($subtitle =~ m|^[^ ,]+ [^ ]+, [0-9][0-9][0-9][0-9]$|) {
    my ($format, $pcountries, $pyear) = ($subtitle =~ m|^([^ ,]+) ([^ ,]+), ([0-9]+)$|);

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
  # Amerikanischer Spielfilm 1994
  #
  if ($subtitle =~ m/^\S+ischer \S+ilm (?:von |)\d{4}$/) {
    my ($pcountries, $format, $pyear) = ($subtitle =~ m/^(\S+) (\S+) (?:von |)(\d{4})$/);

    $sce->{production_date} = "$pyear-01-01";
    my ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_genre", $format );
    AddCategory( $sce, $program_type, $categ );
    return undef;
  }

  #
  # Dokumentation (D 1980)
  #
  if ($subtitle =~ m|^\S+\s+\(\S+\s+\d{4}\)$|) {
    my ($format, $pcountries, $pyear) = ($subtitle =~ m|^(\S+)\s+\((\S+)\s+(\d{4})\)$|);

    $sce->{production_date} = "$pyear-01-01";
    my ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_genre", $format );
    AddCategory( $sce, $program_type, $categ );
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
  if ($subtitle =~ m/^(?:Film\S*|Reportage) von \S+ \S+$/) {
    d( "parsing producer from subtitle: " . $subtitle );
    my ($format, $producer) = ($subtitle =~ m|^(\S+) von (\S+ \S+)$|);

    AddCredits( $sce, 'producers', ($producer) );

    # programme format is mostly reported in genre, too. so just reuse that
    my ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_genre", $format );
    AddCategory( $sce, $program_type, $categ );

    return undef;
  }
  if ($subtitle =~ m|^Film\S* von \S+ \S+ und \S+ \S+$|) {
    d( "parsing producers from subtitle: " . $subtitle );
    my ($format, $producer1, $producer2) = ($subtitle =~ m|^(\S+) von (\S+ \S+) und (\S+ \S+)$|);

    AddCredits( $sce, 'producers', ($producer1, $producer2) );

    # programme format is mostly reported in genre, too. so just reuse that
    my ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_genre", $format );
    AddCategory( $sce, $program_type, $categ );

    return undef;
  }

  # ZDF Infokanal appends producers to the episode title
  if ($subtitle =~ m|Film von .*$|) {
    d( 'parsing producer from subtitle: ' . $subtitle );
    my ($producer) = ($subtitle =~ m|Film von (.*)$|);
    $subtitle =~ s|\s*Film von .*$||;
    $subtitle =~ s|\s*Ein$||;
    if( $subtitle eq '' ) {
      $subtitle = undef;
    }

    # split at "und"
    my @producers = split( '\s+und\s+', $producer );
    # join with comma and split again (to handle three producers)
    $producer = join( ', ', @producers );
    @producers = split( ',\s*', $producer );

    AddCredits( $sce, 'producers', @producers );

#    fall-through to capture episode number from subtitle, too.
#    return $subtitle;
    if( !defined( $subtitle) ) {
      return $subtitle;
    }
  }

  # ZDF Infokanal appends presenters to the episode title
  if ($subtitle =~ m|Moderation: .*$|) {
    d( 'parsing presenters from subtitle: ' . $subtitle );
    my ($presenter) = ($subtitle =~ m|Moderation: (.*)$|);
    $subtitle =~ s|\s*Moderation: .*$||;
    if( $subtitle eq '' ) {
      $subtitle = undef;
    }

    # split at "und"
    my @presenters = split( '\s+und\s+', $presenter);
    # join with comma and split again (to handle three presenters)
    $presenter = join( ', ', @presenters);
    @presenters = split( ',\s*', $presenter );

    AddCredits( $sce, 'presenters', @presenters);

#    fall-through to capture episode number from subtitle, too.
#    return $subtitle;
    if( !defined( $subtitle) ) {
      return $subtitle;
    }
  }

  # ZDF.kultur puts the episode number in front of the episode title
  # ZDFinfokanal, too
  if( $ds->{currbatchname} =~ m/^(?:infokanal|kultur)\./ ){
    if( $subtitle =~ m|^\d+\.\s+.*$| ){
      d( 'parsing episode number from subtitle: ' . $subtitle );
      my( $episodenr, $title )=( $subtitle =~ m|^(\d+)\.\s+(.*)$| );

      $sce->{episode} = '. ' . ($episodenr-1) . ' .';

      return $title;
    }
  }

  # ZDFinfokanal puts the presenter at the end of the subtitle (if it's Guido Knopp's ZDF-History)
  if( $ds->{currbatchname} =~ m/^(?:infokanal)\./ ){
    if ($subtitle =~ m|\s+mit (?:Guido Knopp)$|) {
      d( 'parsing presenters from subtitle: ' . $subtitle );
      my ($presenter) = ($subtitle =~ m|\s+mit (Guido Knopp)$|);
      my @presenters = split( ',\s*', $presenter );
      AddCredits( $sce, 'presenters', @presenters);
      $subtitle =~ s|\s+mit (?:Guido Knopp)$||;
      if( $subtitle eq '' ) {
        return undef;
      }
    }
  }

  # Fünfteilige Doku-Reihe von Michaela Hummel
  if ($subtitle =~ m/^(?:\S+eilige\s+|)\S+eihe\s+von \S+ \S+$/) {
    d( "parsing producer from subtitle: " . $subtitle );
    my ($format, $producer) = ($subtitle =~ m/^(?:\S+eilige\s+|)(\S+eihe)\s+von (\S+ \S+)$/);

    AddCredits( $sce, 'producers', ($producer) );

    # programme format is mostly reported in genre, too. so just reuse that
    my ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_genre", $format );
    AddCategory( $sce, $program_type, $categ );

    return undef;
  }
  # Fünfteilige Doku-Reihe von Michaela Hummel und Meike Materne
  if ($subtitle =~ m/^(?:\S+eilige |)\S+eihe\s+von \S+ \S+ und \S+ \S+$/) {
    d( "parsing producers from subtitle: " . $subtitle );
    my ($format, $producer1, $producer2) = ($subtitle =~ m/^(?:\S+eilige |)(\S+eihe)\s+von (\S+ \S+) und (\S+ \S+)$/);

    AddCredits( $sce, 'producers', ($producer1, $producer2) );

    # programme format is mostly reported in genre, too. so just reuse that
    my ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_genre", $format );
    AddCategory( $sce, $program_type, $categ );

    return undef;
  }

  # strip repeats
  # (von 18.35 Uhr)
  if ($subtitle =~ m|^\(von \d+\.\d{2} Uhr\)$|) {
    return undef;
  }
  # (Erstsendung 6.9.2009)
  if ($subtitle =~ m|^\(Erstsendung \d+\.\d+\.\d{4}\)$|) {
    return undef;
  }
  # (vom Vortag)
  if ($subtitle =~ m|^\(vom Vortag\)$|) {
    return undef;
  }

  # Folge 102
  if (my ($ep) = ($subtitle =~ m|^Folge (\d+)$|)) {
    if( !$sce->{episode} ){
      $sce->{episode} = '. ' . ($ep - 1) . ' .';
    }
    return undef;
  }

  # ZDFneo episode number in front of episode title but keep "10.000 Meilen"
  # 1. Folgentitle
  # but not for parts!
  # 1. Teil
  if (my ($ep, $eptitle) = ($subtitle =~ m|^(\d+)\.\s+((?!Teil).*)$|)) {
    if( !$sce->{episode} ){
      $subtitle = $eptitle;
      $sce->{episode} = '. ' . ($ep - 1) . ' .';
    }
  }
  # Zeichentrickserie
  # CGI-Animationsserie
  # Fantasy-Serie
  if ($subtitle =~ m/^(?:\S+eilige\s+|)(?:\S+eihe|\S+erie|Dokusoap|Die ZDFneo-Reportage)$/) {
    my ($format) = ($subtitle =~ m/^(?:\S+eilige\s+|)(\S+eihe|\S+erie|Dokusoap|Die ZDFneo-Reportage)$/);

    my ( $program_type, $categ ) = $ds->LookupCat( "DreiSat_genre", $format );
    AddCategory( $sce, $program_type, $categ );
    return undef;
  }

  # Auswandererdoku
  # Das Entdeckermagazin mit Eric Mayer
  # mit Normen Odenthal
  # mit Barbara Hahlweg
  # Hongkong-Spielfilm von 2003
  # Nach Motiven der Romane von Maj Sjöwall und Per Wahlöö
  # Film von Claus U. Eckert und Petra Thurn
  # 

  if( $subtitle ){
    d( 'no match (or fall-through) for subtitle: ' . $subtitle );
  }else{
    $subtitle = undef;
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


# call with sce, target field, sendung element, xpath expression
# e.g. ParseCredits( \%sce, 'actors', $sc, './programm//besetzung/darsteller' );
# e.g. ParseCredits( \%sce, 'writers', $sc, './programm//stab/person[funktion=buch]' );
sub ParseCredits
{
  my( $ce, $field, $root, $xpath) = @_;

  my @people;
  my $nodes = $root->findnodes( $xpath );
  foreach my $node ($nodes->get_nodelist) {
    my $person = $node->string_value();
    if( $person ne '' ) {
      push( @people, $person );
    }
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
