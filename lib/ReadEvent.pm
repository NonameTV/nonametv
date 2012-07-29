package ReadEvent;


=pod

Reads one event from file

=cut

use strict;
use warnings;

use utf8;
use Env;

use NonameTV::Log qw/progress/;
use NonameTV::Config qw/ReadConfig/;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
    
    # set the version for version checking
    $VERSION     = 0.1;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],
    @EXPORT_OK   = qw/ReadEvent/;
}
our @EXPORT_OK;

sub ReadEvent
{
  my( $lang, $file ) = @_;

  my $conf = ReadConfig();

  my $filename = $conf->{Site}->{Credits} . "/credits/sites/" . lc( $conf->{Site}->{Name} ) . "/" . $lang . "/" . $file;

  my $event = {
    title => "",
    description => "",
  };

  open(TXTFILE, $filename) or return undef;
  my @lines = <TXTFILE>;

  foreach my $text (@lines){

    if( $text =~ /^#/ ){
      next;
    } elsif( $text =~ /^TITLE:/i ){
      ( $event->{title} ) = ( $text =~ /^TITLE:\s*(.*)$/i );
    } elsif( $text =~ /^DESCRIPTION:/i ){
      ( $event->{description} ) = ( $text =~ /^DESCRIPTION:\s*(.*)$/i );
    }

  }

  close(TXTFILE);
    
  return( $event );
}

1;

### Setup coding system
## Local Variables:
## coding: utf-8
## End:
