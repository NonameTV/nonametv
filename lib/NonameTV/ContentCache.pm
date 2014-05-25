package NonameTV::ContentCache;

use strict;
use warnings;

use Digest::MD5 qw/md5_hex/;
use Encode qw(encode_utf8 from_to is_utf8);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError) ;

use NonameTV::Log qw/w d/;

=pod

Utility class for NonameTV.

Downloads data via http and stores it in a cache. The cache is stored
as plain files named after the objectname, which makes it easy to look
at the contents of the cache and inspect the data that has been
downloaded.

=pod

=head1 Constructor

  my $cc = NonameTV::ContentCache->new( {
    basedir => "/tmp/test",
    callbackobject => $obj,
    useragent => "Mozilla 1.0",
  } );

The callbackobject must implement the following methods:

  my( $urlstr, $error ) = $co->Object2Url( $objectname, $callbackdata );

  Convert an objectname into a url. The callbackdata is taken from
  the call to GetConvert. $urlstr can also be a reference to an array
  in which case the urls will be tried in order until one of them
  receive a successful response.

  my $error = $co->ApproveContent( $content_ref, $callbackdata );

  Check the content returned from the server to determine if it is
  valid. This method is called whenever the downloaded content is
  valid according to the http protocol. It can be used for servers
  that do not return proper http response-codes and uses error-pages
  or something else instead. ApproveContent is really only useful in
  combination with an Object2Url that returns several urls.

  undef means that the content is valid. A string is treated as an
  error message.

  my( $filtered_ref, $error ) = $co->FilterContent( $content_ref, 
                                                    $callbackdata )

  Filter the content to remove any unnecessary data. The resulting data
  is compared to the previous filtered data to see if the filtered data
  has changed before it is returned by GetContent.

  Both these methods can return (undef, "errorstring") if an error 
  occured for some reason. The error will be handled in the same way as
  errors from the http-server.

  my( $extension ) = $co->ContentExtension();
  my( $extension ) = $co->FilteredExtension();

  ContentCache will name the files on disk with these extension (e.g. html).
  If undef is returned, no extension is used.

=cut

sub new {
  my $class = ref( $_[0] ) || $_[0];
  
  my $self = { }; 
  bless $self, $class;

  # Copy the parameters supplied in the constructor.
  foreach my $key (keys(%{$_[1]})) {
      $self->{$key} = ($_[1])->{$key};
  }

  eval {
    require WWW::Mechanize;
    $self->{ua} = WWW::Mechanize->new( onerror => \&d );
  };

  if( not defined $self->{ua} ) {
    require LWP::UserAgent;
    $self->{ua} = LWP::UserAgent->new( cookie_jar => {} );
  }

  $self->{ua}->agent( $self->{useragent} );
  $self->{ua}->env_proxy( );
  $self->{ua}->ssl_opts( SSL_verify_mode => 'SSL_VERIFY_NONE' );

  if( not defined $self->{credentials} ) {
    $self->{credentials} = {};
  }

  if( not -d $self->{basedir} ) {
      mkdir( $self->{basedir} ) or
	  die "Failed to create $self->{basedir}";
  }

  return $self;
}

=pod

    my( $dataref, $errormsg ) = $cc->GetContent( $objectname, 
                                                 $callbackdata, 
                                                 $force );

Fetch a an object from a url. Returns undef if the object was unchanged
since the last time it was fetched or if the fetch failed. $errormsg
contains an errormessage returned from the server. Three different answers
are possible:

  (dataref, undef) - Data was downloaded and needs to be processed.
  (undef, errormsg) - Download failed and the caller should notify the user
                      of the error.
  (undef, undef) - The content or filtered content was the same as the last time 
        it was downloaded.

     If $force is true, (undef, undef) is never returned.

=cut
 
