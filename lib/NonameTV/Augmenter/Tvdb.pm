package NonameTV::Augmenter

use Data::Dumper;
use TVDB::API;

my $apikey = '903EA97DCFFBCD21';
my $cachefile = '/home/nonametv/var/contentcache/'.'thetvdb/tvdb.db';
my $bannerdir = '/home/nonametv/var/contentcache/'.'thetvdb/banner';

my $tvdb = TVDB::API::new({ apikey    => $apikey,
                            lang      => 'de',
                            cache     => $cachefile,
                            banner    => $bannerdir,
                            useragent => 'Grabber from NonameTV site',
                         });

# ZDFneo - 30 Rock - Der Pfad der Tugend - Folge 37
my $episode = $tvdb->getEpisodeAbs('30 Rock', 37);
print Dumper($episode);

# prematched episodeid: ARTE - Mini-Max oder Die unglaublichen Abenteuer des Maxwell Smart - So ein Zirkus ... - Folge 39
my $episode = $tvdb->getEpisodeId(6058);
print Dumper($episode);

# ZDFneo - Mad Men - Verkaufte Vergangenheit - Folge 5
my $episode = $tvdb->getEpisodeAbs('Mad Men', 5);
print Dumper($episode);
