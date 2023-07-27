#
# Custom Tag Importer
#
# (c) 2021 AF
#
# Based on the CustomScan plugin by (c) 2006 Erland Isaksson
#
# GPLv3 license
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#

package Plugins::CustomTagImporter::Common;

use strict;
use warnings;
use utf8;

use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use File::Spec::Functions qw(:ALL);
use Plugins::CustomTagImporter::MP3::Info;
use POSIX qw(floor);
use Time::HiRes qw(time);

my $prefs = preferences('plugin.customtagimporter');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log::logger('plugin.customtagimporter');

my $scanningAborted = 0;
my @libraryTrackIDs = ();
my $errors = 0;
my %dumpedTagNames;

use base 'Exporter';
our %EXPORT_TAGS = (
	all => [qw(commit rollback initDatabase rescan abortScan isScanning countAvailableCustomTags)],
);
our @EXPORT_OK = ( @{ $EXPORT_TAGS{all} } );

# MP3 raw tag mapping
my %rawTagNames = (
	'GRP1' => 'GROUPING',
	'IPL' => 'INVOLVEDPEOPLE',
	'IPLS' => 'INVOLVEDPEOPLE',
	'MVNM' => 'MOVEMENTNAME',
	'MVIN' => 'MOVEMENT',
	'PCST' => 'PODCAST',
	'TAL' => 'ALBUM',
	'TALB' => 'ALBUM',
	'TBP' => 'BPM',
	'TBPM' => 'BPM',
	'TCAT' => 'PODCASTCATEGORY',
	'TCM' => 'COMPOSER',
	'TCMP' => 'COMPILATION',
	'TCO' => 'CONTENTTYPE', #GENRE
	'TCOM' => 'COMPOSER',
	'TCON' => 'CONTENTTYPE', #GENRE
	'TCOP' => 'COPYRIGHT',
	'TCR' => 'COPYRIGHT',
	'TDA' => 'DATE',
	'TDAT' => 'DATE',
	'TDEN' => 'ENCODINGTIME',
	'TDES' => 'TDES',
	'TDLY' => 'PLAYLISTDELAY',
	'TDOR' => 'ORIGRELEASETIME',
	'TDRC' => 'RECORDINGTIME', #YEAR
	'TDRL' => 'RELEASETIME',
	'TDTG' => 'TAGGINGTIME',
	'TDY' => 'PLAYLISTDELAY',
	'TEN' => 'ENCODEDBY',
	'TENC' => 'ENCODEDBY',
	'TEXT' => 'LYRICIST',
	'TFLT' => 'FILETYPE',
	'TFT' => 'FILETYPE',
	'TGID' => 'PODCASTID',
	'TIM' => 'TIME',
	'TIME' => 'TIME',
	'TIPL' => 'INVOLVEDPEOPLE2',
	'TIT1' => 'CONTENTGROUP',
	'TIT2' => 'TITLE',
	'TIT3' => 'SUBTITLE',
	'TKE' => 'INITIALKEY',
	'TKEY' => 'INITIALKEY',
	'TKWD' => 'PODCASTKEYWORDS',
	'TLA' => 'LANGUAGE',
	'TLAN' => 'LANGUAGE',
	'TLE' => 'SONGLEN',
	'TLEN' => 'SONGLEN',
	'TMCL' => 'MUSICIANCREDITLIST',
	'TMED' => 'MEDIATYPE',
	'TMOO' => 'MOOD',
	'TMT' => 'MEDIATYPE',
	'TOA' => 'ORIGARTIST',
	'TOAL' => 'ORIGALBUM',
	'TOF' => 'ORIGFILENAME',
	'TOFN' => 'ORIGFILENAME',
	'TOL' => 'ORIGLYRICIST',
	'TOLY' => 'ORIGLYRICIST',
	'TOPE' => 'ORIGARTIST',
	'TOR' => 'ORIGYEAR',
	'TORY' => 'ORIGYEAR',
	'TOT' => 'ORIGALBUM',
	'TOWN' => 'FILEOWNER',
	'TP1' => 'ARTIST',
	'TP2' => 'BAND',
	'TP3' => 'CONDUCTOR',
	'TP4' => 'MIXARTIST',
	'TPA' => 'PARTINSET', #SET
	'TPB' => 'PUBLISHER',
	'TPE1' => 'ARTIST',
	'TPE2' => 'BAND',
	'TPE3' => 'CONDUCTOR',
	'TPE4' => 'MIXARTIST',
	'TPOS' => 'PARTINSET', #SET
	'TPRO' => 'PRODUCEDNOTICE',
	'TPUB' => 'PUBLISHER',
	'TRC' => 'ISRC',
	'TRCK' => 'TRACKNUM',
	'TRD' => 'RECORDINGDATES',
	'TRDA' => 'RECORDINGDATES',
	'TRK' => 'TRACKNUM',
	'TRSN' => 'NETRADIOSTATION',
	'TRSO' => 'NETRADIOOWNER',
	'TSI' => 'SIZE',
	'TSIZ' => 'SIZE',
	'TSOA' => 'ALBUMSORTORDER',
	'TSOP' => 'PERFORMERSORTORDER',
	'TSOC' => 'COMPOSERSORTORDER',
	'TSOT' => 'TITLESORTORDER',
	'TSRC' => 'ISRC',
	'TSS' => 'ENCODERSETTINGS',
	'TSSE' => 'ENCODERSETTINGS',
	'TSST' => 'SETSUBTITLE',
	'TT1' => 'CONTENTGROUP',
	'TT2' => 'TITLE',
	'TT3' => 'SUBTITLE',
	'TXT' => 'LYRICIST',
	'TXX' => 'USERTEXT',
	'TXXX' => 'USERTEXT',
	'TYE' => 'YEAR',
	'TYER' => 'YEAR',
	'WAF' => 'WWWAUDIOFILE',
	'WAR' => 'WWWARTIST',
	'WAS' => 'WWWAUDIOSOURCE',
	'WCM' => 'WWWCOMMERCIALINFO',
	'WCOM' => 'WWWCOMMERCIALINFO',
	'WCOP' => 'WWWCOPYRIGHT',
	'WCP' => 'WWWCOPYRIGHT',
	'WFED' => 'PODCASTURL',
	'WOAF' => 'WWWAUDIOFILE',
	'WOAR' => 'WWWARTIST',
	'WOAS' => 'WWWAUDIOSOURCE',
	'WORS' => 'WWWRADIOPAGE',
	'WPAY' => 'WWWPAYMENT',
	'WPB' => 'WWWPUBLISHER',
	'WPUB' => 'WWWPUBLISHER',
	'WXX' => 'WWWUSER',
	'WXXX' => 'WWWUSER',
	'XSOP' => 'ARTISTSORT',
);

