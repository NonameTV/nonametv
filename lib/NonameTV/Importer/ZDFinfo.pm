package NonameTV::Importer::ZDFinfo;

use strict;
use warnings;

=pod

Importer for data from ZDF. 
One file per channel and week downloaded from their site.
The downloaded file is in xml-format.
Same format as DreiSat.

=cut

use NonameTV qw/ParseXml/;
use NonameTV::Importer::ZDF_util qw/ParseWeek ParseData/;
use NonameTV::Log qw/progress w error/;

use base 'NonameTV::Importer::BaseFile';

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

    return $self;
}

sub ImportContentFile {
  my $self = shift;

  my( $filename, $chd ) = @_;

  $self->{datastore}->{augment} = 1;

  progress ("ZDFinfo: reading $filename");

  open(XMLFILE, $filename);
  undef $/;
  my $cref = <XMLFILE>;
  close(XMLFILE);

  my $week = ParseWeek (\$cref);

  my $batch_id = $chd->{xmltvid} . "_" . $week;
  $self->{datastore}->StartBatch ($batch_id);
  my $err = ParseData ( $batch_id, \$cref, $chd, $self->{datastore});
  $self->{datastore}->EndBatch ($err, undef);

  return 
}


1;
