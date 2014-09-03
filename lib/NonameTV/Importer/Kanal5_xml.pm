package NonameTV::Importer::Kanal5_xml;

use strict;
use warnings;

=pod

Imports data for Kanal5 and Kanal9.
Files is sent via mail. Per week.

=cut

use utf8;

use DateTime;
use XML::LibXML;
use IO::Scalar;
use Data::Dumper;

use NonameTV qw/norm ParseDescCatSwe ParseXml AddCategory MonthNumber/;
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

  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore}, "Europe/Stockholm" );
  $self->{datastorehelper} = $dsh;

  # use augment - this is made for walking.
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
  #$ds->{SILENCE_END_START_OVERLAP}=1;
  #$ds->{SILENCE_DUPLICATE_SKIP}=1;

  my $doc;
  #my $cref=`cat $file`;
  my $xml = XML::LibXML->new;
  eval { $doc = $xml->parse_file($file); };

  if( not defined( $doc ) ) {
    error( "Kanal5_xml: $file: Failed to parse xml" );
    return;
  }

  my $currdate = "x";
  my $column;

    # the grabber_data should point exactly to one worksheet
    my $rows = $doc->findnodes( ".//transmissions/TRANSMISSION" );

    if( $rows->size() == 0 ) {
      error( "Kanal5_xml: $chd->{xmltvid}: No Rows found" ) ;
      return;
    }

  ## Fix for data falling off when on a new week (same date, removing old programmes for that date)
  my ($week, $year) = ($file =~ /tab(\d\d)(\d\d)/);

  if(!defined $year) {
    error( "Kanal5_xml: $chd->{xmltvid}: Failure to get year from filename" ) ;
    return;
  } else { $year += 2000; }

  my $batchid = $chd->{xmltvid} . "_" . $year . "-".$week;

  $dsh->StartBatch( $batchid , $chd->{id} );
  ## END

  foreach my $row ($rows->get_nodelist) {
      my $start = $self->create_dt( $row->findvalue( './/starttime/TIMEINSTANT/@full' ) );
      my $end = $self->create_dt( $row->findvalue( './/end/TIMEINSTANT/@full' ) );

      my $date = $start->ymd("-");

      if($date ne $currdate ) {
        $dsh->StartDate( $date , "06:00" );
        $currdate = $date;

        progress("Kanal5_xml: Date is: $date");
      }

      
      my $title = undef;
      my $title_org = undef;
      
      # Title,
      # Titles is in a array of titles for English (original), TTV (?), and Swedish, I choose TTV..
      # as it looks more "real".
      
      my $titles = $row->findnodes( ".//titles/PRODUCTTITLE" );
      foreach my $t ($titles->get_nodelist) {
      	# predefined is which title you want, these can be: TTV (chosen by Kanal5), SwedishTitle, OriginalTitle.
      	if($t->findvalue( './/type/PSIPRODUCTTITLETYPE/@predefined' ) eq "SwedishTitle") {
      		$title = $t->findvalue( './@title' );
      	}

      	# original title
        if($t->findvalue( './/type/PSIPRODUCTTITLETYPE/@predefined' ) eq "OriginalTitle") {
      		$title_org = $t->findvalue( './@title' );
      	}
      	
      }

      #print("Title:$title\n");

      # Home shopping
      if($row->findvalue( './/transmissiontype/TXTYPEK5/@name' ) eq "Tele Shopping") {
      	$title = "Homeshopping";
      }
      
      # No title? Weird.
      if(!(defined $title)) {
      	error("No title found at $start");
      	next;
      }

	  # extra info
	  # description is in shortdescription and shortdescriptionTTV (TTV has more info)
	  my $desc = $row->findvalue( './/shortdescriptionTTV/TEXT' );
	  
	  my $genre = $row->findvalue( './/category/CATEGORY/@name' );
		
      my $ce = {
        channel_id => $chd->{id},
        title => norm($title),
        start_time => $start->ymd("-") . " " . $start->hms(":"),
        end_time   => $end->ymd("-")   . " " . $end->hms(":"),
        description => norm($desc),
      };

      extract_extra_info( $ds, $ce );
      
      my($program_type, $category ) = $ds->LookupCat( 'Kanal5_xml', $genre );
	  AddCategory( $ce, $program_type, $category );
	  
	  # Castmembers
	  my @actors;
      my @directors;

      my $ns2 = $row->find( './/CASTMEMBER' );
  
      foreach my $act ($ns2->get_nodelist)
      {
    	my $role = undef;
        my $name = norm( $act->findvalue('./person/PERSON/@fullname') );
        my $type = norm( $act->findvalue('./function/FUNCTION/@printcode') );
      
        if($type eq "director" )
        {
          push @directors, $name;
        }
        else
        {
          push @actors, $name;
        }
      }
      
      if( scalar( @actors ) > 0 and !defined($ce->{actors}) )
      {
        $ce->{actors} = join ";", @actors;
      }

      if( scalar( @directors ) > 0 and !defined($ce->{directors}) )
      {
        $ce->{directors} = join ";", @directors;
      }

      $ce->{original_title} = norm($title_org) if defined($title_org) and $ce->{title} ne norm($title_org) and norm($title_org) ne "";

      # Replace The in the original title.
      if(defined($ce->{original_title})) {
        # Move , The to The <name>
        if($ce->{original_title} =~ /, The/i) {
            $ce->{original_title} =~ s/, The//i;
            $ce->{original_title} = norm("The ".$ce->{original_title});
        }

        # US
        if($ce->{original_title} =~ /^US\s+/i) {
            $ce->{original_title} =~ s/^US //i;
            $ce->{original_title} = $ce->{original_title} . " US";
        }

        # UK
        if($ce->{original_title} =~ /^UK\s+/i) {
            $ce->{original_title} =~ s/^UK //i;
            $ce->{original_title} = $ce->{original_title} . " UK";
        }

        # AU
        if($ce->{original_title} =~ /^AU\s+/i) {
            $ce->{original_title} =~ s/^AU //i;
            $ce->{original_title} = $ce->{original_title} . " AU";
        }

        $ce->{original_title} = norm($ce->{original_title});
      }
      
      # Add programme
      $ds->AddProgrammeRaw( $ce );
      progress( "Kanal5_xml: $chd->{xmltvid}: $start - $title" );
    } # next row

	$dsh->EndBatch( 1 );

  return 1;
}