sub GetContent {
  my $self = shift;
  my( $objectname, $data, $force ) = @_;

  $force = 0 if not defined $force;
  
  my $co = $self->{callbackobject};
  
  my( $url, $objerror ) = $co->Object2Url( $objectname, $data );
  if( not defined( $url ) ) {
    return( undef, $objerror );
   }

  my @urls;

  if( ref( $url ) eq "ARRAY" ) {
    @urls = @{$url};
    if( scalar( @urls ) == 0 ) {
      die "$objectname: Object2Url returned an empty array-ref.";
    }
  }
  else {
    @urls = ($url);
  }

  my( $cref, $geterror );

  foreach my $surl (@urls) {
    ( $cref, $geterror ) = $self->GetUrl( $surl );
    if( defined $cref ) {
      $geterror = $co->ApproveContent( $cref, $data );
      if( defined $geterror ) {
	$cref = undef;
      }
      else {
	last;
      }
    }
  }

  $self->TouchState( $objectname );
  my $state = $self->GetState( $objectname );
  if( $force ) {
    $state->{contentmd5} = "xx";
    $state->{filteredmd5} = "xx";
    delete( $state->{error} );
  }

  if( defined( $cref ) ) {
    my $currstate = {
      contentmd5 => "(unknown)",
      filteredmd5 => "(unknown)",
    };

    # Treat undef as an empty string.
    $$cref = "" if not defined $$cref;
    
    w "Content is not a sequence of bytes."
	if is_utf8( $$cref );

    # Calculate md5sum of content
    $currstate->{contentmd5} = $self->CalculateMD5( $cref );

    # Compare md5sum with stored md5sum
    if( $currstate->{contentmd5} eq $state->{contentmd5} ) {
      # Same as last time
      return (undef, undef);
    }

    $self->WriteReference( $self->Filename( $objectname, "content",
                           $co->ContentExtension() ), 
			   $cref );

    # Filter content
    if( (not defined $cref) or (not defined $$cref) ) {
      my $empty = "";
      $cref = \$empty;
    }

    my( $filtered_ref, $filter_error ) = 
	$co->FilterContent( $cref, $data );

    if( not defined $filtered_ref ) {
      $self->SetState( $objectname, $currstate );
      return (undef, $filter_error );
    }

    # Calculate md5sum of filtered content
    $currstate->{filteredmd5} = $self->CalculateMD5( $filtered_ref );

    $self->SetState( $objectname, $currstate );

    # Compare md5sum with stored md5sum
    if( $currstate->{filteredmd5} eq $state->{filteredmd5} ) {
      # Same as last time
      return (undef, undef);
    }

    $self->WriteReference( $self->Filename( $objectname, "filtered", 
                                            $co->FilteredExtension() ), 
			   $filtered_ref );
    
    return ($filtered_ref, undef);
  }
  else {
    # No content was returned for this url.

    if( defined( $state->{error} ) and ($state->{error} eq $geterror) ) {
      # Same error as last time. No point in reporting 
      # it again.
      return (undef, undef);
    }
    else {
      unlink( $self->Filename( $objectname, "content", 
			       $co->ContentExtension() ) );
      unlink( $self->Filename( $objectname, "filtered", 
			       $co->FilteredExtension() ) );
      $self->SetState( $objectname, { error => $geterror } );
      return (undef, $geterror );
    }
  }
}

=pod

  my( $dataref, $error ) = $cc->GetUrl( $url );

Fetch a url. Returns (undef, "error message")  if the server 
returned an error.

=cut
 
