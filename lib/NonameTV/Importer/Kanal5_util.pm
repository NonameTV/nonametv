package NonameTV::Importer::Kanal5_util;

use strict;
use warnings;

=pod

Importer for Kanal5's Word-format.
Data is downloaded in one file per week. The file is in Microsoft Word-
format. There is no consistent markup used for describing the data. The
parsing is done by iterating over each <div> in the resulting html and
looking at the text inside the <div> to decide what type of data is
in this <div>. This is then fed to a state-machine.

The Importer also accepts data in html-format as produced by wvHtml.
This makes it possible to provide overrides in html-format.

Categorization-data is fetched from the xml-files that Kanal5 publish.
These files contain more data than the Word-files, but they are not
updated with last minute changes. Programs are matched between the
two formats by looking for identical titles.

Features:

Episode-information parsed from description.

=cut

use DateTime;
use XML::LibXML;
use POSIX qw/floor/;

use NonameTV qw/Word2Xml Html2Xml ParseXml norm AddCategory ParseDescCatSwe/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/p w f/;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    # set the version for version checking
    $VERSION     = 0.1;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/ParseData/;
}
our @EXPORT_OK;

sub ParseData
{
  my( $ctag, $cref, $chd, $cat, $dsh, $autobatch ) = @_;

  my $doc;
    
  if( $$cref =~ /^\<\!DOCTYPE HTML/ )
  {
    # This is an override that has already been run through wvHtml
    $doc = Html2Xml( $$cref );
  }
  elsif( $$cref =~ /^\<\?xml / )
  {
    # This has been run through Word2Xml already.
    $doc = ParseXml( $cref );
  }
  else
  {
    $doc = Word2Xml( $$cref );
  }

  if( not defined( $doc ) )
  {
    f "Failed to parse";
    return 0;
  }
  
  # Find all div-entries.
  my $ns = $doc->find( "//div" );
  
  if( $ns->size() == 0 )
  {
    f "No programme entries found";
    return 0;
  }
  
  # States
  use constant {
    ST_START  => 0,
    ST_FDATE  => 1,   # Found date
    ST_FTIME  => 2,   # Found starttime
    ST_FTITLE => 3,   # Found title
    ST_FDESC  => 4,   # Found description
  };
  
  use constant {
    T_TIME => 10,
    T_TIME_TITLE => 11, # Both time and title on the same line.
    T_DATE => 12,
    T_TEXT => 13,
        };
  
  my $state=ST_START;
  my $currdate;
  my $batch_id;
  
  my $ce = {};
  
  foreach my $div ($ns->get_nodelist)
  {
    my( $text ) = norm( $div->findvalue( '.' ) );

    next if $text eq "";
    
    my $type = T_TEXT;
    
    my( $date, $channel );
    my( $start, $stop, $text2 );
    
    if( ($date, $channel ) = ($text =~ 
			      /^.*?
			      (\d+-\d+-\d+),\s+
			      vecka\s+\d+,\s+
			      (.*)$/x ) ) {
      if( $channel ne $chd->{display_name} ) {
	f "Wrong channel found ($channel)";
	$dsh->EndBatch( 1 ) if defined( $batch_id );
	return 0;
      }

      $type = T_DATE;
    }
    elsif( ($start, $stop) = 
	   ( $text =~ /^(\d+[:\.]\d+)\s*\-\s*(\d+[:\.]\d+)$/ ) )
    {
      $type = T_TIME;
    }
    elsif( ( $start ) = ( $text =~ /^(\d+[:\.]\d+)$/ ) )
    {
      $type = T_TIME;
    }
    elsif( ($start, $stop, $text2) = 
           ( $text =~ /^(\d+[:\.]\d+)\s*\-\s*(\d+[\.:]\d+)\s+(.*)$/ ) )
    {
      $type = T_TIME_TITLE;
    }
    elsif( ( $start, $text2 ) = ( $text =~ /^(\d+[:\.]\d+)\s+(.*)$/ ) )
    {
      $type = T_TIME_TITLE;
    }
    
    if( $state == ST_FTITLE )
    {
      if( $type == T_TEXT )
      {
	if( defined( $ce->{description} ) )
	{
	  $ce->{description} .= " " . $text;
	}
	else
	{
	  $ce->{description} = $text;
	}
      }
      else
      {
	extract_extra_info( $dsh, $ce, $cat, $ctag );
	$dsh->AddProgramme( $ce );
	$ce = {};
	$state = ST_FDATE;
      }
    }
    
    if( $state == ST_START )
    {
      if( $type == T_DATE )
      {
	if( $autobatch ) {
	  if( defined( $batch_id ) ) {
	    $dsh->EndBatch( 1 );
	  }
	  $batch_id = $chd->{xmltvid} . "_$date";
	  $dsh->StartBatch( $batch_id, $chd->{id} );
	}

	$dsh->StartDate( $date );
	$state = ST_FDATE;
      }
      else
      {
	w "Expected date, found: $text";
      }
    }
    elsif( $state == ST_FDATE )
    {
      if( $type == T_TIME )
      {
	$ce->{start_time} = $start;
	$ce->{end_time} = $stop if defined( $stop );
	$state = ST_FTIME;
      }
      elsif( $type == T_TIME_TITLE )
      {
	$ce->{start_time} = $start;
	$ce->{end_time} = $stop if defined( $stop );
	$ce->{title} = $text2;
	$state = ST_FTITLE;
      }
      elsif( $type == T_DATE )
      {
	if( $autobatch ) {
	  if( defined( $batch_id ) ) {
	    $dsh->EndBatch( 1 );
	  }
	  $batch_id = $chd->{xmltvid} . "_$date";
	  $dsh->StartBatch( $batch_id, $chd->{id} );
	}

	$dsh->StartDate( $date );
	$state = ST_FDATE;
      }
      else
      {
	w "Expected time, found: $text";
      }
    }
    elsif( $state == ST_FTIME )
    {
      if( $type == T_TEXT )
      {
	$ce->{title} = $text;
	$state = ST_FTITLE;
      }
      else
      {
	w "Expected title, found: $text";
      }
    }
  }
  
  if( defined( $ce->{title} ) )
  {
    extract_extra_info( $dsh, $ce, $cat, $ctag );
    $dsh->AddProgramme( $ce );
  }

  if( $autobatch ) {
    $dsh->EndBatch( 1 );
  }

  # Success
  return 1;
}

