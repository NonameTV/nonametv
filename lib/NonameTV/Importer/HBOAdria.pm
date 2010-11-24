package NonameTV::Importer::HBOAdria;

use strict;
use warnings;

=pod

Importer for data from HBO Adria. 
One file per month downloaded from hbo.hr site.
The downloaded file is in html-format.

Features:

=cut

use POSIX qw/strftime/;
use DateTime;
use Unicode::String qw(utf8 latin1);
use Locale::Recode;
use HTML::TableExtract;
use HTML::Parse;
use HTML::FormatText;
use XML::LibXML;
use Spreadsheet::ParseExcel;
use IMDB::Film;

use NonameTV qw/MyGet norm AddCategory MonthNumber/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV::Config qw/ReadConfig/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

use constant {
  FT_UNKNOWN      => 0,  # unknown
  FT_XML_HBOADRIA => 1,  # HBOAdria xml file
  FT_XML_CINEMAX  => 2,  # Cinemax xml file
  FT_XML_AXN      => 3,  # AXN xml file
};

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

  my $conf = ReadConfig();

  $self->{FileStore} = $conf->{FileStore};

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile
{
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $channel_id = $chd->{id};
  my $channel_xmltvid = $chd->{xmltvid};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

#return if( $file !~ /Cinemax_Raspored_04-09_CRO\.XLS/i );
#return if( $channel_xmltvid !~ /axn/i );

  if( $file =~ /\.xml$/i ){
    my $ft = CheckFileFormat( $file );
    if( $ft eq FT_XML_HBOADRIA ){
      $self->ImportXML_HBOAdria( $file, $chd );
    } elsif( $ft eq FT_XML_CINEMAX ){
      $self->ImportXML_Cinemax( $file, $chd );
    } elsif( $ft eq FT_XML_AXN ){
      $self->ImportXML_AXN( $file, $chd );
    }
  } elsif( $file =~ /\.xls$/i ){
    #$self->ImportXLS( $file, $chd );
  } elsif( $file =~ /\.html$/i ){
    #$self->ImportHTML( $file, $chd );
  }

  return;
}

sub CheckFileFormat
{
  my( $file ) = @_;

  # Only process .xml files.
  return if( $file !~ /\.xml$/i );

  # find 'ScheduleData' or 'AdminWebsiteData' blocks
  # HBO Adria and HBO Comedy come with 'ScheduleData'
  # Cinemax and Cinemax2 come with 'AdminWebsiteData'

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "HBOAdria: Failed to parse xml file $file" );
    return FT_UNKNOWN;
  }

  my $sdbs;

  $sdbs = $doc->findnodes( "//ScheduleData" );
  if( $sdbs->size() gt 0 ) {
    progress( "HBOAdria: HBOAdria XML format recognized in $file" );
    return FT_XML_HBOADRIA;
  }

  $sdbs = $doc->findnodes( "//AdminWebsiteData" );
  if( $sdbs->size() gt 0 ) {
    progress( "HBOAdria: Cinemax XML format recognized in $file" );
    return FT_XML_CINEMAX;
  }

  $sdbs = $doc->findnodes( "//AXN" );
  if( $sdbs->size() gt 0 ) {
    progress( "HBOAdria: AXN XML format recognized in $file" );
    return FT_XML_AXN;
  }

  return FT_UNKNOWN;
}

