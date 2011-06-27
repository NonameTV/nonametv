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
    if( $ceref->{'subtitle'} ) {
      $ceref->{'subtitle'} .= ': ' . $ceref->{'subtitle'};
    }
  }elsif( $ruleref->{matchby} eq 'splitguesttitle' ) {
    # split the name of the guest from the title and put it into subtitle and guest
    my( $title, $episodetitle )=( $ceref->{title} =~ m|$ruleref->{title}| );
    $resultref->{'title'} = $title;
    $resultref->{'subtitle'} = $episodetitle;
    $resultref->{'guests'} = $episodetitle;
  }elsif( $ruleref->{matchby} eq 'replacetitle' ) {
    $resultref->{'title'} = $ruleref->{remoteref};
  }elsif( $ruleref->{matchby} eq 'replacesubtitle' ) {
    $resultref->{'subtitle'} = $ruleref->{remoteref};
  }elsif( $ruleref->{matchby} eq 'copylastdetails' ) {
    # We have a program without details (no description) and want to
    # copy all details (all but details related to the transmission, like aspect
    # and audio) from the last program with the same title/subtitle/episode
    # number on the same (or another) channel.
    #
    # Remoteref can be a xmltvid of another channel to copy from there, in this case
    # the search will be for the same or an earlier start time.
    #
    # If the programme to augment has a timestamp (UTC!) in previously-shown then
    # try a programme with that start time first.
    #
    # FIXME what about series that air in pairs of two episodes?
    #
  }else{
    $result = "don't know how to match by '" . $ruleref->{matchby} . "'";
    $resultref = undef;
  }

  return( $resultref, $result );
}


1;