sub create_dt
{
  my $self = shift;
  my( $str ) = @_;
    $str =~ s/\..*$//;
  my( $date, $time ) = split( 'T', $str );

#print("date: $date\n");
#print("time: $time\n");

  if( not defined $time )
  {
    return undef;
  }
  my( $year, $month, $day ) = split( '-', $date );
  
  # Remove the dot and everything after it.

  
  my( $hour, $minute, $second ) = split( ":", $time );
  
  

  my $dt = DateTime->new( year   => $year,
                          month  => $month,
                          day    => $day,
                          hour   => $hour,
                          minute => $minute,
                          time_zone => 'Europe/Stockholm',
                          );
 ##
 $dt->set_time_zone( "UTC" );
  
  return $dt;
}

sub extract_extra_info
{
  my( $ds, $ce ) = @_;
 	#
  # Try to extract category and program_type by matching strings
  # in the description.
  #
  my ( $program_type, $category ) = ParseDescCatSwe( $ce->{description} );
  AddCategory( $ce, $program_type, $category );

  my @sentences = (split_text( $ce->{description} ), "");
  for( my $i=0; $i<scalar(@sentences); $i++ )
  {
    $sentences[$i] =~ tr/\n\r\t /    /s;
    $sentences[$i] =~ s/^I detta (avsnitt|program)://;
		
	if( my( $originaltitle ) = ($sentences[$i] =~ /^Originaltitel:\s*(.*)/ ) )
    {
    	# Remove originaltitle from description, maybe use originaltitle instead of
    	# swedish title?
      $sentences[$i] = "";
    }
    elsif( my( $rating ) = ($sentences[$i] =~ /^.ldersgr.ns:\s*(.*)$/ ) )
    {
    	# Agerating
      #$ce->{rating} = norm($rating);
      $sentences[$i] = "";
    }
    elsif( my( $directors ) = ($sentences[$i] =~ /^Regi:\s*(.*)/) )
    {
      $ce->{directors} = parse_person_list( $directors );
      $sentences[$i] = "";
    }
    elsif( my( $teller ) = ($sentences[$i] =~ /^Ber.ttare:\s*(.*)/ ) )
    {
      $ce->{commentators} = parse_person_list( $teller );
      $sentences[$i] = "";
    }
    elsif( my( $audioactors ) = ($sentences[$i] =~ /^R.ster:\s*(.*)/ ) )
    {
      $ce->{actors} = parse_person_list( $audioactors );
      $sentences[$i] = "";
    }
    elsif( my( $actors ) = ($sentences[$i] =~ /^I rollerna:\s*(.*)/ ) )
    {
      $ce->{actors} = parse_person_list( $actors );
      $sentences[$i] = "";
    }
    elsif( my( $actors2 ) = ($sentences[$i] =~ /^Medverkande:\s*(.*)/ ) )
    {
      $ce->{actors} = parse_person_list( $actors2 );
      $sentences[$i] = "";
    }
    elsif( my( $actors3 ) = ($sentences[$i] =~ /^Sk.despelare:\s*(.*)/ ) )
    {
      $ce->{actors} = parse_person_list( $actors3 );
      $sentences[$i] = "";
    }
    elsif( my( $actors4 ) = ($sentences[$i] =~ /^I rollerna.\s*(.*)/ ) )
    {
      $ce->{actors} = parse_person_list( $actors4 );
      $sentences[$i] = "";
    }
    elsif( my( $gueststar ) = ($sentences[$i] =~ /^G.ststj.rna:\s*(.*)/ ) )
    {
      $ce->{guests} = parse_person_list( $gueststar );
      $sentences[$i] = "";
    }
    elsif( my( $guestactor ) = ($sentences[$i] =~ /^G.stsk.despelare:\s*(.*)/ ) )
    {
    	# Kanal5 listes it in Sk�despelare. No need to have it in guests.
      #$ce->{guests} = parse_person_list( $guestactor );
      $sentences[$i] = "";
    }
    elsif( my( $guests ) = ($sentences[$i] =~ /^G.ster:\s*(.*)/ ) )
    {
      $ce->{guests} = parse_person_list( $guests );
      $sentences[$i] = "";
    }
    elsif( my( $presenters ) = ($sentences[$i] =~ /^Programledare:\s*(.*)/ ) )
    {
      $ce->{presenters} = parse_person_list( $presenters );
      $sentences[$i] = "";
    }
    elsif( my( $guest ) = ($sentences[$i] =~ /^G.stv.rd:\s*(.*)/ ) )
    {
    	# Series like Saturday Night Live.
      $ce->{subtitle} = parse_person_list( $guest );
      $sentences[$i] = "";
    }
    elsif( my( $fran ) = ($sentences[$i] =~ /^Fr.n\s*(.*)/ ) )
    {
    	# Previous air
      $sentences[$i] = "";
    }
    elsif( my( $next ) = ($sentences[$i] =~ /^.ven\s*(.*)/ ) )
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
    elsif(my ($prodyear) = ($sentences[$i] =~ /\bfr.n (\d\d\d\d)\b/))
    {
        # Remove the bline and add it to the db instead and grab production year
        $ce->{bline} = norm($sentences[$i]);
        $ce->{production_date} = $prodyear."-01-01";
        $sentences[$i] = "";
    }
  }

  $ce->{description} = norm(join_text( @sentences ));
  
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
  $t =~ s/\.*\s*\n\s*([A-Z???])/. $1/g;

  # Turn all whitespace into pure spaces and compress multiple whitespace to a single.
  $t =~ tr/\n\r\t \xa0/     /s;

  # Replace strange dots.
  $t =~ tr/\x2e/./;

  # Split on a dot and whitespace followed by a capital letter,
  # but the capital letter is included in the output string and
  # is not removed by split. (?=X) is called a look-ahead.
#  my @sent = grep( /\S/, split( /\.\s+(?=[A-Z???])/, $t ) );

  # Mark sentences ending with a dot for splitting.
  $t =~ s/\.(|\s+)([A-Z???])/;;$2/g;

  # Mark sentences ending with ! or ? for split, but preserve the "!?".
  $t =~ s/([\!\?])\s+([A-Z???])/$1;;$2/g;
  
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

1;