sub ImportHTML
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my $nowday;
  my $starttime;
  my $laststart;
  my $duration;
  my $title;
  my $stereo;
  my $director;
  my $actors;
  my $genre;
  my $rating;

  my $nowyear = DateTime->today->year();
  my $nowmonth = DateTime->today->month();

  progress("HBOAdria: processing HTML/XLS file $file");

  my $te = HTML::TableExtract->new(
    #headers => [qw(TID TITTEL)],
    keep_html => 1
    );

  #$te->parse($$cref);
  $te->parse_file($file);

  my $table = $te->first_table_found();

  foreach my $row ($table->rows) {

    #
    # column 0: day of the month
    #
    my $col = norm(@$row[0]);
    my $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content =~ /Filmovi/ ) {
      progress("HBOAdria: Content of the file is '$content'");
      next;
    }

    if ( scalar( $content ) ) {
      $nowday = $content;
      progress("HBOAdria: Date is $nowday");
    }

    #
    # column 1: start time
    #
    $col = norm(@$row[1]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content ) {
      $starttime = $content;
      #progress("HBOAdria: start time is $starttime");
    }

    #
    # column 2: stereo
    #
    $col = norm(@$row[2]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content ) {
      $stereo = $content;

      $stereo = 'mono' if( $stereo =~ /MONO/i );
      $stereo = 'stereo' if( $stereo =~ /STEREO/i );
      $stereo = 'dolby digital' if( $stereo =~ /DOLBY_5\.1/i );
      $stereo = 'dolby' if( $stereo =~ /DOLBY/i );
      $stereo = 'surround' if( $stereo =~ /SURROUND/i );

      #progress("HBOAdria: stereo is $stereo");
    }

    #
    # column 3: title
    #
    $col = norm(@$row[3]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    # recode the title from windows-1250 to UTF-8
    my $cod = Locale::Recode->new( from => 'windows-1250' , to => 'UTF-8' );
    $cod->recode( $content );

    if ( $content ) {
      $title = $content;
      #progress("HBOAdria: title is $title");
    }

    #
    # column 4: director
    #
    $col = norm(@$row[4]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content ) {
      $director = $content;
      #progress("HBOAdria: director is $director");
    }

    #
    # column 5: actors
    #
    $col = norm(@$row[5]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content ) {
      $actors = $content;
      #progress("HBOAdria: actors is $actors");
    }

    #
    # column 6: genre
    #
    $col = norm(@$row[6]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content ) {
      $genre = $content;
      #progress("HBOAdria: genre is $genre");
    }

    #
    # column 7: rating
    #
    $col = norm(@$row[7]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content ) {
      $rating = $content;
      #progress("HBOAdria: rating is $rating");
    }

    #
    # column 8: duration
    #
    $col = norm(@$row[8]);
    $content = HTML::FormatText->new->format(parse_html($col));

    # trim
    $content =~ s/^\s+|\s+$//g;

    if ( $content ) {
      $duration = $content;
      #progress("HBOAdria: duration is $duration");
    }

    #
    # set right times
    #
    my( $start_dt , $end_dt ) = create_dt( $nowyear , $nowmonth , $nowday , $starttime , $duration );
    if( $start_dt < $laststart ){
      $start_dt->add( days => 1 );
      $end_dt->add( days => 1 );
    }
    $laststart = $start_dt;

    if( defined $nowday ){

      progress("HBOAdria: $chd->{xmltvid}: $start_dt - $title ($stereo,$rating)");

      my $ce = {
               channel_id   => $chd->{id},
               title        => $title,
               start_time   => $start_dt->ymd("-") . " " . $start_dt->hms(":"),
               end_time     => $end_dt->ymd("-") . " " . $end_dt->hms(":"),
               stereo       => $stereo,
               rating       => $rating,
               directors    => $director,
               actors       => $actors,
      };

      my($program_type, $category ) = $ds->LookupCat( "HBOAdria", $genre );
      AddCategory( $ce, $program_type, $category );

      $ds->AddProgramme( $ce );
    }

  }

  # Success
  return 1;
}

sub ImportXLS
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  my %columns = ();
  my $date;
  my $currdate = "x";

  progress( "HBOAdria XLS: $chd->{xmltvid}: Processing XLS $file" );


  my $oBook = Spreadsheet::ParseExcel::Workbook->Parse( $file );

  if( not defined( $oBook ) ) {
    error( "HBOAdria XLS: $file: Failed to parse xls" );
    return;
  }

  for(my $iSheet=0; $iSheet < $oBook->{SheetCount} ; $iSheet++){

    my $oWkS = $oBook->{Worksheet}[$iSheet];
    progress("HBOAdria XLS: $chd->{xmltvid}: processing worksheet named '$oWkS->{Name}'");

    # browse through rows
    # schedules are starting after that
    # valid schedule row must have date, time and title set
    for(my $iR = $oWkS->{MinRow} ; defined $oWkS->{MaxRow} && $iR <= $oWkS->{MaxRow} ; $iR++) {

      # get the names of the columns from the 1st row
      if( not %columns ){

        for(my $iC = $oWkS->{MinCol} ; defined $oWkS->{MaxCol} && $iC <= $oWkS->{MaxCol} ; $iC++) {
          $columns{$oWkS->{Cells}[$iR][$iC]->Value} = $iC;
        }
#foreach my $cl (%columns) {
#print "$cl\n";
#}

        if( not defined $columns{'Date'} ){
          %columns = ();
        }

        next;
      }

      my $oWkC;

      # Date
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Date'}];
      if( $oWkC->Value ){

        $date = ParseDate( $oWkC->Value );

        if( $date ne $currdate ) {
          if( $currdate ne "x" ) {
            $dsh->EndBatch( 1 );
          }

          my $batch_id = $chd->{xmltvid} . "_" . $date;
          $dsh->StartBatch( $batch_id , $chd->{id} );
          $dsh->StartDate( $date , "06:00" );
          $currdate = $date;

          progress("HBOAdria XLS: $chd->{xmltvid}: Date is: $date");
        }
      }

      # Time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Time'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $time = $oWkC->Value;

      # Croatian Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Croatian Title'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $crotitle = $oWkC->Value;

      # Original Title
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Original Title'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $origtitle = $oWkC->Value;

      # Genre
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Genre'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $genre = $oWkC->Value;

      # Country Origin
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Country Origin'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $country = $oWkC->Value;

      # Production Year
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Year'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $prodyear = $oWkC->Value;

      # Run Time
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Run Time'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $runtime = $oWkC->Value;

      # Director
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Director'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $directors = $oWkC->Value;

      # Actors
      $oWkC = $oWkS->{Cells}[$iR][$columns{'Cast1'}];
      next if( ! $oWkC );
      next if( ! $oWkC->Value );
      my $actors = $oWkC->Value;

      #progress( "HBOAdria XLS: $chd->{xmltvid}: $time - $origtitle" );

      my $ce = {
        channel_id => $chd->{id},
        title => $crotitle || $origtitle,
        subtitle => $origtitle,
        start_time => $time,
      };

      if( $genre ){
        my($program_type, $category ) = $ds->LookupCat( 'HBOAdria', $genre );
        AddCategory( $ce, $program_type, $category );
      }

      if( defined( $prodyear ) and ($prodyear =~ /(\d\d\d\d)/) )
      {
        $ce->{production_date} = "$1-01-01";
      }

      $ce->{directors} = $directors if $directors;
      $ce->{actors} = $actors if $actors;

      QueryIMDB( $origtitle, $ce );

      $dsh->AddProgramme( $ce );

    } # next row
  } # next sheet

}

