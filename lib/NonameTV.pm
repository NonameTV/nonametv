package NonameTV;

use strict;
use warnings;

# Mark this source-file as encoded in utf-8.
use utf8;
use Env;

use Encode;
use File::Slurp;
use File::Temp qw/tempfile tempdir/;
use LWP::UserAgent;

use NonameTV::StringMatcher;
use NonameTV::Log qw/w/;
use XML::LibXML;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    # set the version for version checking
    $VERSION     = 0.3;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/MyGet expand_entities 
                      Html2Xml Htmlfile2Xml
                      Word2Xml Wordfile2Xml 
		      File2Xml Content2Xml
		      FindParagraphs
                      norm normLatin1 normUtf8 AddCategory
                      ParseDescCatSwe FixProgrammeData
		      ParseXml ParseXmltv ParseJson
                      MonthNumber DayNumber
                      CompareArrays
                     /;
}
our @EXPORT_OK;

my $wvhtml = 'wvHtml --charset=utf-8';
# my $wvhtml = '/usr/bin/wvHtml';

my $ua = LWP::UserAgent->new( agent => "nonametv (http://nonametv.org)", 
                              cookie_jar => {},
                              env_proxy => 1 );

# Fetch a url. Returns ($content, true) if data was fetched from server and
# different from the last time the same url was fetched, ($content, false) if
# it was fetched from the server and was the same as the last time it was
# fetched and (undef,$error_message) if there was an error fetching the data.
 
sub MyGet
{
  my( $url ) = @_;
  my $res = $ua->get( $url );
  
  if( $res->is_success )
  {
    return ($res->content, not defined( $res->header( 'X-Content-Unchanged' ) ) );
  }
  else
  {
    return (undef, $res->status_line );
  }
}

# åäö ÅÄÖ
my %ent = (
           257  => 'ä',
	   231  => 'c', # This should really be a c with a special mark on it.
	                # Unicode 000E7, UTF-8 195 167.
           337  => 'ö',
           8211 => '-',
           8212 => '--',
           8216 => "'",
           8217 => "'",
           8220 => '"',
           8221 => '"',
           8230 => '...',
           8364 => "(euro)",
           );

sub _expand
{
  my( $num, $str ) = @_;

  if( not defined( $ent{$num} ) )
  {
    $ent{$num} = "";
    print STDERR "Unknown entity $num in $str\n";
  }

  return $ent{$num};
}

sub expand_entities
{
  my( $str ) = @_;

  $str =~ s/\&#(\d+);/_expand($1,$str)/eg;

  return $str;
}

=item Html2Xml( $content )

Convert the HTML in $content into an XML::LibXML::Document.

Prints an error-message to STDERR and returns undef if the conversion
fails.

=cut

sub Html2Xml {
  my( $html ) = @_;

  my $xml = XML::LibXML->new;
  $xml->recover(1);
  
  # Remove character that makes the parser stop.
  $html =~ s/\x00//g;

  my $doc;
  eval { $doc = $xml->parse_html_string($html, {
    recover => 1,
    suppress_errors => 1,
    suppress_warnings => 1,
  }); };
  
  if( $@ ne "" ) {
    my ($package, $filename, $line) = caller;
    print "parse_html_string failed: $@ when called from $filename:$line\n";
    return undef;
  }

  return $doc;
}

=item Htmlfile2Xml( $filename )

Convert the HTML in a file into an XML::LibXML::Document.

Prints an error-message to STDERR and returns undef if the conversion
fails.

=cut

sub Htmlfile2Xml
{
  my( $filename ) = @_;

  my $html = read_file( $filename );

  return Html2Xml( $html );
}


=item Word2Xml( $content )

Convert the Microsoft Word document in $content into html and return
the html as an XML::LibXML::Document.

Prints an error-message to STDERR and returns undef if the conversion
fails.

=cut

sub Word2Xml
{
  my( $content ) = @_;
  
  my( $fh, $filename ) = tempfile();
  print $fh $content;
  close( $fh );

  my $doc = Wordfile2Xml( $filename );
  unlink( $filename );
  return $doc;
}

sub Wordfile2Xml
{
  my( $filename ) = @_;

  my $html = qx/$wvhtml "$filename" -/;
  if( $? )
  {
    w "$wvhtml $filename - failed: $?";
    return undef;
  }
  
  # Remove character that makes LibXML choke.
  $html =~ s/\&hellip;/.../g;
  
  return Html2Xml( $html );
}

sub File2Xml {
  my( $filename ) = @_;

  my $data = read_file( $filename );
  my $doc;
  if( $data =~ /^\<\!DOCTYPE HTML/ )
  {
    # This is an override that has already been run through wvHtml
    $doc = Html2Xml( $data );
  }
  else
  {
    $doc = Word2Xml( $data );
  }

  return $doc;
}

sub Content2Xml {
  my( $cref ) = @_;

  my $doc;
  if( $$cref =~ /^\<\!DOCTYPE HTML/ )
  {
    # This is an override that has already been run through wvHtml
    $doc = Html2Xml( $$cref );
  }
  else
  {
    $doc = Word2Xml( $$cref );
  }

  return $doc;
}

=pod

FindParagraphs( $doc, $expr )

Finds all paragraphs in the part of an xml-tree that matches an 
xpath-expression. Returns a reference to an array of strings.
All paragraphs are normalized and empty strings are removed from the
array.

Both <div> and <br> are taken into account when splitting the document
into paragraphs.

Use the expression '//body//.' for html-documents when you want to see
all paragraphs in the page.

=cut 

my %paraelem = (
		p => 1,
		br => 1,
		div => 1,
		td => 1,
		);

sub FindParagraphs {
  my( $doc, $elements ) = @_;

  my $ns = $doc->find( $elements );

  my @paragraphs;
  my $p = "";

  foreach my $node ($ns->get_nodelist()) {
    if( $node->nodeName eq "#text" ) {
      $p .= $node->textContent();
    }
    elsif( defined $paraelem{ $node->nodeName } ) {
      $p = norm( $p );
      if( $p ne "" ) {
	push @paragraphs, $p;
	$p = "";
      }
    }
  }

  return \@paragraphs;
}