sub initDatabase {
	my $class = shift;

	my $dbh = Slim::Schema->dbh;
	my $sth = $dbh->table_info();
	my $tableExists;
	eval {
		while (my ($qual, $owner, $table, $type) = $sth->fetchrow_array()) {
			if ($table eq 'customtagimporter_track_attributes') {
				$tableExists = 1;
			}
		}
	};
	if($@) {
		$log->error("Database error: $DBI::errstr");
	}
	$sth->finish();
	main::DEBUGLOG && $log->is_debug && $log->debug($tableExists ? 'CTI table table found.' : 'No CTI table table found.');

	unless ($tableExists) {
		my $createDBsql = "CREATE TABLE IF NOT EXISTS customtagimporter_track_attributes (
id INTEGER PRIMARY KEY AUTOINCREMENT,
track int(10),
url text NOT NULL,
urlmd5 char(32) NOT NULL,
type varchar (255) NOT NULL,
attr varchar (255) NOT NULL,
value varchar(255),
valuesort varchar(255)
);

create index if not exists track_attr_cstrackidx on customtagimporter_track_attributes (track, type, attr);
create index if not exists urlmd5_cstrackidx on customtagimporter_track_attributes (urlmd5);
create index if not exists urlIndex on customtagimporter_track_attributes (url(255));
create index if not exists type_attr_value_idx on customtagimporter_track_attributes (type, attr, value);
create index if not exists type_attr_valuesort_idx on customtagimporter_track_attributes (type, attr, valuesort);
create index if not exists attr_type_idx on customtagimporter_track_attributes (attr, type);
create index if not exists track_attr_value_cstrackidx on customtagimporter_track_attributes (track, attr, value, valuesort);";

		main::DEBUGLOG && $log->is_debug && $log->debug('CustomTagImporter: Creating database tables + indices');
		executeSQLstat($createDBsql);
	}
}

sub executeSQLstat {
	my $statement = shift;
	my $dbh = Slim::Schema->dbh;
	my $inStatement = 0;

	for my $line (split(/[\n\r]/, $statement)) {
		# skip empty lines
		$line =~ s/^\s*//o;

		next if $line =~ /^\s*$/;

		if ($line =~ /^\s*(?:CREATE|SET|INSERT|UPDATE|DELETE|DROP|SELECT|ALTER|DROP)\s+/oi) {
			$inStatement = 1;
		}

		if ($line =~ /;/ && $inStatement) {
			$statement .= $line;
			main::DEBUGLOG && $log->is_debug && $log->debug("Executing SQL statement: [$statement]");
			eval { $dbh->do($statement) };
			if ($@) {
				$log->error("Couldn't execute SQL statement: [$statement] : [$@]");
			}
			$statement = '';
			$inStatement = 0;
			next;
		}
		$statement .= $line if $inStatement;
	}
	commit($dbh);
}

sub rescan {
	my $importerCall = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug('Starting rescan');

	if (!$importerCall && $prefs->get('scanningInProgress')) {
		main::DEBUGLOG && $log->is_debug && $log->debug('CustomTagImporter: Scanning already in progress, wait until it\'s finished');
		return;
	}

	$prefs->set('scanprogresspercentage', 0);

	if (!$prefs->get('customtags') && !$prefs->get('ratingtags')) {
		main::DEBUGLOG && $log->is_debug && $log->debug('CustomTagImporter: scanning requires that you define at least 1 custom or rating tag');
		$prefs->set('scanResult', 4);
		return;
	}

	$prefs->set('scanningInProgress', 1);
	$prefs->set('scanResult', 0);
	$scanningAborted = 0;
	$errors = 0;

	initTrackScan($importerCall);

	return;
}

sub initTrackScan {
	my $importerCall = shift;
	my $scanningContext->{'scanStartTime'} = time();

	clearDBtable();

	my $dbh = Slim::Schema->dbh;

	# get track ids
	@libraryTrackIDs = ();
	my $sth = $dbh->prepare("SELECT tracks.id from tracks where tracks.audio = 1 and tracks.remote = 0 and tracks.content_type != 'cpl' and tracks.content_type != 'src' and tracks.content_type != 'ssp' and tracks.content_type != 'dir' and tracks.content_type is not null group by tracks.id order by tracks.id asc");
	$sth->execute();
	my ($id, $url);
	$sth->bind_col(1, \$id);
	while ($sth->fetch()) {
		push @libraryTrackIDs, $id;
	}
	$sth->finish();

	my $count = scalar @libraryTrackIDs;
	$scanningContext->{'noOfTracks'} = $count;
	$scanningContext->{'currentTrackNo'} = 0;
	main::DEBUGLOG && $log->is_debug && $log->debug('Number of tracks to scan: '.$scanningContext->{'noOfTracks'});
	$scanningContext->{'importerCall'} = $importerCall;

	if ($importerCall) {
		my $progress;

		if ($count) {
			$progress = Slim::Utils::Progress->new({
				'type' => 'importer',
				'name' => 'plugin_customtagimporter_scan',
				'total' => $count,
				'bar' => 1
			});
		}

		while ( scanTracksForImporter({
			scanningContext => $scanningContext,
			count => $count,
			progress => $progress,
		}) ) {}
	} else {
		Slim::Utils::Scheduler::add_task(\&scanTrack, $scanningContext);
	}
}