sub ImportXML_HBOAdria
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  progress( "HBOAdria: $chd->{xmltvid}: Processing XML $file" );

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "HBOAdria: $chd->{xmltvid}: Failed to parse xml file $file" );
    return;
  }

  # find 'ScheduleData' blocks
  my $sdbs = $doc->findnodes( "//ScheduleData" );
  if( $sdbs->size() == 0 ) {
    error( "HBOAdria: $chd->{xmltvid}: No 'ScheduleData' blocks found" ) ;
    return 0;
  }
  progress( "HBOAdria: $chd->{xmltvid}: " . $sdbs->size() . " schedule blocks found" );

  # browse through ScheduleData nodes
  foreach my $sdb ($sdbs->get_nodelist)
  {

    my @ces;

    # find 'vwScheduledTitle' events
    my $vwsts = $sdb->findnodes( ".//vwScheduledTitle" );
    if( $vwsts->size() == 0 ) {
      error( "HBOAdria: $chd->{xmltvid}: No 'vwScheduledTitle' events found" ) ;
      next;
    }
    progress( "HBOAdria: $chd->{xmltvid}: " . $vwsts->size() . " events found" );

    foreach my $vwst ($vwsts->get_nodelist)
    {
      my $scheduleid  = $vwst->findvalue( './/ScheduleId' );
      my $countryid  = $vwst->findvalue( './/CountryId' );
      my $scheduleday = $vwst->findvalue( './/ScheduleDay' );
      my $starttime = $vwst->findvalue( './/StartTime' );
      my $ispremiere = $vwst->findvalue( './/IsPremiere' );
      my $channelid = $vwst->findvalue( './/ChannelId' );
      my $sound = $vwst->findvalue( './/Sound' );
      my $runtime = $vwst->findvalue( './/RunTime' );
      my $edition = $vwst->findvalue( './/Edition' );
      my $translation = $vwst->findvalue( './/Translation' );
      my $originaltitle = $vwst->findvalue( './/OriginalTitle' );
      my $episodenumber = $vwst->findvalue( './/EpisodeNumber' );
      my $productiondate = $vwst->findvalue( './/ProductionDate' );
      my $titleid = $vwst->findvalue( './/TitleId' );
      my $localtitle = $vwst->findvalue( './/LocalTitle' );
      my $localseriestitle = $vwst->findvalue( './/LocalSeriesTitle' );
      my $localdirector = $vwst->findvalue( './/LocalDirector' );
      my $localcast = $vwst->findvalue( './/LocalCast' );
      my $localgenre1 = $vwst->findvalue( './/LocalGenre1' );
      my $localgenre2 = $vwst->findvalue( './/LocalGenre2' );
      my $localcountryorigin = $vwst->findvalue( './/LocalCountryOrigin' );
      my $localoriginallanguage = $vwst->findvalue( './/LocalOriginalLanguage' );
      my $locallogline = $vwst->findvalue( './/LocalLogLine' );
      my $localsynopsis = $vwst->findvalue( './/LocalSynopsis' );
      my $approved = $vwst->findvalue( './/Approved' );
      my $ishighlight = $vwst->findvalue( './/IsHighlight' );

      my $mainpromoimage = $vwst->findvalue( './/MainPromoImage' );
      my $widethumbnailimage = $vwst->findvalue( './/WideThumbnailImage' );
      my $halfpromoimage = $vwst->findvalue( './/HalfPromoImage' );
      my $thirdpromoimage = $vwst->findvalue( './/ThirdPromoImage' );
      my $thumbnailimage = $vwst->findvalue( './/ThumbnailImage' );
      my $galleryimage1 = $vwst->findvalue( './/GalleryImage1' );
      my $galleryimage2 = $vwst->findvalue( './/GalleryImage2' );
      my $galleryimage3 = $vwst->findvalue( './/GalleryImage3' );

      my $schedulingcategory = $vwst->findvalue( './/SchedulingCategory' );
      my $packagetype = $vwst->findvalue( './/PackageType' );
      my $localrating = $vwst->findvalue( './/LocalRating' );
      my $islaststarttime = $vwst->findvalue( './/IsLastStartTime' );

      my $time = ParseStartTime( $starttime );

      next if( ! $time );
      next if( ! $localtitle );

      my $ce = {
        channel_id => $chd->{id},
        title      => norm($localtitle),
        start_time => $time,
      };

      $ce->{schedule_id} = $scheduleid if ( $scheduleid =~ /\S/ );
      $ce->{title_id} = $titleid if ( $titleid =~ /\S/ );
      $ce->{subtitle} = $originaltitle if ( $originaltitle =~ /\S/ );
      $ce->{description} = $localsynopsis if ( $localsynopsis =~ /\S/ );
      $ce->{directors} = $localdirector if ( $localdirector =~ /\S/ );
      $ce->{actors} = $localcast if ( $localcast =~ /\S/ );
      $ce->{rating} = $localrating if ( $localrating =~ /\S/ );
      #$ce->{country} = $localcountryorigin if ( $localcountryorigin =~ /\S/ );
      #$ce->{date} = $productiondate if ( $productiondate =~ /\S/ );
      $ce->{aspect} = "4:3";

      if( $sound =~ /\S/ ) {
        $ce->{stereo} = 'mono' if( $sound =~ /MONO/i );
        $ce->{stereo} = 'stereo' if( $sound =~ /STEREO/i );
        $ce->{stereo} = 'dolby digital' if( $sound =~ /DOLBY_5\.1/i );
        $ce->{stereo} = 'dolby' if( $sound =~ /DOLBY/i );
        $ce->{stereo} = 'surround' if( $sound =~ /SURROUND/i );
      }

      if( $episodenumber gt 0 ){
        $ce->{episode} = sprintf( ". %d .", $episodenumber - 1 );
      }

      if( $localgenre1 =~ /\S/ ){
        my($program_type, $category ) = $ds->LookupCat( "HBOAdria", $localgenre1 );
        AddCategory( $ce, $program_type, $category );
      }

      if( $localgenre2 =~ /\S/ ){
        my($program_type, $category ) = $ds->LookupCat( "HBOAdria", $localgenre2 );
        AddCategory( $ce, $program_type, $category );
      }

      $ce->{url_image_main} = $mainpromoimage if ( $mainpromoimage =~ /\S/ );
      $ce->{url_image_thumbnail} = $thumbnailimage if ( $thumbnailimage =~ /\S/ );
      $ce->{url_image_icon} = $halfpromoimage if ( $halfpromoimage =~ /\S/ );

      QueryIMDB( $originaltitle, $ce );

      push( @ces , $ce );
    }

    progress("HBOAdria: $chd->{xmltvid}: Populating database with " . @ces . " events" );
    FlushData( $dsh, $chd->{id}, $chd->{xmltvid}, @ces );
  }

  return 1;
}

