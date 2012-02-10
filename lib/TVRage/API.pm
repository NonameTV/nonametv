#===============================================================================
#       MODULE:  TVRage::API
#       AUTHOR:  Joakim Nylén, http://tvtab.la
#      COMPANY:  dotMedia Networks
#      SOME STUFF IS FROM TVDB::API - ALL THANKS GOES TO BEHANW.
#===============================================================================

use strict;
use warnings;

package TVRage::API;

use Mouse;
use LWP::UserAgent;
use HTTP::Request::Common;
use XML::Simple;
use Encode qw(encode decode);
use Data::Dumper;
use Debug::Simple;
use NonameTV::Config qw/ReadConfig/;
use NonameTV::Log qw/w d/;

sub new {
    my $self = bless {};
    
    my $args;
    if (ref $_[0] eq 'HASH') {
        # Subroutine arguments by hashref
        $args = shift;
    } else {
        # Traditional subroutine arguments
        $args = {};
        ($args->{cache}) = @_;
    }
    
    # Nonametv conf
    my $conf = ReadConfig( );
    
    $args->{cache} = $conf->{ContentCachePath} . 'Tvrage/tvrage.db';
    $args->{useragent} ||= "nonametv (http://nonametv.org)";
    

    $self->{ua} = LWP::UserAgent->new;
    $self->{ua}->env_proxy();
    $self->setUserAgent($args->{useragent});
    
    $self->{xml} = XML::Simple->new(
        ForceArray => ['Showinfo'],#, 'Season', 'episode'
        SuppressEmpty => 1,
    );

    $self->setCacheDB($args->{cache});
    
    
    #my %opt = (quiet => 0, debug => 4, verbose => 3);
    #Debug::Simple::debuglevels(\%opt);
    
    return $self;
}

###############################################################################
########################### from TVDB::API ####################################
###############################################################################
sub setUserAgent {
    my ($self, $userAgent) = @_;
    $self->{ua}->agent($userAgent);
}


# Download binary data
sub _download {
    my ($self, $fmt, $url, @parm) = @_;

    # Make URL
    $url = sprintf($fmt, $url, @parm);

    #$url =~ s/\$/%24/g;
    $url =~ s/#/%23/g;
    #$url =~ s/\*/%2A/g;
    #$url =~ s/\!/%21/g;
    #&verbose(2, "TVRage::Cache: download: $url\n");
    utf8::encode($url);

    # Make sure we only download once even in a session
    return $self->{dload}->{$url} if defined $self->{dload}->{$url};

    # Download URL
    my $req = HTTP::Request->new(GET => $url);
    my $res = $self->{ua}->request($req);

    if ($res->content =~ /(?:404 Not Found|The page your? requested does not exist)/i) {
        #&warning("TVRage::Cache: download $url, 404 Not Found\n");
        $self->{dload}->{$url} = 0;
        return undef;
    }
    $self->{dload}->{$url} = $res->content;
    return $res->content;
}
# Download Xml, remove empty tags, parse XML, and return hashref
sub _downloadXml {
    my ($self, $fmt, @parm) = @_;

    # Download XML file
    my $xml = $self->_download($fmt, $self->{apiURL}, @parm, 'xml');
    return undef unless $xml;

    $xml = Compress::Zlib::memGunzip($xml) unless $xml =~ /^</;

    # Remove empty tags
    $xml =~ s/(<[^\/\s>]*\/>|<[^\/\s>]*><\/[^>]*>)//gs;

    # Return process XML into hashref
    return undef unless $xml;
    return $self->{xml}->XMLin($xml);
}

sub setCacheDB {
    my ($self, $cache) = @_;
    $self->{cachefile} = $cache;
    $self->{cache} = DBM::Deep->new(
        file => $cache,
        #filter_store_key => \&_compressCache,
        filter_store_value => \&_compressCache,
        #filter_fetch_key => \&_decompressCache,
        filter_fetch_value => \&_decompressCache,
        utf8 => 1,
    );
}
sub _compressCache {
    # Escape UTF-8 chars and gzip data
    return Compress::Zlib::memGzip(encode('utf8',$_[0]));
}
sub _decompressCache {
    # Decompress data and then unescape UTF-8 chars
    return decode('utf8',Compress::Zlib::memGunzip($_[0]));
}
sub dumpCache {
    my ($self) = @_;
    my $cache = $self->{cache};
    print Dumper($cache);
}

###############################################################################
# Find all possible series that are close
sub getPossibleSeriesId {
    my ($self, $sid) = @_;

    &verbose(2, "TVRage: Get possbile series id for $sid\n");
    #my $xml = $self->_download($Url{getSeriesID}, $Url{defaultURL}, $sid, $self->{lang});
    my $xml = "";
    return undef unless $xml;
    my $data = XMLin($xml, ForceArray=>['Series'], KeyAttr=>{});

    # Build hashref to return
    my $ret = {};
    for my $series (@{$data->{Series}}) {
        my $sid = $series->{id};
        if (defined $ret->{$sid}) {
            $ret->{$sid}->{altlanguage} = {};
            $ret->{$sid}->{altlanguage}->{$series->{language}} = $series;
        } else {
            $ret->{$sid} = $series;
        }
    }

    return $ret;
}