sub scanTracksForImporter {
	my $params = shift;
	my $progress = $params->{progress};
	my $scanningContext = $params->{scanningContext};

	if (my $trackID = shift(@libraryTrackIDs)) {
		getScanTrackAttributes($trackID, $scanningContext);

		if ($scanningContext->{'currentTrackNo'} > 0 && $scanningContext->{'currentTrackNo'} % 1000 == 0) {
			main::INFOLOG && $log->is_info && $log->info('Scanned '.$scanningContext->{'currentTrackNo'}.' out of '.$scanningContext->{'noOfTracks'}.' tracks so far');
		}
		return 1;
	}

	exitScan($scanningContext);
	if ($progress) {
		$progress->final($params->{count});
		$log->error(sprintf('Finished in %.3f seconds', $progress->duration));
	}
	return 0;
}

sub scanTrack {
	my $scanningContext = shift;

	my $trackID = undef;
	if (defined($scanningContext->{'currentTrackNo'})) {
		$trackID = shift @libraryTrackIDs;
	}

	if (defined($trackID)) {
		getScanTrackAttributes($trackID, $scanningContext);
		return 1 if !$scanningAborted;
	}
	exitScan($scanningContext);
	return 0;
}

sub getScanTrackAttributes {
	my ($trackID, $scanningContext) = @_;

	if (defined($trackID)) {
		my $track = Slim::Schema->rs('Track')->find($trackID);
		my $dbh = Slim::Schema->dbh;
		main::DEBUGLOG && $log->is_debug && $log->debug('Scanning track '.$scanningContext->{'currentTrackNo'}.' of '.$scanningContext->{'noOfTracks'});
		main::DEBUGLOG && $log->is_debug && $log->debug('Scanning track: '.$track->title);

		my $attributes;
		eval { $attributes = scanCustomTagTrack($track, $scanningContext); };

		if ($@) {
			$log->error("CustomTagImporter: Failed to call scanTrack: $@");
			$errors++;
		}

		if ($attributes && scalar(@{$attributes}) > 0) {
			for my $attribute (@{$attributes}) {
				my $sql = undef;
				$sql = "INSERT INTO customtagimporter_track_attributes (track, url, urlmd5, type, attr, value, valuesort) values (?, ?, ?, ?, ?, ?, ?)";
				my $sth = $dbh->prepare($sql);
				eval {
					$sth->bind_param(1, $track->id);
					$sth->bind_param(2, $track->url);
					$sth->bind_param(3, $track->urlmd5);
					if ($attribute->{'name'} eq 'RATING') {
						$sth->bind_param(4, 'rating');
					} else {
						$sth->bind_param(4, 'customtag');
					}

					$sth->bind_param(5, $attribute->{'name'});
					$sth->bind_param(6, $attribute->{'value'});
					if (defined($attribute->{'valuesort'})) {
						$attribute->{'valuesort'} = Slim::Utils::Text::ignoreCaseArticles($attribute->{'valuesort'});
					} elsif (defined($attribute->{'value'})) {
						$attribute->{'valuesort'} = Slim::Utils::Text::ignoreCaseArticles($attribute->{'value'});
					}
					$sth->bind_param(7, $attribute->{'valuesort'});
					$sth->execute();
					commit($dbh);
				};
				if ($@) {
					$log->error("Database error: $DBI::errstr");
					eval {
						rollback($dbh);
					};
					$errors++;
				}
				$sth->finish();
			}
		}
		$scanningContext->{'currentTrackNo'}++;

		if ($scanningContext->{'currentTrackNo'} && $scanningContext->{'noOfTracks'}) {
			my $progressPercentage = ($scanningContext->{'currentTrackNo'} / $scanningContext->{'noOfTracks'}) * 100;
			my $rounded = sprintf("%.0f", $progressPercentage);
			$prefs->set('scanprogresspercentage', $rounded);
		}
	}
	return;
}

sub exitScan {
	my $scanningContext = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug('Optimizing SQLite database');
	my $dbh = Slim::Schema->dbh;
	$dbh->do("ANALYZE customtagimporter_track_attributes");
	commit($dbh);
	if (!isScanning(undef)) {
		$scanningAborted = 0;
	}
	@libraryTrackIDs = ();

	$prefs->set('scanningInProgress', 0);

	# scan result: 1 = success, 2 = aborted, 3 = errors
	if ($scanningAborted == 1) {
		$prefs->set('scanResult', 2);
		main::INFOLOG && $log->is_info && $log->info('Rescan aborted after '.(time()-($scanningContext->{'scanStartTime'})).' seconds. Scanned '.$scanningContext->{'currentTrackNo'}.' out of '.$scanningContext->{'noOfTracks'}.' tracks.');
	} elsif ($errors > 0) {
		$prefs->set('scanResult', 3);
		main::INFOLOG && $log->is_info && $log->info('Rescan completed (with errors) after '.(time()-($scanningContext->{'scanStartTime'})).' seconds.');
	} else {
		$prefs->set('scanResult', 1);
		main::INFOLOG && $log->is_info && $log->info('Rescan completed after '.(time()-($scanningContext->{'scanStartTime'})).' seconds.');
	}

	# optional: dump tag names to file
	if (!$scanningContext->{'importerCall'} && $prefs->get('dumptagnames')) {
		my $saveDir = $serverPrefs->get('playlistdir') || Slim::Utils::OSDetect::dirsFor('prefs');
		my $filename = catfile($saveDir, 'CTI_TagNameDump.txt');
		my $output = FileHandle->new($filename, '>:utf8') or do {
				$log->error('could not open '.$filename.' for writing.');
				return;
			};
		print $output "###  Custom Tag Importer - Tag Name Dump  ###\n###  Found these tag names:\n\n";

		foreach my $key (sort keys %dumpedTagNames) {
			print $output $key."\n";
		}
		close $output;
		%dumpedTagNames = ();
	}

	rateScannedTracks($scanningContext) if $prefs->get('writeratingstodb');
}