sub extract_extra_info
{
  my( $dsh, $ce, $cat, $ctag ) = @_;

  my $ds = $dsh->{ds};

  $ce->{start_time} =~ tr/\./:/;
  if( exists $ce->{end_time} ) {
    $ce->{end_time} =~ tr/\./:/;
  }

  # Try to remove any prefix such as "SERIESTART:" from the title.
  # These prefixes are only available in the doc-data, not in the
  # xml-files.
  my( $prefix, $short_title ) = ($ce->{title} =~ /(.*?):\s*(.*)/);
  if( (defined($short_title) and defined( $cat->{$short_title} )) or
      ( lc($prefix) eq "seriestart" ) or
      ( lc($prefix) =~ /^(s.songs)*premi.r$/ ) )
  {
    $ce->{title} = $short_title;
  }

  my( $program_type, $category );

  #
  # Lookup category and program_type by searching for the title in
  # the xml-data.
  #
  if( defined( $cat->{$ce->{title}} ) )
  {
    ( $program_type, $category ) = $ds->LookupCat( "Kanal5",
                                                   $cat->{$ce->{title}} );
    AddCategory( $ce, $program_type, $category );
  }
  else
  {
  }

  #
  # Try to extract category and program_type by matching strings
  # in the description.
  #
  ( $program_type, $category ) = ParseDescCatSwe( $ce->{description} );
  AddCategory( $ce, $program_type, $category );

  #
  # Add default category and program_type from the category-information
  # in the xml-file if all the above failed.
  #
  if( defined( $cat->{$ce->{title}} ) )
  {
    ( $program_type, $category ) = $ds->LookupCat( "Kanal5_fallback",
                                                   $cat->{$ce->{title}} );
    AddCategory( $ce, $program_type, $category );
  }

  # Find production year from description.
  if( defined( $ce->{description} ) and
      ($ce->{description} =~ /\bfr.n (\d\d\d\d)\b/) )
  {
    $ce->{production_date} = "$1-01-01";
  }

  my @sentences = (split_text( $ce->{description} ), "");
  my $found_episode=0;
  for( my $i=0; $i<scalar(@sentences); $i++ )
  {
    $sentences[$i] =~ tr/\n\r\t /    /s;

    $sentences[$i] =~ s/^I detta (avsnitt|program):\s*//;

    if( extract_episode( $sentences[$i], $ce ) )
    {
      $found_episode = 1;
    }
		
		if( my( $originaltitle ) = ($sentences[$i] =~ /Originaltitel:\s*(.*)/ ) )
    {
    	# Get episodename at the end of - 
    	#my ( $totalepi, $episodename ) = ($sentences[$i] =~ /\-\s+(\d+)\s+(\s*)/ );
    	
    	#if(defined($episodename)) {
    	#    $ce->{subtitle} = norm($episodename);
    	#}
      $sentences[$i] = "";
    }
    elsif( my( $aven ) = ($sentences[$i] =~ /.ven\s*(.*)$/ ) )
    {
    	# Även 17/12
      $sentences[$i] = "";
    }
    elsif( my( $rating ) = ($sentences[$i] =~ /.ldersgr.ns:\s*(.*)$/ ) )
    {
    	# Agerating
      #$ce->{rating} = norm($rating);
      $sentences[$i] = "";
    }
    elsif( my( $directors ) = ($sentences[$i] =~ /Regi:\s*(.*)/) )
    {
      $ce->{directors} = parse_person_list( $directors );
      $sentences[$i] = "";
    }
    elsif( my( $teller ) = ($sentences[$i] =~ /Ber.ttare:\s*(.*)/ ) )
    {
      $ce->{commentators} = parse_person_list( $teller );
      $sentences[$i] = "";
    }
    elsif( my( $audioactors ) = ($sentences[$i] =~ /R.ster:\s*(.*)/ ) )
    {
      $ce->{actors} = parse_person_list( $audioactors );
      $sentences[$i] = "";
    }
    elsif( my( $actors ) = ($sentences[$i] =~ /I rollerna:\s*(.*)/ ) )
    {
      $ce->{actors} = parse_person_list( $actors );
      $sentences[$i] = "";
    }
    elsif( my( $actors2 ) = ($sentences[$i] =~ /Medverkande:\s*(.*)/ ) )
    {
      $ce->{actors} = parse_person_list( $actors2 );
      $sentences[$i] = "";
    }
    elsif( my( $actors3 ) = ($sentences[$i] =~ /Sk.despelare:\s*(.*)/ ) )
    {
      $ce->{actors} = parse_person_list( $actors3 );
      $sentences[$i] = "";
    }
    elsif( my( $actors4 ) = ($sentences[$i] =~ /I rollerna.\s*(.*)/ ) )
    {
      $ce->{actors} = parse_person_list( $actors4 );
      $sentences[$i] = "";
    }
    elsif( my( $gueststar ) = ($sentences[$i] =~ /G.ststj.rna:\s*(.*)/ ) )
    {
      $ce->{guests} = parse_person_list( $gueststar );
      $sentences[$i] = "";
    }
    elsif( my( $guestactor ) = ($sentences[$i] =~ /G.stsk.despelare:\s*(.*)/ ) )
    {
    	# Kanal5 listes it in Skådespelare. No need to have it in guests.
      #$ce->{guests} = parse_person_list( $guestactor );
      $sentences[$i] = "";
    }
    elsif( my( $guests ) = ($sentences[$i] =~ /G.ster:\s*(.*)/ ) )
    {
      $ce->{guests} = parse_person_list( $guests );
      $sentences[$i] = "";
    }
    elsif( my( $presenters ) = ($sentences[$i] =~ /Programledare:\s*(.*)/ ) )
    {
      #$ce->{presenters} = parse_person_list( $presenters );
      $sentences[$i] = "";
    }
    elsif( my( $guest ) = ($sentences[$i] =~ /G.stv.rd:\s*(.*)/ ) )
    {
    	# Series like Saturday Night Live.
      $ce->{subtitle} = parse_person_list( $guest );
      $sentences[$i] = "";
    }
    elsif( my( $fran ) = ($sentences[$i] =~ /Fr.n\s*(.*)/ ) )
    {
    	# Previous air
      $sentences[$i] = "";
    }
    elsif( my( $next ) = ($sentences[$i] =~ /.ven\s*(.*)/ ) )
    {
    	# Next air
      $sentences[$i] = "";
    }
    elsif( my( $seaso, $episod ) = ($sentences[$i] =~ /^S(\d+)E(\d+)/ ) )
    {
    	$ce->{episode} = sprintf( " %d . %d . ", $seaso-1, $episod-1 ) if $episod;
    	$ce->{program_type} = 'series';
    	
    	# Remove from description
      $sentences[$i] = "";
    }
    
    # Delete the episode and everything after it from the description.
    if( $found_episode ) 
    {
      $sentences[$i] = "";
    }
  }

  $ce->{description} = join_text( @sentences );
  
  
}