###############################################################################
# Get ID for named series
sub getSeriesId {
    my ($self, $sid, $nocache) = @_;
    $sid = $sid->[0] if ref $sid eq 'ARRAY';
    return undef unless defined $sid;

    # see if $sid is a series id already
    return $sid if $sid =~ /^\d+$/ && $sid > 70000;

    # See if it's in the series cache
    my $cache = $self->{cache};
    if (!$nocache && defined $cache->{Name2Sid}->{$sid}) {
        #print "From SID Cache: $sid -> $cache->{Name2Sid}->{$sid}\n";
        return undef unless $cache->{Name2Sid}->{$sid};
        return $cache->{Name2Sid}->{$sid};
    }

    #my $data = $self->getPossibleSeriesId($sid);

    # Look through list of possibilities
    #if ($data) {
    #    while (my ($sid,$series) = each %$data) {
    #        if ($series->{SeriesName} =~ /^(The )?\Q$sid\E(, The)?$/i) {
    #            $cache->{Name2Sid}->{$sid} = $sid;
    #            return $sid;
    #        }
    #    }
    #}

    # Nothing found, assign 0 to name so we cache this result
    #&warning("TVRage::Cache: No series id found for: $sid\n");
    $cache->{Name2Sid}->{$sid} = 0; # Not undef as that messes up DBM::Deep
    return undef;
}

###############################################################################
# Set Series Id in Cache
sub setSeriesId {
    my ($self, $sid) = @_;
    return 1 unless defined $sid;

    # See if it's in the series cache
    my $cache = $self->{cache};
    $cache->{Name2Sid}->{$sid} = $sid;
    return 0;
}

###############################################################################
# Do we have this Series?



sub showInfo {
    my ($self, $sid) = @_;
    
    my $series = $self->{cache};
    
    
    &debug(2, "TVRage: getSeries: $sid, $sid\n");

    #my $sid = $self->getSeriesId($showId, $nocache?$nocache-1:0);
    #return undef unless $sid;

    if (defined $series->{$sid}) {
        # Get updated series data
            &debug(2, "TVRage: From Series Cache: $sid\n");
#print Dumper( $series->{$sid} );
    # Get full series data
    } else {
         #&debug(2, "download: $sid\n");
         &verbose(1, "TVRage: Downloading series: $sid\n");
            my $data = $self->_downloadXml("http://www.tvrage.com/feeds/showinfo.php?sid=". $sid);
            #print Dumper( $data );
            return undef unless $data;

            # Copy updated series into cache
            while (my ($key,$value) = each %{$data}) {
                $series->{$sid}->{$key} = $value;
                
            }
         
        $self->getEpisodes($sid);
        
        #print Dumper( $series->{$sid} );
        
    }
    
    #print Dumper( $series );
    return $series->{$sid};
}

sub getEpisodes {
    my ($self, $sid) = @_;
    my $series = $self->{cache};
    
    # Episodes already downloaded?
    if (defined $series->{$sid}->{episodes}) {
            &debug(2, "From Episodes Cache: $sid\n");
#print Dumper( $series->{$sid}->{episodes} );
    # Get full series data
    } else {
         #&debug(2, "download: $sid\n");
         &verbose(1, "TVRage: Downloading episodes: $sid\n");
            my $data = $self->_downloadXml("http://www.tvrage.com/feeds/episode_list.php?sid=". $sid);
            #print Dumper( $data );
            return undef unless $data;

            # Copy updated series into cache
            $series->{$sid}->{episodes} = [] unless $series->{$sid}->{episodes};
            $series->{$sid}->{episodes} = $data;
         
     }
        
        #print Dumper( $series->{$sid}->{episodes} );
        return $series->{$sid}->{episodes};
}

sub getEpisode {
    my ($self, $sid, $season, $episode) = @_;
    my $episode2 = $episode;
    my $season2 = $season;
    $episode--; $season--;
    my $series = $self->{cache};
    
    # check if it's in array format and return the details, or in hash (one episdoe added only) o return error
    if($series->{$sid}->{episodes}{Episodelist}{Season} =~ /Array/) {
    	if(defined($series->{$sid}) and defined($series->{$sid}->{episodes}{Episodelist}{Season}[$season]) and defined($series->{$sid}->{episodes}{Episodelist}{Season}[$season]{episode}[$episode])) {
    		# w( "TVRage: episode " . $episode . " of season " . $season . " found for '" . $series->{$sid}->{showname} . "'" );
    		return $series->{$sid}->{episodes}{Episodelist}{Season}[$season]{episode}[$episode];
    	} else {
        w( "TVRage: no episode " . $episode2 . " of season " . $season2 . " found for '" . $series->{$sid}->{showname} . "'" );
        return undef;
    	}
    } elsif($series->{$sid}->{episodes}{Episodelist}{Season} =~ /Hash/) {
    	w("TVRage: the episode list is in HASH format, do something here to get the details (hash = only one season/episode)");
    	return undef;
    } else {
    	#print Dumper($series->{$sid});
    	w("TVRage: the episode list is not in array nor hash format, weird.");
    	return undef;
    }
}

1;