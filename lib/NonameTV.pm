package NonameTV;

use strict;
use warnings;

# Mark this source-file as encoded in utf-8.
use utf8;
use Env;

use LWP::UserAgent;
use File::Temp qw/tempfile tempdir/;
use File::Slurp;

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
                      norm AddCategory
                      ParseDescCatSwe FixProgrammeData
		      ParseXml ParseXmltv
                      MonthNumber
                      CompareArrays
                     /;
}
our @EXPORT_OK;

my $wvhtml = '/usr/bin/wvHtml --charset=utf8';
# my $wvhtml = '/usr/bin/wvHtml';

my $ua = LWP::UserAgent->new( agent => "Grabber from http://tv.swedb.se", 
                              cookie_jar => {} );

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
$sm->AddRegexp( qr/familjeserie/i,       [ 'series', undef ] );
$sm->AddRegexp( qr/tecknad serie/i,      [ 'series', undef ] );
$sm->AddRegexp( qr/animerad serie/i,     [ 'series', undef ] );
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
$sm->AddRegexp( qr/dokumentärserie/i,    [ 'series', 'Documentary' ] );
$sm->AddRegexp( qr/dramadokumentär/i,    [ undef,    'Documentary' ] );

$sm->AddRegexp( qr/barnserie/i,          [ 'series', "Children's" ] );
$sm->AddRegexp( qr/matlagningsserie/i,   [ 'series', 'Cooking' ] );
$sm->AddRegexp( qr/motorserie/i,         [ 'series', undef ] );
$sm->AddRegexp( qr/fixarserie/i,         [ 'series', "Home/How-to" ] );
$sm->AddRegexp( qr/science[-\s]*fiction[-\s]*serie/i, 
                [ 'series', 'SciFi' ] );
$sm->AddRegexp( qr/barnprogram/i,          [ undef, "Children's" ] );

# Movies
$sm->AddRegexp( qr/\b(familje|drama|action)*komedi\b/i,  [ 'movie', "Comedy" ] );

$sm->AddRegexp( qr/\b(krigs|kriminal)*drama\b/i,  [ 'movie', "Drama" ] );

$sm->AddRegexp( qr/\baction(drama|film)*\b/i,     [ 'movie', "Action/Adv" ] );

$sm->AddRegexp( qr/\b.ventyrsdrama\b/i,           [ 'movie', "Action/Adv" ] );

$sm->AddRegexp( qr/\bv.stern(film)*\b/i,          [ 'movie', undef ] );

$sm->AddRegexp( qr/\b(drama)*thriller\b/i,        [ 'movie', "Crime" ] );

$sm->AddRegexp( qr/\bscience\s*fiction(rysare)*\b/i, [ 'movie', "SciFi" ] );

$sm->AddRegexp( qr/\b(l.ng)*film\b/i,             [ 'movie', undef ] );


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
  if( $@ ne "" )   {
    w "Failed to parse xml: $@";
    return undef;
  }

  return $doc;
}

=pod

Parse a reference to an xml-string in xmltv-format into a reference to an 
array of hashes with programme-info.

=cut