sub parse_person_list
{
  my( $str ) = @_;

  # Remove all variants of m.fl.
  $str =~ s/\s*m[\. ]*fl\.*\b//;
  
  # Remove trailing '.'
  $str =~ s/\.$//;

  $str =~ s/\boch\b/,/;
  $str =~ s/\bsamt\b/,/;

  my @persons = split( /\s*,\s*/, $str );
  foreach (@persons)
  {
    # The character name is sometimes given . Remove it.
    s/^.*\s+-\s+//;
  }

  return join( ", ", grep( /\S/, @persons ) );
}

sub split_text
{
  my( $t ) = @_;

  return () if not defined( $t );

  # Remove any trailing whitespace
  $t =~ s/\s*$//;

  # Replace ... with ::.
  $t =~ s/\.{3,}/::./;

  # Replace newlines followed by a capital with space and make sure that there is a dot
  # to mark the end of the sentence. 
  $t =~ s/\.*\s*\n\s*([A-Z���])/. $1/g;

  # Turn all whitespace into pure spaces and compress multiple whitespace to a single.
  $t =~ tr/\n\r\t \xa0/     /s;

  # Replace strange dots.
  $t =~ tr/\x2e/./;

  # Split on a dot and whitespace followed by a capital letter,
  # but the capital letter is included in the output string and
  # is not removed by split. (?=X) is called a look-ahead.
#  my @sent = grep( /\S/, split( /\.\s+(?=[A-Z���])/, $t ) );

  # Mark sentences ending with a dot for splitting.
  $t =~ s/\.\s+([A-Z���])/;;$1/g;

  # Mark sentences ending with ! or ? for split, but preserve the "!?".
  $t =~ s/([\!\?])\s+([A-Z���])/$1;;$2/g;
  
  my @sent = grep( /\S/, split( ";;", $t ) );

  if( scalar( @sent ) > 0 )
  {
    $sent[-1] =~ s/\.*\s*$//;
  }

  return @sent;
}

