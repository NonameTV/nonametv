DROP TABLE IF EXISTS `batches`;
CREATE TABLE `batches` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(50) NOT NULL DEFAULT '',
  `last_update` int(11) NOT NULL DEFAULT '0',
  `message` text NOT NULL,
  `abort_message` text NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `channels`;
CREATE TABLE `channels` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `display_name` varchar(100) NOT NULL DEFAULT '',
  `xmltvid` varchar(100) NOT NULL DEFAULT '',
  `chgroup` varchar(100) NOT NULL,
  `grabber` varchar(25) NOT NULL DEFAULT '',
  `export` tinyint(1) NOT NULL DEFAULT '0',
  `grabber_info` varchar(100) NOT NULL DEFAULT '',
  `logo` tinyint(4) NOT NULL DEFAULT '0',
  `def_pty` varchar(20) DEFAULT '',
  `def_cat` varchar(20) DEFAULT '',
  `sched_lang` varchar(4) NOT NULL DEFAULT '',
  `empty_ok` tinyint(1) NOT NULL DEFAULT '0',
  `url` varchar(100) DEFAULT NULL,
  `allowcredits` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `chgroup` (`chgroup`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `channelgroups`;
CREATE TABLE `channelgroups` (
  `abr` varchar(24) CHARACTER SET latin1 NOT NULL,
  `display_name` varchar(100) CHARACTER SET latin1 NOT NULL,
  `position` tinyint(10) unsigned NOT NULL,
  `sortby` varchar(32) NOT NULL,
  `hidden` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`abr`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `files`;
CREATE TABLE `files` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `channelid` int(11) NOT NULL DEFAULT '0',
  `filename` varchar(80) NOT NULL DEFAULT '',
  `successful` tinyint(1) DEFAULT NULL,
  `message` text NOT NULL,
  `earliestdate` datetime DEFAULT NULL,
  `latestdate` datetime DEFAULT NULL,
  `md5sum` varchar(33) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `channelid` (`channelid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `programs`;
CREATE TABLE `programs` (
  `category` varchar(100) NOT NULL DEFAULT '',
  `channel_id` int(11) NOT NULL DEFAULT '0',
  `start_time` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `end_time` datetime DEFAULT '0000-00-00 00:00:00',
  `schedule_id` varchar(100) NOT NULL,
  `title_id` varchar(100) NOT NULL,
  `title` varchar(100) NOT NULL DEFAULT '',
  `subtitle` mediumtext,
  `description` text,
  `batch_id` int(11) NOT NULL DEFAULT '0',
  `program_type` varchar(20) DEFAULT '',
  `episode` varchar(20) DEFAULT NULL,
  `production_date` date DEFAULT NULL,
  `aspect` enum('unknown','4:3','16:9') NOT NULL DEFAULT 'unknown',
  `quality` varchar(40) NOT NULL,
  `stereo` varchar(40) NOT NULL,
  `rating` varchar(20) NOT NULL,
  `directors` text NOT NULL,
  `actors` text NOT NULL,
  `writers` text NOT NULL,
  `adapters` text NOT NULL,
  `producers` text NOT NULL,
  `presenters` text NOT NULL,
  `commentators` text NOT NULL,
  `guests` text NOT NULL,
  `url` varchar(100) DEFAULT NULL,
  `star_rating` varchar(20) DEFAULT NULL,
  `live` int(1) DEFAULT NULL,
  `rerun` int(1) DEFAULT NULL,
  `extra_id` varchar(65) DEFAULT NULL COMMENT 'imdbid(movies)/tvdbid(series)/tvrageid(series)',
  `extra_id_type` varchar(65) DEFAULT NULL COMMENT 'type: tvrage,themoviedb,thetvdb',
  `original_title` varchar(255) DEFAULT NULL COMMENT 'Original Title',
  `original_subtitle` varchar(255) DEFAULT NULL,
  `previously_shown` varchar(255) DEFAULT NULL,
  `bline` varchar(255) DEFAULT NULL,
  `country` varchar(255) DEFAULT NULL,
  `poster` varchar(255) DEFAULT NULL,
  `fanart` varchar(255) DEFAULT NULL,
  `external_ids` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`channel_id`,`start_time`),
  KEY `batch` (`batch_id`,`start_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `state`;
CREATE TABLE `state` (
  `name` varchar(60) NOT NULL DEFAULT '',
  `value` text,
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `trans_cat`;
CREATE TABLE `trans_cat` (
  `type` varchar(50) NOT NULL,
  `original` varchar(50) NOT NULL DEFAULT '',
  `category` varchar(50) DEFAULT NULL,
  `program_type` varchar(50) DEFAULT '',
  PRIMARY KEY (`type`,`original`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `trans_country`;
CREATE TABLE `trans_country` (
  `type` varchar(50) NOT NULL,
  `original` varchar(50) NOT NULL DEFAULT '',
  `country` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`type`,`original`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `languagestrings`;
CREATE TABLE `languagestrings` (
  `module` varchar(32) NOT NULL DEFAULT '',
  `strname` varchar(32) NOT NULL DEFAULT '',
  `strvalue` text NOT NULL,
  `language` varchar(4) NOT NULL DEFAULT '',
  UNIQUE KEY `lng` (`module`,`strname`,`language`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `epgservers`;
CREATE TABLE `epgservers` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `active` tinyint(1) unsigned NOT NULL DEFAULT '0',
  `name` varchar(100) NOT NULL DEFAULT '',
  `description` varchar(100) NOT NULL DEFAULT '',
  `vendor` varchar(100) NOT NULL DEFAULT '',
  `type` varchar(100) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `dvb_cat`;
CREATE TABLE `dvb_cat` (
  `category` varchar(100) DEFAULT NULL,
  `dvb_category` varchar(20) NOT NULL,
  `description` varchar(100) NOT NULL,
  PRIMARY KEY (`dvb_category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `networks`;
CREATE TABLE `networks` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `nid` int(11) NOT NULL,
  `active` tinyint(1) unsigned NOT NULL DEFAULT '0',
  `epgserver` int(11) unsigned NOT NULL,
  `name` varchar(100) NOT NULL,
  `operator` varchar(100) NOT NULL DEFAULT '',
  `description` varchar(100) NOT NULL DEFAULT '',
  `charset` varchar(100) NOT NULL DEFAULT '',
  `type` enum('DVB-C','DVB-S','DVB-T','IPTV','GENERIC') NOT NULL,
  PRIMARY KEY (`id`),
  KEY `epgserver` (`epgserver`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `services`;
CREATE TABLE `services` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `dbchid` int(11) unsigned NOT NULL,
  `active` tinyint(1) unsigned NOT NULL DEFAULT '0',
  `network` int(11) unsigned NOT NULL,
  `transportstream` int(11) unsigned NOT NULL,
  `servicename` varchar(100) NOT NULL DEFAULT '',
  `logicalchannelnumber` int(11) unsigned NOT NULL,
  `serviceid` int(11) unsigned NOT NULL,
  `description` varchar(100) NOT NULL DEFAULT '',
  `sourceaddress` varchar(32) NOT NULL,
  `sourceport` int(10) unsigned NOT NULL,
  `pidvideo` int(10) unsigned NOT NULL,
  `pidaudio` int(10) unsigned NOT NULL,
  `nvod` varchar(100) NOT NULL,
  `servicetypeid` int(11) unsigned NOT NULL,
  `lasteventid` int(11) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `transportstream` (`transportstream`),
  KEY `dbchid` (`dbchid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `transportstreams`;
CREATE TABLE `transportstreams` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `tsid` int(11) NOT NULL,
  `active` tinyint(1) unsigned NOT NULL DEFAULT '0',
  `network` int(11) unsigned NOT NULL,
  `description` varchar(100) NOT NULL DEFAULT '',
  `muxmainprotocol` varchar(100) NOT NULL DEFAULT '',
  `eitmaxbw` varchar(100) NOT NULL DEFAULT '',
  `simaxbw` varchar(100) NOT NULL DEFAULT '',
  `dsystype` varchar(100) NOT NULL,
  `dsysfrequency` varchar(100) NOT NULL,
  `dsysmodulationschemeid` varchar(100) NOT NULL,
  `dsysfecouterschemeid` varchar(100) NOT NULL,
  `dsysfecinnerschemeid` varchar(100) NOT NULL,
  `dsyssymbolrate` varchar(100) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `network` (`network`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `admins`;
CREATE TABLE `admins` (
  `username` varchar(32) NOT NULL DEFAULT '',
  `password` varchar(64) NOT NULL,
  `fullname` varchar(64) NOT NULL DEFAULT '',
  `email` varchar(64) NOT NULL DEFAULT '',
  `language` varchar(32) NOT NULL DEFAULT '',
  `ismaster` tinyint(1) unsigned NOT NULL DEFAULT '0',
  `roleeditor` tinyint(1) unsigned NOT NULL DEFAULT '0',
  UNIQUE KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `augmenterrules`;
CREATE TABLE `augmenterrules` (
  `channel_id` int(11) DEFAULT NULL,
  `augmenter` varchar(20) NOT NULL,
  `title` varchar(100) DEFAULT NULL,
  `otherfield` varchar(20) DEFAULT NULL,
  `othervalue` varchar(100) DEFAULT NULL,
  `remoteref` varchar(100) DEFAULT NULL,
  `matchby` varchar(30) DEFAULT NULL,
  UNIQUE KEY `channel_id` (`channel_id`,`augmenter`,`title`,`otherfield`,`othervalue`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `jobs`;
CREATE TABLE `jobs` (
  `type` varchar(20) NOT NULL,
  `name` varchar(100) NOT NULL,
  `starttime` datetime NOT NULL,
  `deleteafter` datetime NOT NULL,
  `duration` varchar(20) NOT NULL,
  `success` tinyint(4) NOT NULL,
  `message` mediumtext,
  `lastok` datetime DEFAULT '0000-00-00 00:00:00',
  `lastfail` datetime DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`type`,`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `dvb_service_pointer`;
CREATE TABLE `dvb_service_pointer` (
  `channel_id` int(11) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT '1',
  `original_network_id` int(5) NOT NULL,
  `transport_id` int(5) NOT NULL DEFAULT '0',
  `service_id` int(5) NOT NULL,
  `description` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`original_network_id`,`transport_id`,`service_id`,`active`),
  KEY `channel_id` (`channel_id`),
  CONSTRAINT `dvb_service_pointer_ibfk_1` FOREIGN KEY (`channel_id`) REFERENCES `channels` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO `admins` (username, password) VALUES ('nonametv', '');
