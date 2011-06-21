package NonameTV::Augmenter::Fixups;

use strict;
use warnings;

use Data::Dumper;
use Encode;

use NonameTV qw/norm/;
use NonameTV::Augmenter::Base;
use NonameTV::Config qw/ReadConfig/;
use NonameTV::Log qw/w/;

use base 'NonameTV::Augmenter::Base';


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self  = $class->SUPER::new( @_ );
    bless ($self, $class);

#    print Dumper( $self );

#    defined( $self->{Language} ) or die "You must specify Language";

    # need config for main content cache path
    my $conf = ReadConfig( );

    return $self;
}


sub AugmentProgram( $$$ ){
  my( $self, $ceref, $ruleref ) = @_;

  # empty hash to get all attributes to change
  my $resultref = {};
  # result string, empty/false for success, message/true for failure
  my $result = '';

  if( $ruleref->{matchby} eq 'setcategorynews' ) {
    $resultref->{'category'} = 'news';
  }elsif( $ruleref->{matchby} eq 'splittitle' ) {
    my( $title, $episodetitle )=( $ceref->{title} =~ m|$ruleref->{title}| );
    $resultref->{'title'} = $title;
    $resultref->{'subtitle'} = $episodetitle;
  }elsif( $ruleref->{matchby} eq 'copylastdetails' ) {
    # we have a program without details (no description) and want to
    # copy all details from the last program with the same
    # title/subtitle/episode number on the same (or another) channel
  }else{
    $result = "don't know how to match by '" . $ruleref->{matchby} . "'";
    $resultref = undef;
  }

  return( $resultref, $result );
}


1;