# Join a number of sentences into a single paragraph.
# Performs the inverse of split_text
sub join_text
{
  my $t = join( ". ", grep( /\S/, @_ ) );
  $t .= "." if $t =~ /\S/;
  $t =~ s/::/../g;

  # The join above adds dots after sentences ending in ! or ?. Remove them.
  $t =~ s/([\!\?])\./$1/g;

  return $t;
}

sub extract_episode
{
  my( $d, $ce ) = @_;

  return 0 unless defined( $d );

  #
  # Try to extract episode-information from the description.
  #
  my( $ep, $eps, $seas );
  my $episode;

  # Avsn 2
  ( $ep ) = ($d =~ /\bAvsn\s+(\d+)/ );
  $episode = sprintf( " . %d .", $ep-1 ) if defined $ep;

  # Avsn 2/3
  ( $ep, $eps ) = ($d =~ /\bAvsn\s+(\d+)\s*\/\s*(\d+)/ );
  $episode = sprintf( " . %d/%d . ", $ep-1, $eps ) 
    if defined $eps;

  # Avsn 2/3 s�s 2.
  ( $ep, $eps, $seas ) = ($d =~ /\bAvsn\s+(\d+)\s*\/\s*(\d+)\s+s.s\s+(\d+)/ );
  $episode = sprintf( " %d . %d/%d . ", $seas-1, $ep-1, $eps ) 
    if defined $seas;

  # Avsn 2 s�s 2.
  ( $ep, $seas ) = ($d =~ /\bAvsn\s+(\d+)\s+s.s\s+(\d+)/ );
  $episode = sprintf( " %d . %d . ", $seas-1, $ep-1 ) 
    if defined $seas;

  # Del 2
  ( $ep ) = ($d =~ /\bDel\s+(\d+)/ );
  $episode = sprintf( " . %d .", $ep-1 ) if defined $ep;

  # Del 2/3
  ( $ep, $eps ) = ($d =~ /\bDel\s+(\d+)\s*\/\s*(\d+)/ );
  $episode = sprintf( " . %d/%d . ", $ep-1, $eps ) 
    if defined $eps;

  # Del 2/3 s�s 2.
  ( $ep, $eps, $seas ) = ($d =~ /\bDel\s+(\d+)\s*\/\s*(\d+)\s+s.s\s+(\d+)/ );
  $episode = sprintf( " %d . %d/%d . ", $seas-1, $ep-1, $eps ) 
    if defined $seas;

  # Del 2 s�s 2.
  ( $ep, $seas ) = ($d =~ /\bDel\s+(\d+)\s+s.s\s+(\d+)/ );
  $episode = sprintf( " %d . %d . ", $seas-1, $ep-1 ) 
    if defined $seas;
  
  
  
  if( defined $episode )
  {
    $ce->{episode} = $episode;
    $ce->{program_type} = 'series';
    return 1
  }

  return 0;
}
  
1;