# Remove any strange quotation marks and other syntactic marks
# that we don't want to have. Remove leading and trailing space as well
# multiple whitespace characters.
# Returns the empty string if called with an undef string.
sub norm
{
  my( $str ) = @_;

  return "" if not defined( $str );

# Uncomment the code below and change the regexp to learn which
# character code perl thinks a certain character has.
# These codes can be used in \x{YY} expressions as shown below.
#  if( $str =~ /unique string/ ) {
#    for( my $i=0; $i < length( $str ); $i++ ) {
#      printf( "%2x: %s\n", ord( substr( $str, $i, 1 ) ), 
#               substr( $str, $i, 1 ) ); 
#    }
#  }

  $str = expand_entities( $str );
  
  $str =~ tr/\x{96}\x{93}\x{94}/-""/; #
  $str =~ tr/\x{201d}\x{201c}/""/;
  $str =~ tr/\x{2022}/*/; # Bullet
  $str =~ tr/\x{2013}\x{2018}\x{2019}/-''/;
  $str =~ tr/\x{017c}\x{0144}\x{0105}/zna/;
  $str =~ s/\x{85}/... /g;
  $str =~ s/\x{2026}/.../sg;
  $str =~ s/\x{2007}/ /sg;

  $str =~ s/^\s+//;
  $str =~ s/\s+$//;
  $str =~ tr/\n\r\t /    /s;
  
  return $str;
}

#
# fixup utf8 with the microsoft variant of latin1 instead of iso-8859-1 in the lower 256 code points
#
# see http://en.wikipedia.org/wiki/Windows-1252
#
sub normLatin1
{
  my( $str ) = @_;

  return undef if not defined( $str );

  $str =~ tr/\x{80}\x{82}\x{83}\x{84}\x{85}\x{86}\x{87}\x{88}\x{89}\x{8a}\x{8b}\x{8c}\x{8e}\x{91}\x{92}\x{93}\x{94}\x{95}\x{96}\x{97}\x{98}\x{99}\x{9a}\x{9b}\x{9c}\x{9e}\x{9f}/\x{20ac}\x{201a}\x{0192}\x{201e}\x{2026}\x{2020}\x{2021}\x{02c6}\x{2030}\x{0160}\x{2039}\x{0152}\x{017d}\x{2018}\x{2019}\x{201c}\x{201d}\x{2022}\x{2012}\x{2014}\x{02dc}\x{2122}\x{0161}\x{203a}\x{0153}\x{017e}\x{0178}/; #

  return $str;
}

#
# fixup utf8 encoded twice
#
sub normUtf8
{
  my( $str ) = @_;

  return undef if not defined( $str );

  # we have got a string of perl characters
  $str = encode('utf-8', $str);

  $str =~ s|([\x{C3}][\x{82}-\x{83}][\x{C2}][\x{80}-\x{BF}])|encode('iso-8859-1', decode('utf-8', $1) )|eg;

  # it should still be a string of perl characters
  $str = decode('utf-8', $str);

  return $str;
}

=item AddCategory

Add program_type and category to an entry if the entry does not already
have a program_type and category. 

AddCategory( $ce, $program_type, $category );

=cut

sub AddCategory
{
  my( $ce, $program_type, $category ) = @_;

  if( not defined( $ce->{program_type} ) and defined( $program_type )
      and ( $program_type =~ /\S/ ) )
  {
    $ce->{program_type} = $program_type;
  }

  if( not defined( $ce->{category} ) and defined( $category ) 
      and ( $category =~ /\S/ ) )
  {
    $ce->{category} = $category;
  }
}

=item ParseDescCatSwe

Parse a program description in Swedish and return program_type
and category that can be deduced from the description.

  my( $pty, $cat ) = ParseDescCatSwe( "Amerikansk äventyrsserie" );

=cut

my $sm = NonameTV::StringMatcher->new();
$sm->AddRegexp( qr/kriminalserie/i,      [ 'series', 'Crime/Mystery' ] );
$sm->AddRegexp( qr/deckarserie/i,        [ 'series', 'Crime/Mystery' ] );
$sm->AddRegexp( qr/polisserie/i,         [ 'series', 'Crime/Mystery' ] );
$sm->AddRegexp( qr/familjeserie/i,       [ 'series', 'Family' ] );
$sm->AddRegexp( qr/tecknad serie/i,      [ 'series', 'Animated' ] );
$sm->AddRegexp( qr/animerad serie/i,     [ 'series', 'Animated' ] );
$sm->AddRegexp( qr/dramakomediserie/i,   [ 'series', 'Comedy' ] );
$sm->AddRegexp( qr/dramaserie/i,         [ 'series', 'Drama' ] );
$sm->AddRegexp( qr/resedokumentärserie/i,[ 'series', 'Food/Travel' ] );
$sm->AddRegexp( qr/komediserie/i,        [ 'series', 'Comedy' ] );
$sm->AddRegexp( qr/realityserie/i,       [ 'series', 'Reality' ] );
$sm->AddRegexp( qr/realityshow/i,        [ 'series', 'Reality' ] );
$sm->AddRegexp( qr/dokusåpa/i,           [ 'series', 'Reality' ] );
$sm->AddRegexp( qr/actiondramaserie/i,   [ 'series', 'Action' ] );
$sm->AddRegexp( qr/actionserie/i,        [ 'series', 'Action' ] );
$sm->AddRegexp( qr/underhållningsserie/i,[ 'series', undef ] );
$sm->AddRegexp( qr/äventyrsserie/i,      [ 'series', 'Action/Adv' ] );
$sm->AddRegexp( qr/äventyrskomediserie/i,[ 'series', 'Comedy' ] );
$sm->AddRegexp( qr/dokumentär(serie|program)/i,    [ 'series', 'Documentary' ] );
$sm->AddRegexp( qr/dramadokumentär/i,    [ undef,    'Documentary' ] );

$sm->AddRegexp( qr/barnserie/i,          [ 'series', "Children's" ] );
$sm->AddRegexp( qr/matlagningsserie/i,   [ 'series', 'Cooking' ] );
$sm->AddRegexp( qr/motorserie/i,         [ 'series', 'sports' ] );
$sm->AddRegexp( qr/fixarserie/i,         [ 'series', "Home/How-to" ] );
$sm->AddRegexp( qr/science[-\s]*fiction[-\s]*serie/i, 
                [ 'series', 'SciFi' ] );
$sm->AddRegexp( qr/barnprogram/i,          [ undef, "Children's" ] );


# Kanal 5 new
$sm->AddRegexp( qr/livsstilsserie/i,          [ 'series', 'Lifestyle' ] );
$sm->AddRegexp( qr/dramathrillerserie/i,      [ 'series', 'Drama/Thriller' ] );
$sm->AddRegexp( qr/fantasydramaserie/i,       [ 'series', 'Fantasy/Drama' ] );
$sm->AddRegexp( qr/tävlingsserie/i,           [ 'series', 'Contest' ] );
$sm->AddRegexp( qr/inredningsserie/i,         [ 'series', 'Home/How-to' ] );
$sm->AddRegexp( qr/frågesport/i,        			[ 'series', 'Quiz' ] );
$sm->AddRegexp( qr/sci[-\s]*fiserie/i, 				[ 'series', 'SciFi' ] );
$sm->AddRegexp( qr/nöjesprogram/i, 						[ 'series', 'Entertainment' ] );
$sm->AddRegexp( qr/talkshow/i,         				[ 'series', 'Talk' ] );
$sm->AddRegexp( qr/relationsserie/i,         	[ 'series', 'Relationship' ] );
$sm->AddRegexp( qr/actionthrillerserie/i,     [ 'series', 'Action/Thriller' ] );
$sm->AddRegexp( qr/kriminalkomediserie/i,     [ 'series', 'Crime/Comedy' ] );
$sm->AddRegexp( qr/intervjuserie/i,     			[ 'series', 'Talk' ] );

# If has *film in name set it as movie.
#$sm->AddRegexp( qr/\b\s*film\b/i,        					[ 'movie', "Movies" ] );

# Movies
$sm->AddRegexp( qr/\b(familje|drama|action)*komedi\b/i,  [ 'movie', "Comedy" ] );

$sm->AddRegexp( qr/\b(krigs|kriminal)*drama\b/i,  [ 'movie', "Drama" ] );

$sm->AddRegexp( qr/\baction(drama|film)*\b/i,     [ 'movie', "Action/Adv" ] );

$sm->AddRegexp( qr/\b.ventyrsdrama\b/i,           [ 'movie', "Action/Adv" ] );

$sm->AddRegexp( qr/\bv.stern(film)*\b/i,          [ 'movie', undef ] );

$sm->AddRegexp( qr/\b(drama)*thriller\b/i,        [ 'movie', "Crime" ] );

$sm->AddRegexp( qr/\bscience\s*fiction(rysare)*\b/i, [ 'movie', "SciFi" ] );

$sm->AddRegexp( qr/\b(l.ng)*film\b/i,             [ 'movie', undef ] );

$sm->AddRegexp( qr/\bbollywoodfilm\b/i,             [ 'movie', "Bollywood" ] );

# Kanal 5
$sm->AddRegexp( qr/\bkomedifilm\b/i,             [ 'movie', "Comedy" ] );
$sm->AddRegexp( qr/\banimerad komedifilm\b/i,    [ 'movie', "Animated/Comedy" ] );
$sm->AddRegexp( qr/\bthrillerfilm\b/i,    			 [ 'movie', "Thriller" ] );
$sm->AddRegexp( qr/\bdramafilm\b/i,        			 [ 'movie', "Drama" ] );
$sm->AddRegexp( qr/\bactionthrillerfilm\b/i,     [ 'movie', "Action/Thriller" ] );
$sm->AddRegexp( qr/\bkriminaldramafilm\b/i,      [ 'movie', "Crime/Drama" ] );
$sm->AddRegexp( qr/\bdramathrillerfilm\b/i,        [ 'movie', "Crime" ] );



sub ParseDescCatSwe
{
  my( $desc ) = @_;

  return (undef, undef) if not defined $desc;

  my $res = $sm->Match( $desc );
  if( defined( $res ) ) 
  {
    return @{$res};
  }
  else
  {
    return (undef,undef);
  }
}

sub FixProgrammeData
{
  my( $d ) = @_;

  $d->{title} =~ s/^s.songs+tart\s*:*\s*//gi;
  $d->{title} =~ s/^seriestart\s*:*\s*//gi;
  $d->{title} =~ s/^reprisstart\s*:*\s*//gi;
  $d->{title} =~ s/^programstart\s*:*\s*//gi;

  $d->{title} =~ s/^s.songs*avslutning\s*:*\s*//gi;
  $d->{title} =~ s/^sista\s+delen\s*:*\s*//gi;
  $d->{title} =~ s/^sista\s+avsnittet\s*:*\s*//gi;

  if( $d->{title} =~ s/^((matin.)|(fredagsbio))\s*:\s*//gi )
  {
    $d->{program_type} = 'movie';
    $d->{category} = 'Movies';
  }

  # Set program_type to series if the entry has an episode-number
  # with a defined episode (i.e. second part),
  # but doesn't have a program_type.
  if( exists( $d->{episode} ) and defined( $d->{episode} ) and
      ($d->{episode} !~ /^\s*\.\s*\./) and 
      ( (not defined($d->{program_type})) or ($d->{program_type} =~ /^\s*$/) ) )
  {
    $d->{program_type} = "series";
  }
}

=pod 

my $doc = ParseXml( $strref );

Parse an xml-string into an XML::LibXML document. Takes a reference to a
string as the only reference.

=cut

my $xml;

sub ParseXml {
  my( $cref ) = @_;

  if( not defined $xml ) {
    $xml = XML::LibXML->new;
    $xml->load_ext_dtd(0);
  }
  
  my $doc;
  eval { 
    $doc = $xml->parse_string($$cref); 
  };
  if( $@ )   {
    w "Failed to parse xml: $@";
    return undef;
  }

  return $doc;
}

=pod 

my $doc = ParseJson( $strref );

Parse an json-string

=cut

my $json;

sub ParseJson {
  my( $cref ) = @_;

  if( not defined $json ) {
    $json = new JSON;
  }
  
  my $doc;
  eval { 
    $doc = $json->allow_nonref->utf8->relaxed->escape_slash->loose->allow_singlequote->allow_barekey->decode($$cref); 
  };
  if( $@ )   {
    w "Failed to parse json: $@";
    return undef;
  }

  return $doc;
}

=pod

Parse a reference to an xml-string in xmltv-format into a reference to an 
array of hashes with programme-info.

=cut

sub ParseXmltv {
  my( $cref, $channel ) = @_;

  my $doc = ParseXml( $cref );
  return undef if not defined $doc;

  my @d;

  # Find all "programme"-entries for $channel or all channels.
  my $filter = "//programme";
  if ($channel) {
    $filter .= '[@channel="' . $channel . '"]';
  }
  my $ns = $doc->find( $filter );
  if( $ns->size() == 0 ) {
    return;
  }
  
  foreach my $pgm ($ns->get_nodelist) {
    my $start = $pgm->findvalue( '@start' );
    my $start_dt = create_dt( $start );

    my $stop = $pgm->findvalue( '@stop' );
    my $stop_dt = create_dt( $stop ) if $stop;

    my $title = $pgm->findvalue( 'title' );
    my $subtitle = $pgm->findvalue( 'sub-title' );
    
    my $desc = $pgm->findvalue( 'desc' );
    my $cat1 = $pgm->findvalue( 'category[1]' );
    my $cat2 = $pgm->findvalue( 'category[2]' );
    my $episode = $pgm->findvalue( 'episode-num[@system="xmltv_ns"]' );
    my $production_date = $pgm->findvalue( 'date' );
    my $url = $pgm->findvalue( 'url' );

    my $aspect = $pgm->findvalue( 'video/aspect' );
    my $quality = $pgm->findvalue( 'video/quality' );

    my $stereo = $pgm->findvalue( 'audio/stereo' );

    my @directors;
    $ns = $pgm->find( ".//director" );
    foreach my $dir ($ns->get_nodelist) {
      push @directors, $dir->findvalue(".");
    }
    
    my @actors;
    my $ns = $pgm->find( ".//actor" );
    foreach my $act ($ns->get_nodelist) {
      push @actors, $act->findvalue(".");
    }

    my @writers;
    $ns = $pgm->find( ".//writer" );
    foreach my $dir ($ns->get_nodelist) {
      push @writers, $dir->findvalue(".");
    }

    my @adapters;
    $ns = $pgm->find( ".//adapter" );
    foreach my $dir ($ns->get_nodelist) {
      push @adapters, $dir->findvalue(".");
    }
    
    my @producers;
    $ns = $pgm->find( ".//producer" );
    foreach my $dir ($ns->get_nodelist) {
      push @producers, $dir->findvalue(".");
    }
    
    my @composers;
    $ns = $pgm->find( ".//composer" );
    foreach my $dir ($ns->get_nodelist) {
      push @composers, $dir->findvalue(".");
    }
    
    my @editors;
    $ns = $pgm->find( ".//editor" );
    foreach my $dir ($ns->get_nodelist) {
      push @editors, $dir->findvalue(".");
    }
    
    my @presenters;
    $ns = $pgm->find( ".//presenter" );
    foreach my $dir ($ns->get_nodelist) {
      push @presenters, $dir->findvalue(".");
    }
    
    my @commentators;
    $ns = $pgm->find( ".//commentator" );
    foreach my $dir ($ns->get_nodelist) {
      push @commentators, $dir->findvalue(".");
    }
    
    my @guests;
    $ns = $pgm->find( ".//guest" );
    foreach my $dir ($ns->get_nodelist) {
      push @guests, $dir->findvalue(".");
    }
    
    my %e = (
      start_dt => $start_dt,
      title => $title,
      description => $desc,
    );

    if( $stop =~ /\S/ ) {
      $e{stop_dt} = $stop_dt;
    }

    if( $subtitle =~ /\S/ ) {
      $e{subtitle} = $subtitle;
    }

    if( $episode =~ /\S/ ) {
      $e{episode} = $episode;
    }

    if( $url =~ /\S/ ) {
      $e{url} = $url;
    }

    if( $cat1 =~ /^[a-z]/ ) {
      $e{program_type} = $cat1;
    }
    elsif( $cat1 =~ /^[A-Z]/ ) {
      $e{category} = $cat1;
    }

    if( $cat2 =~ /^[a-z]/ ) {
      $e{program_type} = $cat2;
    }
    elsif( $cat2 =~ /^[A-Z]/ ) {
      $e{category} = $cat2;
    }

    if( $production_date =~ /\S/ ) {
      $e{production_date} = "$production_date-01-01";
    }

    if( $aspect =~ /\S/ ) {
      $e{aspect} = $aspect;
    }

    if( $quality =~ /\S/ ) {
      $e{quality} = $quality;
    }

    if( $stereo =~ /\S/ ) {
      $e{stereo} = $stereo;
    }

    if( scalar( @directors ) > 0 ) {
      $e{directors} = join ", ", @directors;
    }

    if( scalar( @actors ) > 0 ) {
      $e{actors} = join ", ", @actors;
    }
    
    if( scalar( @writers ) > 0 ) {
      $e{writers} = join ", ", @writers;
    }
    
    if( scalar( @adapters ) > 0 ) {
      $e{adapters} = join ", ", @adapters;
    }
    
    if( scalar( @producers ) > 0 ) {
      $e{producers} = join ", ", @producers;
    }
    
    if( scalar( @composers ) > 0 ) {
      $e{composers} = join ", ", @composers;
    }
    
    if( scalar( @editors ) > 0 ) {
      $e{editors} = join ", ", @editors;
    }
    
    if( scalar( @presenters ) > 0 ) {
      $e{presenters} = join ", ", @presenters;
    }
    
    if( scalar( @commentators ) > 0 ) {
      $e{commentators} = join ", ", @commentators;
    }
    
    if( scalar( @guests ) > 0 ) {
      $e{guests} = join ", ", @guests;
    }
    
    push @d, \%e;
  }

  return \@d;
}

sub create_dt
{
  my( $datetime ) = @_;

  my( $year, $month, $day, $hour, $minute, $second, $tz ) = 
    ($datetime =~ /(\d{4})(\d{2})(\d{2})
                   (\d{2})(\d{2})(\d{2})\s+
                   (\S+)$/x);
  
  my $dt = DateTime->new( 
                          year => $year,
                          month => $month, 
                          day => $day,
                          hour => $hour,
                          minute => $minute,
                          second => $second,
                          time_zone => $tz 
                          );
  
  return $dt;
}

=pod

Convert month name to month number

=cut

sub MonthNumber {
  my( $monthname , $lang ) = @_;

  my( @months_1, @months_2, @months_3, @months_4, @months_5, @months_6, @months_7, @months_8 );

  if( $lang =~ /^en$/ ){
    @months_1 = qw/jan feb mar apr may jun jul aug sep oct nov dec/;
    @months_2 = qw/janu febr marc apr may june july augu sept octo nov dec/;
    @months_3 = qw/january february march april may june july august september october november december/;
    @months_4 = qw/Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec/;
    @months_5 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_6 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_7 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_8 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
  } elsif( $lang =~ /^de$/ ){
    @months_1 = qw/jan feb mar apr may jun jul aug sep oct nov dec/;
    @months_2 = qw/Januar Februar März April Mai Juni Juli August September Oktober November Dezember/;
    @months_3 = qw/Januar Februar Mä April Mai Juni Juli August September Oktober November Dezember/;
    @months_4 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_5 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_6 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_7 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_8 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
  } elsif( $lang =~ /^hr$/ ){
    @months_1 = qw/sij vel ozu tra svi lip srp kol ruj lis stu pro/;
    @months_2 = qw/sijecanj veljaca ozujak travanj svibanj lipanj srpanj kolovoz rujan listopad studeni prosinac/;
    @months_3 = qw/sijecnja veljače ozujka travnja svibnja lipnja srpnja kolovoza rujna listopada studenoga prosinca/;
    @months_4 = qw/sijeÃ¨a veljače ožujka travnja svibnja lipnja srpnja kolovoza rujna listopada studenog prosinca/;
    @months_5 = qw/januar februar mart april maj juni juli august septembar oktobar novembar decembar/;
    @months_6 = qw/siječanj veljace ozujka travnja svibnja lipnja srpnja kolovoza rujna listopada studenog prosinca/;
    @months_7 = qw/jan feb mar apr maj jun jul aug sep okt nov dec/;
    @months_8 = qw/siječnja feb mar apr maj jun jul aug sep okt nov dec/;
  } elsif( $lang =~ /^sr$/ ){
    @months_1 = qw/jan feb mar apr maj jun jul aug sep okt nov dec/;
    @months_2 = qw/januar februar mart april maj jun juli avgust septembar oktobar novembar decembar/;
    @months_3 = qw/januara februara marta aprila maja juna jula avgusta septembra oktobra novembra decembra/;
    @months_4 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_5 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_6 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_7 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_8 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
  } elsif( $lang =~ /^it$/ ){
    @months_1 = qw/gen feb mar apr mag giu lug ago set ott nov dic/;
    @months_2 = qw/gennaio febbraio marzo aprile maggio giugno luglio agosto settembre ottobre novembre dicembre/;
    @months_3 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_4 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_5 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_6 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_7 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_8 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
  } elsif( $lang =~ /^fr$/ ){
    @months_1 = qw/jan fav mar avr mai jui jul aou sep oct nov dec/;
    @months_2 = qw/JANVIER FÉVRIER mars avril mai juin juillet Août septembre octobre novembre DÉCEMBRE/;
    @months_3 = qw/janvier favrier mMARS AVRIL MAI JUIN juillet AOÛT septembre octobre novembre DÉCEMBRE/;
    @months_4 = qw/1 Février 3 4 5 6 7 8 9 10 11 12/;
    @months_5 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_6 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_7 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_8 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
  } elsif( $lang =~ /^ru$/ ){
    @months_1 = qw/jan fav mar aprelja maja jui jul aou sep oct nov dec/;
    @months_2 = qw/JANVIER FÉVRIER mars avril mai juin juillet aout septembre octobre novembre DÉCEMBRE/;
    @months_3 = qw/janvier favrier mars avril mai juin juillet aout septembre octobre novembre DÉCEMBRE/;
    @months_4 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_5 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_6 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_7 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_8 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
  } elsif( $lang =~ /^sv$/ ){
    @months_1 = qw/jan feb mar apr maj jun jul aug sep okt nov dec/;
    @months_2 = qw/januari februari mars april maj juni juli augusti september oktober november december/;
    @months_3 = qw/jan feb mar apr maj jun jul aug sept okt nov dec/;
    @months_4 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_5 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_6 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_7 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_8 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
  }

  my %monthnames = ();

  for( my $i = 0; $i < scalar(@months_1); $i++ ){
    $monthnames{$months_1[$i]} = $i+1;
  }

  for( my $i = 0; $i < scalar(@months_2); $i++ ){
    $monthnames{$months_2[$i]} = $i+1;
  }

  for( my $i = 0; $i < scalar(@months_3); $i++ ){
    $monthnames{$months_3[$i]} = $i+1;
  }

  for( my $i = 0; $i < scalar(@months_4); $i++ ){
    $monthnames{$months_4[$i]} = $i+1;
  }

  for( my $i = 0; $i < scalar(@months_5); $i++ ){
    $monthnames{$months_5[$i]} = $i+1;
  }

  for( my $i = 0; $i < scalar(@months_6); $i++ ){
    $monthnames{$months_6[$i]} = $i+1;
  }

  for( my $i = 0; $i < scalar(@months_7); $i++ ){
    $monthnames{$months_7[$i]} = $i+1;
  }

  for( my $i = 0; $i < scalar(@months_8); $i++ ){
    $monthnames{$months_8[$i]} = $i+1;
  }

  my $month = $monthnames{$monthname};
  my $lcmonth = $monthnames{lc $monthname};

  return $month||$lcmonth;
}

=pod

Convert day name to day number

=cut

sub DayNumber {
  my( $dayname , $lang ) = @_;

  my( @days_1, @days_2 );

  if( $lang =~ /^en$/ ){
    @days_1 = qw/Monday Tuesday Wednesday Thursday Friday Saturday Sunday/;
    @days_2 = qw/0 1 2 3 4 5 6/;
  }

  my %daynames = ();

  for( my $i = 0; $i < scalar(@days_1); $i++ ){
    $daynames{$days_1[$i]} = $i+1;
  }

  for( my $i = 0; $i < scalar(@days_2); $i++ ){
    $daynames{$days_2[$i]} = $i+1;
  }

  my $day = $daynames{$dayname};
  my $lcday = $daynames{lc $dayname};

  return $day||$lcday;
}

=begin nd

Function: CompareArrays

Compare two arrays (new and old) and call functions to reflect added,
deleted and unchanged entries.

Parameters:

  $new - A reference to the new array
  $old - A reference to the old array
  $cb - A hashref with callback functions

CompareArrays calls the following callback functions:

  $cb->{cmp}( $enew, $eold ) - Compare an entry from $new with an
                           entry from $old.  Shall return -1 if $ea is
                           less than $eb, 0 if they are equal and 1
                           otherwise.

  $cb->{added}($enew) - Called for all entries that are present in
                      $new but not in $old.

  $cb->{deleted}($eold) - Called for all entries that are present in
                        $old but not in $new.

  $cb->{equal}($enew, $eold) - Called for all entries that are present in
                           both $new and $old.

Additionally, $cb->{max} shall contain an entry that is always
regarded as greater than any possible entry in $new and $old.

Returns:

  nothing

=cut

sub CompareArrays #( $new, $old, $cb )
{
  my( $new, $old, $cb ) = @_;

  my @a = sort { $cb->{cmp}( $a, $b ) } @{$new};
  my @b = sort { $cb->{cmp}( $a, $b ) } @{$old};
  
  push @a, $cb->{max};
  push @b, $cb->{max};

  my $ia = 0;
  my $ib = 0;

  while( 1 ) {
    my $da = $a[$ia];
    my $db = $b[$ib];

    # If both arrays have reached the end, we are done.
    if( ($cb->{cmp}($da, $cb->{max}) == 0) and 
        ($cb->{cmp}($db, $cb->{max}) == 0 ) ) {
      last;
    }

    my $cmp = $cb->{cmp}($da, $db);

    if( $cmp == 0 ) { 
      $cb->{equal}($da, $db);
      $ia++;
      $ib++;
    }
    elsif( $cmp < 0 ) {
      $cb->{added}( $da );
      $ia++;
    }
    else {
      $cb->{deleted}($db);
      $ib++;
    }
  }
}
  
1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