sub ImportXML_Cinemax
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  progress( "HBOAdria: $chd->{xmltvid}: Processing XML $file" );

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "HBOAdria: $chd->{xmltvid}: Failed to parse xml file $file" );
    return;
  }

  # find 'AdminWebsiteData' blocks
  my $sdbs = $doc->findnodes( "//AdminWebsiteData" );
  if( $sdbs->size() == 0 ) {
    error( "HBOAdria: $chd->{xmltvid}: No 'AdminWebsiteData' blocks found" ) ;
    return 0;
  }
  progress( "HBOAdria: $chd->{xmltvid}: " . $sdbs->size() . " schedule blocks found" );

  # browse through ScheduleData nodes
  foreach my $sdb ($sdbs->get_nodelist)
  {

    my @ces;

    # find 'sp_GetFullProgram' events
    my $vwsts = $sdb->findnodes( ".//sp_GetFullProgram" );
    if( $vwsts->size() == 0 ) {
      error( "HBOAdria: $chd->{xmltvid}: No 'sp_GetFullProgram' events found" ) ;
      next;
    }
    progress( "HBOAdria: $chd->{xmltvid}: " . $vwsts->size() . " events found" );

    foreach my $vwst ($vwsts->get_nodelist)
    {
      my $scheduleid  = $vwst->findvalue( './/ScheduleId' );
      my $countryid  = $vwst->findvalue( './/CountryId' );
      my $scheduleday = $vwst->findvalue( './/ScheduleDay' );
      my $starttime = $vwst->findvalue( './/StartTime' );
      my $ispremiere = $vwst->findvalue( './/IsPremiere' );
      my $channelid = $vwst->findvalue( './/ChannelId' );
      my $sound = $vwst->findvalue( './/Sound' );
      my $runtime = $vwst->findvalue( './/RunTime' );
      my $edition = $vwst->findvalue( './/Edition' );
      my $translation = $vwst->findvalue( './/Translation' );
      my $originaltitle = $vwst->findvalue( './/OriginalTitle' );
      my $episodenumber = $vwst->findvalue( './/EpisodeNumber' );
      my $productiondate = $vwst->findvalue( './/ProductionDate' );
      my $titleid = $vwst->findvalue( './/TitleId' );
      my $localtitle = $vwst->findvalue( './/LocalTitle' );
      my $localdirector = $vwst->findvalue( './/LocalDirector' );
      my $localcast = $vwst->findvalue( './/LocalCast' );
      my $localgenre1 = $vwst->findvalue( './/LocalGenre1' );
      my $localgenre2 = $vwst->findvalue( './/LocalGenre2' );
      my $localcountryorigin = $vwst->findvalue( './/LocalCountryOrigin' );
      my $localoriginallanguage = $vwst->findvalue( './/LocalOriginalLanguage' );
      my $locallogline = $vwst->findvalue( './/LocalLogLine' );
      my $approved = $vwst->findvalue( './/Approved' );
      my $ishighlight = $vwst->findvalue( './/IsHighlight' );

      my $imagebig = $vwst->findvalue( './/BigImage' );
      my $imagenormal = $vwst->findvalue( './/NormalImage' );
      my $imageicon = $vwst->findvalue( './/IconImage' );

      my $islaststarttime = $vwst->findvalue( './/IsLastStartTime' );

      # ChannelId should match the
      next if( $chd->{grabber_info} ne $channelid );

      my $time = ParseStartTime( $starttime );

      next if( ! $time );
      next if( ! $localtitle );

      my $ce = {
        channel_id => $chd->{id},
        title      => norm($localtitle),
        start_time => $time,
      };

      $ce->{subtitle} = $originaltitle if ( $originaltitle =~ /\S/ );
      $ce->{description} = $locallogline if ( $locallogline =~ /\S/ );
      $ce->{directors} = $localdirector if ( $localdirector =~ /\S/ );
      $ce->{actors} = $localcast if ( $localcast =~ /\S/ );
      #$ce->{rating} = $localrating if ( $localrating =~ /\S/ );
      #$ce->{country} = $localcountryorigin if ( $localcountryorigin =~ /\S/ );
      #$ce->{date} = $productiondate if ( $productiondate =~ /\S/ );
      $ce->{aspect} = "4:3";

      if( $sound =~ /\S/ ) {
        $ce->{stereo} = 'mono' if( $sound =~ /MONO/ );
        $ce->{stereo} = 'stereo' if( $sound =~ /STEREO/ );
        $ce->{stereo} = 'dolby digital' if( $sound =~ /DOLBY_5\.1/ );
        $ce->{stereo} = 'dolby' if( $sound =~ /DOLBY/ );
        $ce->{stereo} = 'surround' if( $sound =~ /SURROUND/ );
      }

      if( $episodenumber gt 0 ){
        $ce->{episode} = sprintf( ". %d .", $episodenumber - 1 );
      }

      if( $localgenre1 =~ /\S/ ){
        my($program_type, $category ) = $ds->LookupCat( "HBOAdria", $localgenre1 );
        AddCategory( $ce, $program_type, $category );
      }

      if( $localgenre2 =~ /\S/ ){
        my($program_type, $category ) = $ds->LookupCat( "HBOAdria", $localgenre2 );
        AddCategory( $ce, $program_type, $category );
      }

      $ce->{url_image_main} = $imagebig if ( $imagebig =~ /\S/ );
      $ce->{url_image_thumbnail} = $imagenormal if ( $imagenormal =~ /\S/ );
      $ce->{url_image_icon} = $imageicon if ( $imageicon =~ /\S/ );

      push( @ces , $ce );
    }

    progress("HBOAdria: $chd->{xmltvid}: Populating database with " . @ces . " events" );
    FlushData( $dsh, $chd->{id}, $chd->{xmltvid}, @ces );
  }

  return 1;
}

