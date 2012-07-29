package NonameTV::Importer::DiscoveryScraper;

=pod

This importer imports data from www.discoverychannel.no. The data is fetched
as one html-file per day and channel.

=cut

use strict;
use warnings;

use POSIX;
use DateTime;
#use Unicode::String qw(utf8 latin1);
use Encode;
#use XML::LibXML;
use HTML::TableExtract;
use HTML::Entities;
#use XML::XPath;
#use XML::XPath::XMLParser;

use NonameTV qw/MyGet norm Html2Xml/;
use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;

use NonameTV::Importer::BaseDaily;

use base 'NonameTV::Importer::BaseDaily';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);


    defined( $self->{UrlRoot} ) or die "You must specify UrlRoot";

    my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore},
      "Europe/Oslo"  );
    $self->{datastorehelper} = $dsh;

    return $self;
}

sub ImportContent
{
  my $self = shift;
  my( $batch_id, $cref, $chd ) = @_;

  my $ds = $self->{datastore};
  my $dsh = $self->{datastorehelper};

  my( $date ) = ($batch_id =~ /_(.*)$/);

  $dsh->StartDate( $date );
  #print $$cref;
  $$cref = decode_utf8($$cref);
  #my $decoder = utf8($$cref);
  #my $decoded = $decoder->latin1;
  #my $decoded = encode_entities($$cref);
  
  my $te = HTML::TableExtract->new( 
    #headers => [qw(TID TITTEL)],
    attribs => { id => 'tvlistings-table' },
    keep_html => 1
    );
  
  $te->parse($$cref);

  my $table = $te->first_table_found();
  
  foreach my $row ($table->rows) {
    my $start = norm(@$row[0]); 
    #print "\n>>>$start\n";
    next if ($start eq "TID" || $start eq "TIME");
    #my $fulltext = decode_utf8(norm(@$row[1])); 
    my $fulltext = norm(@$row[1]);
    my $tmptitle = $1 if $fulltext =~ m!<strong>(.*)</strong>!i; 
    my @titlearray = split(':', $tmptitle);
    my $title = norm(shift(@titlearray));
    my $subtitle = norm(join(':',@titlearray));
    
    my $desc = $1 if $fulltext =~ m!description">(.*)</div>!i;
	#$desc = decode_utf8($desc);
  
    my $ce = {
        start_time => $start,
        title => $title,
        subtitle => $subtitle,
        description => $desc
    };
    
    $dsh->AddProgramme( $ce );

#    print ">>>", norm(@$row[1]), "\n";
  }
  #print scalar($table->rows());
#    my $ce =  {
#      start_time  => $starttime,
#      title       => norm($title),
#      description => norm($desc),
#    };
    
#    extract_extra_info( $ce );
#    $dsh->AddProgramme( $ce );
  
  
  return 1;
}

sub FetchDataFromSite
{
  my $self = shift;
  my( $batch_id, $data ) = @_;

  my( $date ) = ($batch_id =~ /_(.*)/);

  # Date should be in format yyyymmdd.
  $date = toUnixDate( $date );

  #my $u = URI->new($self->{UrlRoot});
  #$u->query_form( {
  #  chn => $data->{grabber_info},
  #  date => $date,
  #});

  my $url = $self->{UrlRoot};
  $url = $url."&cur_dt=$date&channel_code=";
  my $grinfo = $data->{grabber_info};
  my ( $chan, $lang ) = split('_',$grinfo);
  $url = "$url$chan&language_code=$lang";
  #print "\n>>>> $url <<<<\n";
  my( $content, $code ) = MyGet( $url );

  return( $content, $code );
}

sub extract_extra_info
{
  my( $ce ) = shift;

}

sub toUnixDate { 1;
  my ( $date ) = @_; 
  my $year = substr($date, 0, 4 ); 
  my $mnt = substr($date, 5, 2 ); 
  my $day = substr($date, 8, 2 ); 
  my $unixdate = mktime (0,0,15,$day,$mnt-1,$year-1900,0,0); 
  
  return $unixdate."000";
}

1;
