package NonameTV::Importer::SOAC;

use strict;
use warnings;

=pod

channel: Smile of a child

Import data from Excel or PDF files delivered via e-mail.
Each file is for one week.

Features:

=cut

use utf8;

use DateTime;
use PDF::Core;
#use PDF::Parse;
use PDF;

use NonameTV::DataStore::Helper;
use NonameTV::Log qw/progress error/;
use NonameTV qw/AddCategory norm MonthNumber/;

use NonameTV::Importer::BaseFile;

use base 'NonameTV::Importer::BaseFile';

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $self  = $class->SUPER::new( @_ );
  bless ($self, $class);


  my $dsh = NonameTV::DataStore::Helper->new( $self->{datastore} );
  $self->{datastorehelper} = $dsh;

  return $self;
}

sub ImportContentFile {
  my $self = shift;
  my( $file, $chd ) = @_;

  $self->{fileerror} = 0;

  my $xmltvid = $chd->{xmltvid};
  my $channel_id = $chd->{id};
  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  if( $file =~ /\.xls$/i ){
    #$self->ImportXLS( $file, $channel_id, $xmltvid );
  } elsif( $file =~ /\.pdf$/i ){
    $self->ImportPDF( $file, $channel_id, $xmltvid );
  }

  return;
}

sub ImportPDF
{
  my $self = shift;
  my( $file, $channel_id, $xmltvid ) = @_;

  my $dsh = $self->{datastorehelper};
  my $ds = $self->{datastore};

  # Only process .xls files.
  return if $file !~  /\.pdf$/i;

  my $batch_id;
  my $currdate = "x";
  my $timecol = 0;

  progress( "SOAC: $xmltvid: Processing $file" );

  my $pdf = PDF->new( $file );

  my $pagenum = $pdf->Pages;
print "$pagenum\n";

  my $res= $pdf->GetObject( $pdf );
print "$res\n";




#  my $text = $p->get_text;

#print "$text\n";


  return;
}

sub isDate {
  my ( $text ) = @_;

  # format '6-Jul'
  if( $text =~ /^\d+-(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)$/i ){
    return 1;
  }

  return 0;
}

sub ParseDate
{
  my ( $dinfo ) = @_;

  my( $day, $monthname ) = ( $dinfo =~ /^(\d+)-(\S+)$/ );

  my $year = DateTime->today()->year;

  my $month = MonthNumber( $monthname , "en" );

  return sprintf( '%d-%02d-%02d', $year, $month, $day );
}

sub isTime {
  my ( $text ) = @_;

  # format '18:30 AM/PM'
  if( $text =~ /^\d+:\d+\s+AM\/PM$/i ){
    return 1;
  }

  return 0;
}

sub ParseTime
{
  my ( $tinfo ) = @_;

  my( $hour, $minute ) = ( $tinfo =~ /^(\d+):(\d+)\s+/ );

  return sprintf( '%02d:%02d', $hour, $minute );
}

sub ParseShow
{
  my ( $text ) = @_;

  $text =~ s/\s+/ /g;

  my( $title, $subtitle);

  if( $text =~ /\(cc\)\s/ ){
    ( $title, $subtitle ) = ( $text =~ /(.*)\(cc\)\s(.*)/ );
  } else {
    $title = $text;
  }

  return( $title, $subtitle );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