sub ImportXML_AXN
{
  my $self = shift;
  my( $file, $chd ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  progress( "HBOAdria: $chd->{xmltvid}: Processing XML $file" );

  my $doc;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "HBOAdria: $chd->{xmltvid}: Failed to parse xml file $file" );
    return;
  }

  my $date;
  my $currdate = "x";

  # find 'Programme' blocks
  my $sdbs = $doc->findnodes( "//Programme" );
  if( $sdbs->size() == 0 ) {
    error( "HBOAdria: $chd->{xmltvid}: No 'Programme' blocks found" ) ;
    return 0;
  }
  progress( "HBOAdria: $chd->{xmltvid}: " . $sdbs->size() . " programme blocks found" );

  # browse through Programme nodes - one node is here for each day
  foreach my $sdb ($sdbs->get_nodelist)
  {

    my $channelname  = $sdb->findvalue( './/ChannelName' );
    $date  = ParseDate( $sdb->findvalue( './/LogDate' ) );

    if( $date ne $currdate ) {
      if( $currdate ne "x" ) {
        $dsh->EndBatch( 1 );
      }

      my $batch_id = $chd->{xmltvid} . "_" . $date;
      $dsh->StartBatch( $batch_id , $chd->{id} );
      $dsh->StartDate( $date , "00:00" );
      $currdate = $date;

      progress("HBOAdria: $chd->{xmltvid}: Date is: $date");
    }

    # find 'Series' events
    my $vwsts = $sdb->findnodes( ".//Series" );
    if( $vwsts->size() == 0 ) {
      error( "HBOAdria: $chd->{xmltvid}: No 'Series' events found" ) ;
      next;
    }
    progress( "HBOAdria: $chd->{xmltvid}: " . $vwsts->size() . " events found" );

    # browse through Series nodes
    foreach my $vwst ($vwsts->get_nodelist)
    {

      my $seriesid = $vwst->findvalue( './/SeriesId' );
      my $title = $vwst->findvalue( './/Title' );
      my $season = $vwst->findvalue( './/Season' );
      my $logline = $vwst->findvalue( './/LogLine' );
      my $synopsis = $vwst->findvalue( './/Synopsis' );

      my $episodeid = $vwst->findvalue( './/Episodes//Episode//EpisodeId' );
      my $originalcountry = $vwst->findvalue( './/Episodes//Episode//OriginalCountry' );
      my $runtime = $vwst->findvalue( './/Episodes//Episode//RunTime' );
      my $episodenumber = $vwst->findvalue( './/Episodes//Episode//EpisodeNumber' );
      my $productiondate = $vwst->findvalue( './/Episodes//Episode//ProductionDate' );
      my $eplogline = $vwst->findvalue( './/Episodes//Episode//LogLine' );
      my $epsynopsis = $vwst->findvalue( './/Episodes//Episode//Synopsis' );
      my $epgenre1 = $vwst->findvalue( './/Episodes//Episode//Genre1' );
      my $epgenre2 = $vwst->findvalue( './/Episodes//Episode//Genre2' );
      my $epdirector = $vwst->findvalue( './/Episodes//Episode//Director' );
      my $epcast = $vwst->findvalue( './/Episodes//Episode//Cast' );

      my $epstarttime = $vwst->findvalue( './/Episodes//Episode//Schedules//Schedule//StartTime' );
      my $epispremiere = $vwst->findvalue( './/Episodes//Episode//Schedules//Schedule//IsPremiere' );
      my $eplocalrating = $vwst->findvalue( './/Episodes//Episode//Schedules//Schedule//LocalRating' );

      progress("HBOAdria: $chd->{xmltvid}: $epstarttime - $title");

      my $ce = {
        channel_id => $chd->{id},
        title      => $title,
        start_time => $epstarttime,
      };

      $ce->{schedule_id} = $episodeid if ( $episodeid =~ /\S/ );

      if( $episodenumber gt 0 ){
        if( $season gt 0 ){
          $ce->{episode} = sprintf( "%d . %d .", $season - 1, $episodenumber - 1 );
        } else {
          $ce->{episode} = sprintf( ". %d .", $episodenumber - 1 );
        }
      }

      if( $epsynopsis and ( $epsynopsis !~ /[!! - SYNOPSIS_LEVEL - !!]/ ) ){
        $ce->{description} = $epsynopsis;
      }

      if( $epdirector and ( $epdirector !~ /[!! - CREDITS - !!] / ) ){
        $ce->{directors} = $epdirector;
      }

      if( $epcast and ( $epcast !~ /[!! - CREDITS - !!] / ) ){
        $ce->{actors} = $epcast;
      }

      if( $productiondate and ( $productiondate =~ /(\d\d\d\d)/ ) ){
        $ce->{production_date} = "$1-01-01";
      }

      $ce->{aspect} = "4:3";

      if( $epgenre1 =~ /\S/ ){
        my($program_type, $category ) = $ds->LookupCat( "AXN", $epgenre1 );
        AddCategory( $ce, $program_type, $category );
      }

      if( $epgenre2 =~ /\S/ ){
        my($program_type, $category ) = $ds->LookupCat( "AXN", $epgenre2 );
        AddCategory( $ce, $program_type, $category );
      }

      $ce->{rating} = $eplocalrating if ( $eplocalrating =~ /\S/ );

      QueryIMDB( $title, $ce );

      $dsh->AddProgramme( $ce );

    }

  }

  $dsh->EndBatch( 1 );

  return 1;
}

