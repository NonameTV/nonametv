DROP TABLE IF EXISTS `batches`;
CREATE TABLE `batches` (
  `id` int(11) NOT NULL auto_increment,
  `name` varchar(50) NOT NULL default '',
  `last_update` int(11) NOT NULL default '0',
  `message` text NOT NULL,
  `abort_message` text NOT NULL,
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `channels`;
CREATE TABLE `channels` (
  `id` int(11) NOT NULL auto_increment,
  `display_name` varchar(100) NOT NULL default '',
  `xmltvid` varchar(100) NOT NULL default '',
  `chgroup` varchar(100) NOT NULL,
  `grabber` varchar(20) NOT NULL default '',
  `export` tinyint(1) NOT NULL default '0',
  `grabber_info` varchar(100) NOT NULL default '',
  `logo` tinyint(4) NOT NULL default '0',
  `def_pty` varchar(20) default '',
  `def_cat` varchar(20) default '',
  `sched_lang` varchar(4) NOT NULL default '',
  `empty_ok` tinyint(1) NOT NULL default '0',
  `url` varchar(100) default NULL,
  `allowcredits` tinyint(1) NOT NULL default '0',
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `channelgroups`;
CREATE TABLE `channelgroups` (
  `abr` varchar(24) character set latin1 NOT NULL,
  `display_name` varchar(100) character set latin1 NOT NULL,
  `position` tinyint(10) unsigned NOT NULL,
  `sortby` varchar(32) NOT NULL,
  `hidden` tinyint(1) NOT NULL default '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `files`;
CREATE TABLE `files` (
  `id` int(11) NOT NULL auto_increment,
  `channelid` int(11) NOT NULL default '0',
  `filename` varchar(80) NOT NULL default '',
  `successful` tinyint(1) default NULL,
  `message` text NOT NULL,
  `earliestdate` datetime default NULL,
  `latestdate` datetime default NULL,
  `md5sum` varchar(33) NOT NULL default '',
  PRIMARY KEY  (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `programs`;
CREATE TABLE `programs` (
  `category` varchar(100) NOT NULL default '',
  `channel_id` int(11) NOT NULL default '0',
  `start_time` datetime NOT NULL default '0000-00-00 00:00:00',
  `end_time` datetime default '0000-00-00 00:00:00',
  `schedule_id` varchar(100) NOT NULL,
  `title_id` varchar(100) NOT NULL,
  `title` varchar(100) NOT NULL default '',
  `subtitle` mediumtext,
  `description` mediumtext,
  `batch_id` int(11) NOT NULL default '0',
  `program_type` varchar(20) default '',
  `episode` varchar(20) default NULL,
  `production_date` date default NULL,
  `aspect` enum('unknown','4:3','16:9') NOT NULL default 'unknown',
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
  `url` varchar(100) default NULL,
  `url_image_main` varchar(100) default NULL,
  `url_image_thumbnail` varchar(100) default NULL,
  `url_image_icon` varchar(100) default NULL,
  PRIMARY KEY  (`channel_id`,`start_time`),
  KEY `batch` (`batch_id`,`start_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `state`;
CREATE TABLE `state` (
  `name` varchar(60) NOT NULL default '',
  `value` text,
  PRIMARY KEY  (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `trans_cat`;
CREATE TABLE `trans_cat` (
  `type` varchar(20) NOT NULL default '',
  `original` varchar(50) NOT NULL default '',
  `category` varchar(20) default '',
  `program_type` varchar(50) default '',
  PRIMARY KEY  (`type`,`original`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `languagestrings`;
CREATE TABLE `languagestrings` (
  `module` varchar(32) NOT NULL default '',
  `strname` varchar(32) NOT NULL default '',
  `strvalue` text NOT NULL,
  `language` varchar(4) NOT NULL default ''
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `epgservers`;
CREATE TABLE `epgservers` (
  `id` int(11) unsigned NOT NULL auto_increment,
  `active` tinyint(1) unsigned NOT NULL default '0',
  `name` varchar(100) NOT NULL default '',
  `description` varchar(100) NOT NULL default '',
  `vendor` varchar(100) NOT NULL default '',
  `type` varchar(100) NOT NULL default '',
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `dvb_cat`;
CREATE TABLE `dvb_cat` (
  `category` varchar(20) NOT NULL default '',
  `dvb_category` varchar(20) NOT NULL,
  PRIMARY KEY  (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `networks`;
CREATE TABLE `networks` (
  `id` int(11) unsigned NOT NULL auto_increment,
  `nid` int(11) NOT NULL,
  `active` tinyint(1) unsigned NOT NULL default '0',
  `epgserver` int(11) unsigned NOT NULL,
  `name` varchar(100) NOT NULL,
  `operator` varchar(100) NOT NULL default '',
  `description` varchar(100) NOT NULL default '',
  `charset` varchar(100) NOT NULL default '',
  `type` enum('DVB-C','DVB-S','DVB-T','IPTV','GENERIC') NOT NULL,
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `services`;
CREATE TABLE `services` (
  `id` int(11) unsigned NOT NULL auto_increment,
  `dbchid` int(11) unsigned NOT NULL,
  `active` tinyint(1) unsigned NOT NULL default '0',
  `network` int(11) unsigned NOT NULL,
  `transportstream` int(11) unsigned NOT NULL,
  `servicename` varchar(100) NOT NULL default '',
  `logicalchannelnumber` int(11) unsigned NOT NULL,
  `serviceid` int(11) unsigned NOT NULL,
  `description` varchar(100) NOT NULL default '',
  `sourceaddress` varchar(32) NOT NULL,
  `sourceport` int(10) unsigned NOT NULL,
  `pidvideo` int(10) unsigned NOT NULL,
  `pidaudio` int(10) unsigned NOT NULL,
  `nvod` varchar(100) NOT NULL,
  `servicetypeid` int(11) unsigned NOT NULL,
  `lasteventid` int(11) unsigned NOT NULL,
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `transportstreams`;
CREATE TABLE `transportstreams` (
  `id` int(11) unsigned NOT NULL auto_increment,
  `tsid` int(11) NOT NULL,
  `active` tinyint(1) unsigned NOT NULL default '0',
  `network` int(11) unsigned NOT NULL,
  `description` varchar(100) NOT NULL default '',
  `muxmainprotocol` varchar(100) NOT NULL default '',
  `eitmaxbw` varchar(100) NOT NULL default '',
  `simaxbw` varchar(100) NOT NULL default '',
  `dsystype` varchar(100) NOT NULL,
  `dsysfrequency` varchar(100) NOT NULL,
  `dsysmodulationschemeid` varchar(100) NOT NULL,
  `dsysfecouterschemeid` varchar(100) NOT NULL,
  `dsysfecinnerschemeid` varchar(100) NOT NULL,
  `dsyssymbolrate` varchar(100) NOT NULL,
  UNIQUE KEY `id` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

DROP TABLE IF EXISTS `admins`;
CREATE TABLE `admins` (
  `username` varchar(32) NOT NULL,
  `password` varchar(32) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
INSERT INTO `admins` (username, password) VALUES ('nonametv', '');