sub abortScan {
	if ($prefs->get('scanningInProgress') > 0) {
		$scanningAborted = 1;
		main::DEBUGLOG && $log->is_debug && $log->debug('CustomTagImporter: Aborting scanning');
		return;
	}
}

sub isScanning {
	if ($prefs->get('scanningInProgress') > 0) {
		return 1;
	}
	return 0;
}

sub clearDBtable {
	my $dbh = Slim::Schema->dbh;
	my $startTime = time();

	my $clearDBsql = "DROP TABLE customtagimporter_track_attributes";

	eval {
		my $sth = $dbh->prepare($clearDBsql);
		$sth->execute();
		$sth->finish();
		initDatabase();
		main::idleStreams();
	};
	if ($@) {
		$log->error("Database error: $DBI::errstr");
		$errors++;
	} else {
		main::DEBUGLOG && $log->is_debug && $log->debug('Deleted old database table. Took '.(time()-$startTime).' seconds');
	}
	return;
}

sub scanCustomTagTrack {
	my ($track, $scanningContext) = @_;

	my @result = ();
	my @resultVirtual = ();
	my @resultSort = ();

	main::DEBUGLOG && $log->is_debug && $log->debug('Scanning track: '.$track->title);
	my $tags = Slim::Formats->readTags($track->url);

	# dump tag names to file or log tag names + values if debug. But don't if importer call.
	if (!$scanningContext->{'importerCall'} && $prefs->get('dumptagnames')) {
		for my $t (keys %{$tags}) {
			if ($log->is_debug) {
				if ($t ne 'APIC' && $t ne 'GEOB' && $t ne 'PRIV' && $t ne 'ARTWORK' && $t ne 'ASFLeakyBucketPairs' && $t ne 'WM/Picture') {
					main::DEBUGLOG && $log->is_debug && $log->debug("Got tag: $t = ".$tags->{$t});
				} else {
					main::DEBUGLOG && $log->is_debug && $log->debug("Got tag: $t = (binary data)");
				}
				if (ref($tags->{$t}) eq 'ARRAY' && $t ne 'APIC' && $t ne 'GEOB' && $t ne 'PRIV' && $t ne 'PRIV' && $t ne 'ASFLeakyBucketPairs' && $t ne 'WM/Picture') {
					my $array = $tags->{$t};
					for my $item (@{$array}) {
						main::DEBUGLOG && $log->is_debug && $log->debug("Got array item: $item");
					}
				}
			} else {
				$dumpedTagNames{$t} = 1;
			}
		}
	}

	if ($prefs->get('customtagrawmp3tags') && $track->content_type() eq 'mp3') {
		eval {
			getRawMP3Tags($track->url, $tags);
		};
		if ($@) {
			$log->error("CustomTagImporter:CustomTag: Failed to load raw tags from ".$track->url.":$@");
			$errors++;
		}
	}

	my $prefix = "";
	if ($track->content_type() =~ /^wma/) {
		$prefix = "WM/";
	}

	if (defined($tags)) {
		my $customTagProperty = $prefs->get('customtags');
		my $ratingTagsString = $prefs->get('ratingtags');

		my $customTagMappingProperty = $prefs->get('customtagsmapping');
		if (defined($customTagMappingProperty)) {
			$customTagMappingProperty =~ s/\\,/\\COMMA/;
		}
		my $customSortTagProperty = $prefs->get('customsorttags');
		my $singleValueTagProperty = $prefs->get('singlecustomtags');

		if ($customTagProperty || $ratingTagsString) {
			my @singleValueTags = ();
			if ($singleValueTagProperty) {
				@singleValueTags = split(/\s*,\s*/, $singleValueTagProperty);
			}
			my %singleValueTagsHash = ();
			for my $singleValueTag (@singleValueTags) {
				$singleValueTagsHash{uc($singleValueTag)} = 1;
			}

			my %customTagsHash = ();
			if (defined($customTagProperty) && $customTagProperty) {
				my @customTags = split(/\s*,\s*/, $customTagProperty);
				for my $customTag (@customTags) {
					$customTagsHash{uc($customTag)} = 1;
				}
			}

			my %ratingTagsHash = ();
			if (defined($ratingTagsString) && $ratingTagsString) {
				my @ratingTags = split(/\s*,\s*/, $ratingTagsString);
				for my $tag (@ratingTags) {
					$ratingTagsHash{uc($tag)} = 1;
				}
			}

			my %customSortTagsHash = ();
			my %customSortTags = ();
			if (defined($customSortTagProperty) && $customSortTagProperty) {
				my @customSortTags = split(/\s*,\s*/, $customSortTagProperty);
				for my $customSortTag (@customSortTags) {
					if ($customSortTag =~ /^\s*(.*)\s* = \s*(.*).*$/) {
						my $tag = $1;
						my $sortTag = $2;
						$customSortTagsHash{uc($tag)} = uc($sortTag);
						$customSortTags{uc($sortTag)} = 1;
					}
				}
			}
			my %virtualTagsHash = ();
			my %virtualSingleTagsHash = ();
			my @customTagsMappings = split(/,/, $customTagMappingProperty);
			for my $customTagMapping (@customTagsMappings) {
				$customTagMapping =~ s/\\COMMA/,/;
				if ($customTagMapping =~ /^\s*.*?\s*=\s*(oneof|combine|as)\s+(.+)\s*$/) {
					my @parts = split(/\|/, $2);
					for my $part (@parts) {
						if ($part =~ /^\s*([A-Z0-9_]+)\(.*$/) {
							$virtualTagsHash{$1} = 1;
							$virtualSingleTagsHash{$1} = 1;
						} elsif ($part =~ /^\s*([A-Z0-9_]+)\s*$/) {
							$virtualTagsHash{$1} = 1;
						}
					}
				}
			}

			for my $tag (keys %{$tags}) {
				if ($ratingTagsString) {
					if ($track->content_type() eq 'mp3') {
						my $file = Slim::Utils::Misc::pathFromFileURL($track->url);
						my $rawTags = MP3::Info::get_mp3tag($file, 2, 1);
						if ($tag eq 'POPM' || $tag eq 'POP') {
							# Ignore POP/M tag if we already got a rating value from another tag
							if (scalar @result > 0) {
								my %alreadyHasRATINGtag = map { $_->{'name'} => $_ } @result;
								if ($alreadyHasRATINGtag{'RATING'}) {
									main::DEBUGLOG && $log->is_debug && $log->debug('Ignoring POP/M tags. Already got a rating value from another tag.');
									next;
								}
							}

							my @bytes = unpack "C*", $rawTags->{$tag};
							my $email = 1;
							my $rating = 0;
							my $emailText = '';
							for my $c (@bytes) {
								if ($rating) {
									my $ratingNumber = undef;
									if ($emailText =~ /Windows Media Player/) {
										$ratingNumber = floor($c*100/255);
										$ratingNumber = floor(20+$ratingNumber*80/100);
									} else {
										$ratingNumber = floor($c*100/255);
									}
									if ($ratingNumber > 100) {
										$ratingNumber = 100;
									}
									if ($ratingNumber) {
										my %item = (
											'name' => 'RATING',
											'value' => $ratingNumber
										);
										push @result, \%item;
										next;
									}
								}
								if ($email && $c==0) {
									$email = 0;
									$rating = 1;
								} elsif ($email) {
									$emailText .= chr $c;
								}
							}
						}
					}

					my $ratingtagmax = $prefs->get('ratingtagmax');
					if ($ratingtagmax) {
						my $ratingNumber = undef;
						if ($tag eq 'WM/SharedUserRating' || $tag eq 'SHAREDUSERRATING') {
							$ratingNumber = $tags->{$tag};
							if ($ratingNumber && $ratingNumber =~ /^\d+$/) {
								if ($ratingNumber == 99) {
									$ratingNumber = 100;
								} else {
									$ratingNumber = floor((($ratingNumber/25)+1)*20);
								}
							}
						} elsif (defined($ratingTagsHash{uc($tag)})) {
							$ratingNumber = $tags->{$tag};
							if ($ratingNumber && $ratingNumber =~ /^\d+.?\d*$/) {
								$ratingNumber =~ s/,/./;
								$ratingNumber = floor($ratingNumber*100/$ratingtagmax);
								if ($ratingNumber > 100) {
									$ratingNumber = 100;
								}
							}
						}
						if (defined($ratingNumber) && $ratingNumber) {
							# prefer latest rating tag value over previous one (e.g. POPM)
							if (scalar @result > 0) {
								my %alreadyHasRATINGtag = map { $_->{'name'} => $_ } @result;
								if ($alreadyHasRATINGtag{'RATING'}) {
									main::DEBUGLOG && $log->is_debug && $log->debug("Already got a rating value from another tag. Will use new rating value $ratingNumber from tag '$tag'");
									@result = grep { $_->{'name'} ne 'RATING' } @result;
								}
							}

							main::DEBUGLOG && $log->is_debug && $log->debug("Using $tag, adjusted rating is: $ratingNumber");
							my %item = (
								'name' => 'RATING',
								'value' => $ratingNumber
							);
							push @result, \%item;
							next;
						}
					}
				}
				my $ucTag = uc($tag);
				if ($prefix ne "" && $ucTag =~ /^$prefix/) {
					my $tagWithoutPrefix = $ucTag;
					$tagWithoutPrefix =~ s/^$prefix(.*)$/$1/;
					if ($customTagsHash{$tagWithoutPrefix} || $virtualTagsHash{$tagWithoutPrefix} || $customSortTags{$tagWithoutPrefix}) {
						$ucTag = $tagWithoutPrefix;
					}
				}
				if ($customTagsHash{$ucTag} || $virtualTagsHash{$ucTag} || $customSortTags{$ucTag}) {
					my $values = $tags->{$tag};
					if (!defined($singleValueTagsHash{$ucTag}) && !defined($virtualSingleTagsHash{$ucTag})) {
						my @arrayValues = splitTag($tags->{$tag});
						$values = \@arrayValues;
					}
					my $sortValues = undef;
					my $sortTag = $customSortTagsHash{$ucTag};
					if (ref($values) eq 'ARRAY') {
						my $valueArray = $values;
						my $index = 0;
						for my $value (@{$valueArray}) {
							$value =~ s/^\s*//;
							$value =~ s/\s*$//;
							if ($value ne '') {
								my %item = (
									'name' => $ucTag,
									'value' => $value
								);
								if (defined($sortTag)) {
									$item{'sorttag'} = $sortTag;
									$item{'sorttagindex'} = $index;
								}

								if ($customSortTags{$ucTag}) {
									push @resultSort, \%item;
								}
								if ($customTagsHash{$ucTag}) {
									push @result, \%item;
								} elsif ($virtualTagsHash{$ucTag}) {
									push @resultVirtual, \%item;
								}
							}
							$index = $index + 1;
						}
					} else {
						$values =~ s/^\s*//;
						$values =~ s/\s*$//;
						if ($values ne '') {
							my %item = (
								'name' => $ucTag,
								'value' => $values
							);
							if (defined($sortTag)) {
								$item{'sorttag'} = $sortTag;
								$item{'sorttagindex'} = 0;
							}
							if ($customSortTags{$ucTag}) {
								push @resultSort, \%item;
							}
							if ($customTagsHash{$ucTag}) {
								push @result, \%item;
							} elsif ($virtualTagsHash{$ucTag}) {
								push @resultVirtual, \%item;
							}
						}
					}
				}
			}

			my $resultHash = createTagHash(\@result, \@resultVirtual);

			## tag mapping
			if (defined($customTagMappingProperty) && $customTagMappingProperty) {
				my @customTagsMapping = split(/,/, $customTagMappingProperty);
				for my $customTagMapping (@customTagsMapping) {
					$customTagMapping =~ s/\\COMMA/,/;
					# handle TAG = oneof ONETAG|ANOTHERTAG|ATHIRDTAG mappings
					# handle TAG = combine ONETAG|ANOTHERTAG|ATHIRDTAG mappings
					# handle YEAR = as DATE(exp = ^\d\d\d\d)
					# handle MONTH = combine DATE(exp = ^(\d\d\d\d))|DATE(exp = ^\d\d\d\d-(\d\d))
					# handle DECADE = combine YEAR(exp = ^\d\d\d)|YEAR(text=0)
					# handle ARTISTSORT = combine ARTIST(exp = ^.*\s(.*)$)|ARTIST(text=)|ARTIST(exp = ^(.*)\s)
					if ($customTagMapping =~ /^\s*(.*?)\s* = \s*(oneof|combine|as)\s+(.+)\s*$/) {
						main::DEBUGLOG && $log->is_debug && $log->debug("Handling custom mapping: $customTagMapping");
						my $mappingType = $2;
						my @values = ();
						my $tag = uc($1);
						my @parts = split(/\|/, $3);
						#main::DEBUGLOG && $log->is_debug && $log->debug("GOT: ".Data::Dump::dump(\@parts));
						my $lastPart = 0;
						for my $part (@parts) {
							main::DEBUGLOG && $log->is_debug && $log->debug("Handling custom mapping part $part");
							if ($part =~ /^\s*([A-Za-z0-9_\/ ]+)\(exp = (.*)\)\s*$/) {
								if (exists $resultHash->{uc($1)}) {
									my $partTag = uc($1);
									my $partExp = $2;
									main::DEBUGLOG && $log->is_debug && $log->debug("Handling custom mapping exp part $partTag, $partExp");
									my $partTagValues = $resultHash->{$partTag};
									if (ref($partTagValues) eq 'ARRAY') {
										my $orgValue = undef;
										if (scalar(@values)==1) {
											if ($mappingType eq "combine") {
												$orgValue = shift @values;
											} else {
												$orgValue = $values[0];
											}
										}
										my $i = 0;
										for my $partTagValue (@{$partTagValues}) {
											main::DEBUGLOG && $log->is_debug && $log->debug("Checking $partTagValue against $partExp");
											if ($partTagValue =~ /$partExp/) {
												my $currentValue = $1;
												main::DEBUGLOG && $log->is_debug && $log->debug("Checking $partTagValue against $partExp matched! ($currentValue)");
												if ($mappingType eq "oneof" || $mappingType eq "as") {
													push @values, $currentValue;
													$lastPart = 1;
												} elsif ($mappingType eq "combine") {
													if (defined($orgValue)) {
														push @values, $orgValue.$currentValue;
													} elsif (scalar(@{$partTagValues}) != scalar(@values) && scalar(@values) > 0) {
														map { $_ = $_.$currentValue } @values;
														last;
													} elsif (scalar(@{$partTagValues}) != scalar(@values) && scalar(@values) == 0) {
														for my $v (@{$partTagValues}) {
															if ($v =~ /$partExp/) {
																push @values, $1;
															}
														}
														last;
													} else {
														$values[$i] = $values[$i].$currentValue;
													}
												}
											}
											$i++;
										}
									} else {
										main::DEBUGLOG && $log->is_debug && $log->debug("Checking $partTagValues against $partExp");
										if ($partTagValues =~ /$partExp/) {
											my $currentValue = $1;
											main::DEBUGLOG && $log->is_debug && $log->debug("Checking $partTagValues against $partExp matched! ($currentValue)");
											if ($mappingType eq "oneof" || $mappingType eq "as") {
												push @values, $currentValue;
												last;
											} elsif ($mappingType eq "combine") {
												if (scalar(@values) > 0) {
													map { $_ = $_.$currentValue } @values;
												} else {
													push @values, $currentValue;
												}
											}
										}
									}
								}
							} elsif ($part =~ /^\s*([A-Za-z0-9_\/ ]+)\(text=(.*)\)\s*$/) {
								if (exists $resultHash->{uc($1)}) {
									my $currentValue = $2;
									main::DEBUGLOG && $log->is_debug && $log->debug("Handling custom mapping text part ".uc($1).", $currentValue");
									if ($mappingType eq "oneof" || $mappingType eq "as") {
										push @values, $currentValue;
										last;
									} elsif ($mappingType eq "combine") {
										if (scalar(@values) > 0) {
											map { $_ = $_.$currentValue } @values;
										} else {
											push @values, $currentValue;
										}
									}
								}
							} elsif ($part =~ /^\s*([A-Za-z0-9_\/ ]+)\s*$/) {
								if (exists $resultHash->{uc($1)}) {
									my $partTag = uc($1);
									my $partTagValues = $resultHash->{$partTag};
									main::DEBUGLOG && $log->is_debug && $log->debug("Handling custom mapping tag part $partTag");
									if (ref($partTagValues) eq 'ARRAY') {
										my $orgValue = undef;
										if (scalar(@values) == 1) {
											if ($mappingType eq "combine") {
												$orgValue = shift @values;
											} else {
												$orgValue = $values[0];
											}
										}
										my $i = 0;
										for my $partTagValue (@{$partTagValues}) {
											my $currentValue = $partTagValue;
											if ($mappingType eq "oneof" || $mappingType eq "as") {
												push @values, $currentValue;
												$lastPart = 1;
											} elsif ($mappingType eq "combine") {
												if (defined($orgValue)) {
													push @values, $orgValue.$currentValue;
												} elsif (scalar(@{$partTagValues}) != scalar(@values) && scalar(@values) > 0) {
													map { $_ = $_.$currentValue } @values;
													last;
												} elsif (scalar(@{$partTagValues}) != scalar(@values) && scalar(@values) == 0) {
													@values = @{$partTagValues};
													last;
												} else {
													$values[$i] = $values[$i].$currentValue;
												}
											}
											$i++;
										}
									} else {
										my $currentValue = $partTagValues;
										if ($mappingType eq "oneof" || $mappingType eq "as") {
											push @values, $currentValue;
											last;
										} elsif ($mappingType eq "combine") {
											if (scalar(@values) > 0) {
												map { $_ = $_.$currentValue } @values;
											} else {
												push @values, $currentValue;
											}
										}
									}
								}
							}
							if ($lastPart) {
								last;
							}
						}
						#main::DEBUGLOG && $log->is_debug && $log->debug("Got mapping tags: ".Data::Dump::dump(\@values));

						if (scalar(@values) > 0) {
							if (scalar(@values) == 1) {
								$resultHash->{$tag} = $values[0];
							} else {
								$resultHash->{$tag} = \@values;
							}
							my $sortTag = $customSortTagsHash{$tag};
							my $index = 0;
							for my $value (@values) {
								my @subvalues = ($value);
								if (!defined($singleValueTagsHash{$tag})) {
									@subvalues = splitTag($value)
								}
								for my $subvalue (@subvalues) {
									my %item = (
										'name' => $tag,
										'value' => $subvalue
									);
									if (defined($sortTag)) {
										$item{'sorttag'} = $sortTag;
										$item{'sorttagindex'} = $index;
									}
									push @result, \%item;
									$index++;
								}
							}
						}

					}
				}
			}

			if (scalar(@resultVirtual) > 0) {
				$resultHash = createTagHash(\@result, \@resultVirtual);
			} else {
				$resultHash = {};
			}
			my $resultSortHash = createTagHash(\@resultSort);

			for my $item (@result) {
				if (exists $item->{'sorttag'}) {
					my $values = undef;
					if (exists $resultHash->{$item->{'sorttag'}}) {
						$values = $resultHash->{$item->{'sorttag'}};
					} elsif (exists $resultSortHash->{$item->{'sorttag'}}) {
						$values = $resultSortHash->{$item->{'sorttag'}};
					}
					if (defined($values)) {
						if (ref($values) eq 'ARRAY') {
							if (scalar(@{$values}) > $item->{'sorttagindex'}) {
								$item->{'valuesort'} = $values->[$item->{'sorttagindex'}];
							}
						} else {
							$item->{'valuesort'} = $values;
						}
					}
				}
			}

		}
	}
	return \@result;
}

sub rateScannedTracks {
	my $scanningContext = shift;
	if ($prefs->get('scanningInProgress') > 0) {
		main::DEBUGLOG && $log->is_debug && $log->debug("Active scan process detected. Can't write CTI rating tag values to LMS database");
	} else {
		main::DEBUGLOG && $log->is_debug && $log->debug('Writing ratings from CTI rating tags to LMS database');
	}

	my $started = my $totalTimeStarted = time();
	my $RLenabled = Slim::Utils::PluginManager->isEnabled('Plugins::RatingsLight::Plugin');
	my $dbh = Slim::Schema->dbh;

	### get rated CTI tracks (and their rating values)
	my $sqlGetRatedCTItracks = "select customtagimporter_track_attributes.urlmd5, customtagimporter_track_attributes.value from customtagimporter_track_attributes where customtagimporter_track_attributes.type = 'rating' and ifnull(customtagimporter_track_attributes.value, 0) > 0";

	my %ratedCTItracks = ();
	my $sth = $dbh->prepare($sqlGetRatedCTItracks);
	$sth->execute();
	my ($urlmd5, $CTIratingValue);
	$sth->bind_col(1, \$urlmd5);
	$sth->bind_col(2, \$CTIratingValue);
	while ($sth->fetch()) {
		$ratedCTItracks{$urlmd5} = $CTIratingValue;
	}
	$sth->finish();
	main::DEBUGLOG && $log->is_debug && $log->debug('Pt 1: Getting rated CTI tracks and rating values took '.(time() - $started).' seconds.');

	if (scalar keys %ratedCTItracks == 0) {
		main::INFOLOG && $log->is_info && $log->info('CTI table does not contain tracks with rating tags!');
		return;
	}

	### unrate tracks in LMS db

	$started = time();
	my $sqlunrate = "update tracks_persistent set rating = null where tracks_persistent.rating > 0;";
	my $unrate_sth = $dbh->prepare($sqlunrate);
	eval {
		$unrate_sth->execute();
		commit($dbh);
	};
	if ($@) {
		$log->error("Database error: $DBI::errstr");
		eval {
			rollback($dbh);
		};
	}
	$unrate_sth->finish();
	main::DEBUGLOG && $log->is_debug && $log->debug('Pt 2: Unrating tracks in LMS db took '.(time() - $started).' seconds.');

	## write ratings for rated CTI tracks to LMS tracks_persistent

	$started = time();

	my $sqlrate = "update tracks_persistent set rating = ? where tracks_persistent.urlmd5 = ?;";
	my $rate_sth = $dbh->prepare($sqlrate);

	while (my ($ratedTrackurlmd5, $rating100ScaleValue) = each (%ratedCTItracks)) {
		$rating100ScaleValue = int(($rating100ScaleValue + 5)/10) * 10; # adjust rating values to LMS ten step values
		$rating100ScaleValue = 100 if $rating100ScaleValue > 100;

		eval {
			$rate_sth->bind_param(1, $rating100ScaleValue);
			$rate_sth->bind_param(2, $ratedTrackurlmd5);
			$rate_sth->execute();
			commit($dbh);
		};
		if ($@) {
			$log->error("Database error: $DBI::errstr");
			eval {
				rollback($dbh);
			};
		}
	}
	$rate_sth->finish();
	main::DEBUGLOG && $log->is_debug && $log->debug('Pt 3: Writing ratings for rated CTI tracks to LMS tracks_persistent took '.(time() - $started).' seconds.');

	if ($scanningContext->{'isReset'}) {
		main::INFOLOG && $log->is_info && $log->info('Resetting LMS ratings to CTI rating values took '.(time() - $totalTimeStarted).' seconds.');
	} else {
		main::INFOLOG && $log->is_info && $log->info('Writing CTI rating values to LMS database took '.(time() - $totalTimeStarted).' seconds.');
	}

	Plugins::RatingsLight::Plugin::refreshAll(1) if !$scanningContext->{'importerCall'} && $RLenabled;
}

sub resetRatingsToCTIvalues {
	my $scanningContext->{'isReset'} = 1;
	rateScannedTracks($scanningContext);
}

sub createTagHash {
	my $array1 = shift;
	my $array2 = shift;

	my %resultHash = ();
	my @items = @{$array1};
	if (defined($array2)) {
		push @items, @{$array2};
	}

	for my $item (@items) {
		if (exists $resultHash{$item->{'name'}}) {
			my $values = undef;
			if (ref($resultHash{$item->{'name'}}) eq 'ARRAY') {
				$values = $resultHash{$item->{'name'}};
			} else {
				my @newArray = ($resultHash{$item->{'name'}});
				$values = \@newArray;
				$resultHash{$item->{'name'}} = $values;
			}
			push @{$values}, $item->{'value'} if defined($item->{'value'}) && $item->{'value'} ne "";
		} else {
			$resultHash{$item->{'name'}} = $item->{'value'} if defined($item->{'value'}) && $item->{'value'} ne "";
		}
	}
	return \%resultHash;
}

sub splitTag {
	my $value = shift;

	my @arrayValues = ();
	if (ref($value) eq 'ARRAY') {
		for my $v (@{$value}) {
			my @subArrayValues = Slim::Music::Info::splitTag($v);
			if (scalar(@subArrayValues) > 0) {
				push @arrayValues, @subArrayValues;
			}
		}
	} else {
		@arrayValues = Slim::Music::Info::splitTag($value);
	}
	return @arrayValues;
}

sub getRawMP3Tags {
	my $url = shift;
	my $tags = shift;

	my $rawTags;
	my $file = Slim::Utils::Misc::pathFromFileURL($url);
	$rawTags = MP3::Info::get_mp3tag($file, 2, 1);

	for my $t (keys %{$rawTags}) {
		if (defined($rawTags->{$t}) && defined($rawTagNames{$t}) && ref($rawTags->{$t}) ne 'ARRAY') {
			my $tagName = $rawTagNames{$t};
			if (!defined($tags->{$tagName})) {
				my $value = $rawTags->{$t};
				my $encoding = '';
				if ($value =~ /^(.)/) {
					$encoding = $1;
					if ($encoding eq "\001" || $encoding eq "\002" || $encoding eq "\003") {
						# strip first char (text encoding)
						$value =~ s/^.//;
					}
				}
				if ($encoding eq "\001" || $encoding eq "\002") {
					$value = eval { Slim::Utils::Unicode::decode('utf16', $value) } || Slim::Utils::Unicode::decode('utf16le', $value);
				} elsif ($encoding eq "\003") {
					$value = Slim::Utils::Unicode::decode('utf8', $value);
				}
				# Remove null character at end
				$value =~ s/\0$//;
				$value =~ s/^\0//;
				main::DEBUGLOG && $log->is_debug && $log->debug("Got raw tag: $tagName($t) = ".$value);
				$tags->{$tagName} = $value;
			} else {
				main::DEBUGLOG && $log->is_debug && $log->debug("Got normal tag: $tagName($t) = ".$tags->{$tagName});
			}
		} else {
			main::DEBUGLOG && $log->is_debug && $log->debug("Ignoring tag: $t");
		}
	}
}

sub countAvailableCustomTags {
	my $dbh = Slim::Schema->dbh;
	my $customTagSql = "select count(distinct attr) from customtagimporter_track_attributes where type='customtag' group by attr";
	my $thisCount;
	my $sth = $dbh->prepare($customTagSql);
	$sth->execute();
	$sth->bind_columns(undef, \$thisCount);
	$sth->fetch();
	$sth->finish;
	return $thisCount;
}

sub commit {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->commit();
	}
}

sub rollback {
	my $dbh = shift;
	if (!$dbh->{'AutoCommit'}) {
		$dbh->rollback();
	}
}

1;