sub bytime {
  $$a{start_time} <=> $$b{start_time};
}

sub FlushData {
  my ( $dsh, $channel_id, $xmltvid, @data ) = @_;

  my $currdate = "x";

  if( @data ){

    # sort data by the start_time field
    my @sorteddata = sort bytime @data;

    foreach my $ce (@sorteddata) {

      my $date = $ce->{start_time}->ymd("-");
      my $time = $ce->{start_time}->hms(":");
      $time =~ s/:\d{2}$//; # strip seconds
      $ce->{start_time} = $time;

      if( $date ne $currdate ) {

        if( $currdate ne "x" ){
          # save last day if we have it in memory
          $dsh->EndBatch( 1 );
        }

        my $batch_id = "${xmltvid}_" . $date;
        $dsh->StartBatch( $batch_id, $channel_id );
        $dsh->StartDate( $date , "00:00" );
        $currdate = $date;

        progress("HBOAdria: $xmltvid: Date is $date");
      }

      progress("HBOAdria: $xmltvid: $ce->{start_time} - $ce->{title}");

      $dsh->AddProgramme( $ce );
    }
    $dsh->EndBatch( 1 );
  }
}

sub ParseDate
{
  my( $text ) = @_;

#print "$text\n";

  my( $monthname, $dayname, $month, $day, $year );

  # format: 'MONDAY 01 MARCH 2010'
  if( $text =~ /^\S+\s+\d+\s+\S+\s+\d+$/ ){
    ( $dayname, $day, $monthname, $year ) = ( $text =~ /^(\S+)\s+(\d+)\s+(\S+)\s+(\d+)$/ );
    $month = MonthNumber( $monthname, "en" );

  # format: '4-1-09'
  } elsif( $text =~ /^\d+-\d+-\d+$/ ){
    ( $month, $day, $year ) = ( $text =~ /^(\d+)-(\d+)-(\d+)$/ );
  }

  $year += 2000 if $year < 100;

  return sprintf( "%04d-%02d-%02d", $year, $month, $day );
}