sub GetUrl {
  my $self = shift;
  my( $url ) = @_;

  my $surl = $url;
  my( $host )  = ($surl =~ m%://(.*?)/%);
  if( defined( $self->{credentials}->{$host} ) ) {
    my $cred = $self->{credentials}->{$host};
    
    $surl =~ s%://(.*?)/%://$cred\@$1/%;
  }

  my $res = $self->{ua}->get( $surl );

#  if( defined( $self->{wantuncompress} ) ) {
    if( defined( $res->header( 'Content-Encoding' ) ) ) {
      # Content-Encoding: gzip
      if ($res->header( 'Content-Encoding' ) =~ m|^gzip$| ) {
        d( "uncompressing gzip" );
        my $newc;
        # try to gunzip
        gunzip $res->content_ref => \$newc
          or return (undef, 'failure in gunzipping content: ' . $GunzipError);
        ${$res->content_ref} = $newc; 
      }
    }
#  }

  if( defined( $self->{wantdecode} ) ) {
    if( defined( $res->header( 'Content-Type' ) ) ) {
      # Content-Type: text/plain;charset=windows-1250
      # Content-Type: text/plain;charset=windows-1252
      if ((my ($encoding) = ($res->header( 'Content-Type' ) =~ m|;charset=(\S+)$| ))) {
        d( "decoding $encoding into utf-8" );
        from_to( ${$res->content_ref}, $encoding, 'utf-8' );
      }
    }
  }

  if( $res->is_success ) {
    return ($res->content_ref, undef);
  }
  else {
    return (undef, $res->status_line);
  }
}

sub UserAgent {
  my $self = shift;

  return $self->{ua};
}

=pod

Content is stored in both filtered and unfiltered format. Each content
uses a number of files:

 objname.unfiltered
 objname.filtered
 objname.state

objname.state is touch()ed each time the content is asked for.
objname.state contains the following:

contentmd5 abdb4b1b3ba
filteredmd5 ab3b2b4b1b4

=cut

sub GetState {
  my $self = shift;
  my( $objectname ) = @_;

  my $state = {
    contentmd5 => "x",
    filteredmd5 => "x",
  };

  my $statefile = $self->Filename( $objectname, "state" );
  open( IN, "< $statefile" ) or return $state;

  while( my $line = <IN> ) {
    next if $line =~ /^\s+$/;
    my( $key, $data ) = ($line =~ /^(.*?) (.*?)$/);
    $state->{$key} = $data;
  }

  close( IN );
  return $state;
}

sub SetState {
  my $self = shift;
  my( $objectname, $state ) = @_;

  my $statefile = $self->Filename( $objectname, "state" );

  open( OUT, "> $statefile" )
      or die "Failed to write to $statefile";

  foreach my $key (keys %{$state}) {
    print OUT "$key $state->{$key}\n";
  }

  close( OUT );
}

sub CalculateMD5 {
  my $self  = shift;
  my( $strref ) = @_;

  return md5_hex(encode_utf8($$strref));
}

sub Filename {
  my $self = shift;
  my( $objectname, $type, $extension ) = @_;
  
  if( defined( $extension ) ) {
    $extension = ".$extension";
  }
  else {
    $extension = "";
  }

  if( $type eq "state" ) {
    return "$self->{basedir}/$objectname.state";
  }
  elsif( $type eq "content" ) {
    return "$self->{basedir}/$objectname.content$extension";
  }
  elsif( $type eq "filtered" ) {
    return "$self->{basedir}/$objectname.filtered$extension";
  }
  die "Unknown type $type";
}

sub TouchState {
  my $self = shift;
  my( $objectname ) = @_;

  my $now = time;
  utime( $now, $now, $self->Filename( $objectname, "state" ) );
}

sub WriteReference {
  my $self = shift;

  my( $filename, $ref ) = @_;

  open OUT, "> $filename" or die "Failed to write to $filename";
  print OUT $$ref;
  close( OUT );
}

sub RemoveOld {
  my $self = shift;

  my $g = $self->Filename( "*", "state" );

  my @statefiles = glob( $g );

  foreach my $statefile (@statefiles) {
    if( -M( $statefile ) > 7 ) {
      my( $base ) = ($statefile =~ /(.*)\.state$/);

      unlink( $statefile );
      unlink <$base.content*>;
      unlink <$base.filtered*>;
    }
  }
}

1;