sub ParseXmltv {
  my( $cref ) = @_;

  my $doc = ParseXml( $cref );
  return undef if not defined $doc;

  my @d;

  # Find all "programme"-entries.
  my $ns = $doc->find( "//programme" );
  if( $ns->size() == 0 ) {
    return;
  }
  
  foreach my $pgm ($ns->get_nodelist) {
    my $start = $pgm->findvalue( '@start' );
    my $start_dt = create_dt( $start );

    my $stop = $pgm->findvalue( '@stop' );
    my $stop_dt = create_dt( $stop );

    my $title = $pgm->findvalue( 'title' );
    my $subtitle = $pgm->findvalue( 'sub-title' );
    
    my $desc = $pgm->findvalue( 'desc' );
    my $cat1 = $pgm->findvalue( 'category[1]' );
    my $cat2 = $pgm->findvalue( 'category[2]' );
    my $episode = $pgm->findvalue( 'episode-num[@system="xmltv_ns"]' );
    my $production_date = $pgm->findvalue( 'date' );
    my $url = $pgm->findvalue( 'url' );

    my $aspect = $pgm->findvalue( 'video/aspect' );

    my @actors;
    my $ns = $pgm->find( ".//actor" );

    foreach my $act ($ns->get_nodelist) {
      push @actors, $act->findvalue(".");
    }

    my @directors;
    $ns = $pgm->find( ".//director" );

    foreach my $dir ($ns->get_nodelist) {
      push @directors, $dir->findvalue(".");
    }
    
    my %e = (
      start_dt => $start_dt,
      stop_dt => $stop_dt,
      title => $title,
      description => $desc,
    );

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

    if( scalar( @directors ) > 0 ) {
      $e{directors} = join ", ", @directors;
    }

    if( scalar( @actors ) > 0 ) {
      $e{actors} = join ", ", @actors;
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

  my( @months_1, @months_2, @months_3, @months_4, @months_5, @months_6 );

  if( $lang =~ /^en$/ ){
    @months_1 = qw/jan feb mar apr may jun jul aug sep oct nov dec/;
    @months_2 = qw/janu febr marc apr may june july augu sept octo nov dec/;
    @months_3 = qw/january february march april may june july august september october november december/;
    @months_4 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_5 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_6 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
  } elsif( $lang =~ /^de$/ ){
    @months_1 = qw/jan feb mar apr may jun jul aug sep oct nov dec/;
    @months_2 = qw/Januar Februar März April Mai Juni Juli August September Oktober November Dezember/;
    @months_3 = qw/Januar Februar Mä April Mai Juni Juli August September Oktober November Dezember/;
    @months_4 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_5 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_6 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
  } elsif( $lang =~ /^hr$/ ){
    @months_1 = qw/sij vel ozu tra svi lip srp kol ruj lis stu pro/;
    @months_2 = qw/sijecanj veljaca ozujak travanj svibanj lipanj srpanj kolovoz rujan listopad studeni prosinac/;
    @months_3 = qw/sijecnja veljače ozujka travnja svibnja lipnja srpnja kolovoza rujna listopada studenoga prosinca/;
    @months_4 = qw/sijeÃ¨a veljače ožujka travnja svibnja lipnja srpnja kolovoza rujna listopada studenog prosinca/;
    @months_5 = qw/siječnja veljace ozujka travnja svibnja lipnja srpnja kolovoza rujna listopada studenog prosinca/;
    @months_6 = qw/siječanj veljace ozujka travnja svibnja lipnja srpnja kolovoza rujna listopada studenog prosinca/;
  } elsif( $lang =~ /^sr$/ ){
    @months_1 = qw/jan feb mar apr maj jun jul aug sep okt nov dec/;
    @months_2 = qw/januar februar mart april maj jun juli avgust septembar oktobar novembar decembar/;
    @months_3 = qw/januara februara marta aprila maja juna jula avgusta septembra oktobra novembra decembra/;
    @months_4 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_5 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_6 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
  } elsif( $lang =~ /^it$/ ){
    @months_1 = qw/gen feb mar apr mag giu lug ago set ott nov dic/;
    @months_2 = qw/gennaio febbraio marzo aprile maggio giugno luglio agosto settembre ottobre novembre dicembre/;
    @months_3 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_4 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_5 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_6 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
  } elsif( $lang =~ /^fr$/ ){
    @months_1 = qw/jan fav mar avr mai jui jul aou sep oct nov dec/;
    @months_2 = qw/JANVIER FÉVRIER mars avril mai juin juillet Août septembre octobre novembre DÉCEMBRE/;
    @months_3 = qw/janvier favrier mMARS AVRIL MAI JUIN juillet AOÛT septembre octobre novembre DÉCEMBRE/;
    @months_4 = qw/1 Février 3 4 5 6 7 8 9 10 11 12/;
    @months_5 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_6 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
  } elsif( $lang =~ /^ru$/ ){
    @months_1 = qw/jan fav mar aprelja maja jui jul aou
 sep oct nov dec/;
    @months_2 = qw/JANVIER FÉVRIER mars avril mai juin juillet aout septembre octobre novembre DÉCEMBRE/;
    @months_3 = qw/janvier favrier mars avril mai juin juillet aout septembre octobre novembre DÉCEMBRE/;
    @months_4 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_5 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
    @months_6 = qw/1 2 3 4 5 6 7 8 9 10 11 12/;
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

  my $month = $monthnames{$monthname};
  my $lcmonth = $monthnames{lc $monthname};

  return $month||$lcmonth;
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