sub ParseStartTime
{
  my( $starttime ) = @_;

#print "ParseStartTime >$starttime<\n";

  my( $year, $month, $day, $hour, $min, $sec, $ampm );

  # format '2009-03-10T11:20:00.0000000+01:00'
  if( $starttime =~ /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\./ ){
    ( $year, $month, $day, $hour, $min, $sec ) = ( $starttime =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})/ );

  # format '4/10/2009 8:55:00 PM'
  } elsif( $starttime =~ /^\d+\/\d+\/\d+\s+\d+:\d+:\d+\s+(AM|PM)$/i ){
    ( $month, $day, $year, $hour, $min, $sec, $ampm ) = ( $starttime =~ /^(\d+)\/(\d+)\/(\d+)\s+(\d+):(\d+):(\d+)\s+(AM|PM)$/ );

    $hour += 12 if( $ampm =~ /^PM$/i );
    if( $hour >= 24 ){
      $hour -= 24;
      $day += 1;
    }
  }

#print "D: $day\n";
#print "M: $month\n";
#print "Y: $year\n";
#print "h: $hour\n";
#print "m: $min\n";
#print "s: $sec\n";

  my $sdt = DateTime->new( year   => $year,
                           month  => $month,
                           day    => $day,
                           hour   => $hour,
                           minute => $min,
                           second => $sec,
                           time_zone => 'Europe/Zagreb',
  );

  return $sdt;
}

sub create_dt
{
  my( $ny , $nm , $nd , $st , $du ) = @_;

  if( not defined $nd )
  {
    return undef;
  }

  # start time
  my ( $hour , $minute ) = split( ":" , $st );

  my $sdt = DateTime->new( year   => $ny,
                           month  => $nm,
                           day    => $nd,
                           hour   => $hour,
                           minute => $minute,
                           second => 0,
                           time_zone => 'Europe/Zagreb',
                           );

  # times are in CET timezone in original file
  $sdt->set_time_zone( "UTC" );

  # end time
  $du =~ s/'//gi;
  my $edt = $sdt->clone->add( minutes => $du );

  return( $sdt, $edt );
}

sub QueryIMDB {
  my( $title , $ce ) = @_;

return;
  my $film = new IMDB::Film( crit => $title );
  if($film->status) {

    print "\n--------------------------\n";

    print "Title: ".$film->title()."\n";

    print "Kind: ".$film->kind()."\n";

    print "Year: ".$film->year()."\n";

    print "Connections: ".$film->connections()."\n";

    print "Companies: ".$film->full_companies()."\n";

    print "Company: ".$film->company()."\n";

#    foreach my $episode ( @{$film->episodes()} ){
#      print "Episode: $episode->{id} $episode->{title} $episode->{season} $episode->{episode} $episode->{date} $episode->{plot}\n";
#    }

#    foreach my $episodeof ( @{$film->episodeof()} ){
#      print "Episode: $episodeof->{id} $episodeof->{title} $episodeof->{year}\n";
#    }

    print "Cover: ".$film->cover()."\n";

    foreach my $director ( @{$film->directors()} ){
      print "Director: $director->{id} $director->{name}\n";
    }

    foreach my $writer ( @{$film->writers()} ){
      print "Writer: $writer->{id} $writer->{name}\n";
    }

    foreach my $genre ( @{$film->genres()} ){
      print "Genre: $genre\n";
    }

    print "Tagline: ".$film->tagline()."\n";

    print "Plot: ".$film->plot()."\n";

    print "Storyline: ".$film->storyline()."\n";

    print "Rating: ".$film->rating()."\n";

    foreach my $actor ( @{$film->cast()} ){
      print "Actor: $actor->{id} $actor->{name} $actor->{role}\n";
    }

    print "Duration: ".$film->duration()."\n";

    print "Country: ".$film->country()."\n";

    print "Langguage: ".$film->language()."\n";

    print "Aka: ".$film->also_known_as()."\n";

    print "Trivia: ".$film->trivia()."\n";

    print "Goofs: ".$film->goofs()."\n";

    print "Awards: ".$film->awards()."\n";

    print "MPAA: ".$film->mpaa_info()."\n";

    print "Aspect: ".$film->aspect_ratio()."\n";

    print "Summary: ".$film->summary()."\n";

    print "Certifications: ".$film->certifications()."\n";

    print "Full plot: ".$film->full_plot()."\n";

    foreach my $site ( @{$film->official_sites()} ){
      print "Site: $site->{title} $site->{url}\n";
    }

    foreach my $releasedate ( @{$film->release_dates()} ){
      print "Country: $releasedate->{country} $releasedate->{date} $releasedate->{info}\n";
    }

    print "--------------------------\n";

    if( $film->title() eq $title ){
print "OK ZA UPDATE !!!\n";
    }
  }

  return;
}

sub UpdateFiles {
  my( $self ) = @_;

return;
  # get current moment
  my $now = DateTime->today->ymd();

  # the url to fetch data from
  # is in the format http://www.hbo.hr/Download.aspx?Type=ME&ChanelId=HBO&DayFor=2007-10-06
  # UrlRoot = http://www.hbo.hr/Download.aspx
  # GrabberInfo = Type=ME&ChanelId=HBO

  foreach my $data ( @{$self->ListChannels()} ) {
    my $dir = $data->{grabber_info};
    my $xmltvid = $data->{xmltvid};

    my $url = $self->{UrlRoot} . "?Type=ME&" . $data->{grabber_info} . "&DayFor=" . $now;
    progress("HBOAdria: Fetching xls file from $url");

    my( $content, $code ) = MyGet( $url );

    my $filename = $now;
    my $filepath = $self->{FileStore} . '/' . $xmltvid . '/' . $filename . '.html';
    open (FILE,">$filepath");
    print FILE $content;
    close (FILE);

    progress("HBOAdria: Content saved to $filepath");
  }
}

1;
