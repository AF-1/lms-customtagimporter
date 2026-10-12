#
# Custom Tag Importer
# (c) 2021 AF
# Licensed under the GPLv3 - see LICENSE file
#

package Plugins::CustomTagImporter::Plugin;

use strict;
use warnings;
use utf8;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(cstring);
use Slim::Utils::Log;
use File::Basename qw(dirname);
use Scalar::Util qw(blessed);

use Plugins::CustomTagImporter::Common ':all';
use Plugins::CustomTagImporter::Importer;
use Plugins::CustomTagImporter::CBTemplateReader;

my $prefs = preferences('plugin.customtagimporter');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log->addLogCategory({
	'category' => 'plugin.customtagimporter',
	'defaultLevel' => 'ERROR',
	'description' => 'PLUGIN_CUSTOMTAGIMPORTER',
});

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	initDatabase();

	initPrefs();
	Slim::Control::Request::subscribe(\&_setRefreshCBTimer, [['rescan'], ['done']]);
	Slim::Control::Request::addDispatch(['customtagimporter', 'changedstatus','_status'],[0, 0, 0, undef]);
	Slim::Control::Request::addDispatch(['customtagimporter', 'rescanfolder', '_folderId'], [0, 0, 0, \&_cliRescanFolder]);
	Slim::Menu::FolderInfo->registerInfoProvider(customtagimporter_rescanfolder => (
		after => 'bottom',
		func => \&_folderRescanMenu,
	));

	if (main::WEBUI) {
		require Plugins::CustomTagImporter::Settings::Basic;
		require Plugins::CustomTagImporter::Settings::TagList;
		require Plugins::CustomTagImporter::Settings::DisplayedTagInfo;
		Plugins::CustomTagImporter::Settings::Basic->new($class);
		Plugins::CustomTagImporter::Settings::TagList->new($class);
		Plugins::CustomTagImporter::Settings::DisplayedTagInfo->new($class);
		Slim::Web::Pages->addPageFunction('plugins/CustomTagImporter/rescanfolder', \&_rescanFolderWeb);
	}
}

sub postinitPlugin {
	initMatrix();
}

sub initPrefs {
	$prefs->init({
		'postscanscheduledelay' => 10,
		'ratingtagmax' => 100,
	});
	$prefs->set('scanningInProgress', 0);
	$prefs->set('scanResult', 0);
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 1, 'high' => 255}, 'ratingtagmax');

	$prefs->setChange(\&Plugins::CustomTagImporter::Importer::toggleUseImporter, 'autorescan');
	$prefs->setChange(sub {
			main::DEBUGLOG && $log->is_debug && $log->debug('Change in selected title formats detected. Refreshing titleformats. Changes to your selection might require a server restart to take effect.');
			_setRefreshCBTimer();
		}, 'selectedtitleformats');
	$prefs->setChange(sub {
			main::DEBUGLOG && $log->is_debug && $log->debug('Change in custom tag config matrix detected. Reinitializing trackinfohandler & titleformats.');
			initMatrix();
			Slim::Music::Info::clearFormatDisplayCache();
		}, 'customtagconfigmatrix');
}

sub _folderRescanMenu {
	my ($client, $tags) = @_;

	return unless $tags->{'folder_id'} && $tags->{'folder_id'} > 0;
	return unless $prefs->get('customtags') || $prefs->get('ratingtags');

	if ($tags->{'menuMode'}) {
		return {
			name => cstring($client, 'PLUGIN_CUSTOMTAGIMPORTER_RESCANFOLDER'),
			type => 'link',
			passthrough => [$tags->{'folder_id'}],
			url => \&_folderRescanCallback,
			jive => {
				actions => {
					go => {
						player => 0,
						cmd => ['customtagimporter', 'rescanfolder', $tags->{'folder_id'}],
						nextWindow => 'parent',
					},
				},
			},
			favourites => 0,
		};
	}

	return {
		type => 'text',
		name => cstring($client, 'PLUGIN_CUSTOMTAGIMPORTER_RESCANFOLDER'),
		folderid => $tags->{'folder_id'},
		web => {
			type => 'htmltemplate',
			value => 'plugins/CustomTagImporter/html/rescanfolderlink.html',
		},
	};
}

sub _folderRescanCallback {
	my ($client, $callback, undef, $folderId) = @_;

	# the web UI templates call code refs without arguments when they access the item's url, so ignore such calls
	return unless $folderId;

	$callback->({
		type => 'text',
		name => cstring($client, _startFolderRescan($folderId) ? 'PLUGIN_CUSTOMTAGIMPORTER_RESCANFOLDER_STARTED' : 'PLUGIN_CUSTOMTAGIMPORTER_RESCANFOLDER_NOTSTARTED'),
		showBriefly => 1,
		nextWindow => 'parent',
	});
}

sub _cliRescanFolder {
	my $request = shift;

	if (_startFolderRescan($request->getParam('_folderId'))) {
		$request->setStatusDone();
	} else {
		$request->setStatusBadParams();
	}
}

sub _startFolderRescan {
	my $folderId = shift;

	return 0 unless defined $folderId && $folderId =~ /^[1-9]\d*$/;

	my $folder = Slim::Schema->find('Track', $folderId);
	return 0 unless blessed($folder) && $folder->content_type eq 'dir' && !isScanning() && !Slim::Music::Import->stillScanning;

	my $folderUrl = $folder->url;
	$folderUrl .= '/' unless $folderUrl =~ m{/$};
	rescan(0, $folderUrl);
	return 1;
}

sub _rescanFolderWeb {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $folderId = $params->{'folderid'};
	$params->{'started'} = _startFolderRescan($folderId);

	# landing page: the folder list one level above the rescanned folder
	my $folder = ($folderId && $folderId =~ /^[1-9]\d*$/) ? Slim::Schema->find('Track', $folderId) : undef;
	if (blessed($folder)) {
		my $parent = Slim::Schema->objectForUrl({url => Slim::Utils::Misc::fileURLFromPath(dirname(Slim::Utils::Misc::pathFromFileURL($folder->url)))});
		$params->{'parentfolderid'} = $parent->id if blessed($parent) && $parent->content_type eq 'dir';
	}

	return Slim::Web::HTTP::filltemplatefile('plugins/CustomTagImporter/html/rescanfolder.html', $params);
}


sub getCustomBrowseMenusTemplates {
	return getCustomBrowseTemplates(@_);
}

sub getCustomBrowseTemplates {
	my ($client, $pluginVersion) = @_;
	my $CBversion = Slim::Utils::PluginManager->isEnabled('Plugins::CustomBrowseMenus::Plugin') ? 'CustomBrowseMenus' : 'CustomBrowse';
	return Plugins::CustomTagImporter::CBTemplateReader::getTemplates($client, 'CustomTagImporter', $pluginVersion, 'PluginCache/'.$CBversion, 'CBMenuTemplates', 'xml');
}

sub getCustomBrowseMenusTemplateData {
	return getCustomBrowseTemplateData(@_);
}

sub getCustomBrowseTemplateData {
	my ($client, $templateItem, $parameterValues) = @_;
	return Plugins::CustomTagImporter::CBTemplateReader::readTemplateData('CustomTagImporter', 'CBMenuTemplates', $templateItem->{'id'});
}

sub getCustomBrowseMenusContextTemplates {
	return getCustomBrowseContextTemplates(@_);
}

sub getCustomBrowseContextTemplates {
	my ($client, $pluginVersion) = @_;
	my $CBversion = Slim::Utils::PluginManager->isEnabled('Plugins::CustomBrowseMenus::Plugin') ? 'CustomBrowseMenus' : 'CustomBrowse';
	return Plugins::CustomTagImporter::CBTemplateReader::getTemplates($client, 'CustomTagImporter', $pluginVersion, 'PluginCache/'.$CBversion, 'CBContextMenuTemplates', 'xml');
}

sub getCustomBrowseMenusContextTemplateData {
	return getCustomBrowseContextTemplateData(@_);
}

sub getCustomBrowseContextTemplateData {
	my ($client, $templateItem, $parameterValues) = @_;
	return Plugins::CustomTagImporter::CBTemplateReader::readTemplateData('CustomTagImporter', 'CBContextMenuTemplates', $templateItem->{'id'});
}


sub getCustomSkipFilterTypes {
	my @result = ();

	my %customtag = (
		'id' => 'customtagimporter_customtag_customtag',
		'name' => 'Custom tag',
		'filtercategory' => 'songs',
		'description' => 'Skip songs with a specific custom tag',
		'parameters' => [
			{
				'id' => 'customtag',
				'type' => 'sqlsinglelist',
				'name' => 'Custom tag',
				'data' => 'select distinct attr, attr, attr from customtagimporter_track_attributes order by attr'
			}
		]
	);
	push @result, \%customtag;
	my %notcustomtag = (
		'id' => 'customtagimporter_customtag_notcustomtag',
		'name' => 'Not Custom tag',
		'filtercategory' => 'songs',
		'description' => 'Skip songs that do not have a specific custom tag',
		'parameters' => [
			{
				'id' => 'customtag',
				'type' => 'sqlsinglelist',
				'name' => 'Custom tag',
				'data' => 'select distinct attr, attr, attr from customtagimporter_track_attributes order by attr'
			}
		]
	);
	push @result, \%notcustomtag;

	my %customtagvalue = (
		'id' => 'customtagimporter_customtag_customtagvalue',
		'name' => 'Custom tag value',
		'filtercategory' => 'songs',
		'description' => 'Skip songs with specific custom tag value(s)',
		'parameters' => [
			{
				'id' => 'customtag',
				'type' => 'sqlsinglelist',
				'name' => 'Custom tag',
				'data' => 'select distinct attr, attr, attr from customtagimporter_track_attributes order by attr'
			},
			{
				'id' => 'logop',
				'type' => 'singlelist',
				'name' => '',
				'data' => 'lt=Less than,le=Less than or equal to,ge=Greater than or equal to,gt=Greater than,eq=Equal to (single value),contains=Contains (string),oneof=Equal to one of multiple values',
				'value' => 'eq'
			},
			{
				'id' => 'customtagvalue',
				'type' => 'text',
				'name' => 'Custom tag value<br>(case sensitive, use semicolon to separate multiple values)',
			}
		]
	);
	push @result, \%customtagvalue;

	my %notcustomtagvalue = (
		'id' => 'customtagimporter_customtag_notcustomtagvalue',
		'name' => 'Not custom tag value',
		'filtercategory' => 'songs',
		'description' => 'Skip songs that do NOT have specific custom tag values',
		'parameters' => [
			{
				'id' => 'customtag',
				'type' => 'sqlsinglelist',
				'name' => 'Custom tag',
				'data' => 'select distinct attr, attr, attr from customtagimporter_track_attributes order by attr'
			},
			{
				'id' => 'logop',
				'type' => 'singlelist',
				'name' => '',
				'data' => 'lt=Less than,le=Less than or equal to,ge=Greater than or equal to,gt=Greater than,eq=Equal to (single value),contains=Contains (string),oneof=Equal to one of multiple values',
				'value' => 'eq'
			},
			{
				'id' => 'customtagvalue',
				'type' => 'text',
				'name' => 'Custom tag value<br>(case sensitive, use semicolon to separate multiple values)',
			}
		]
	);
	push @result, \%notcustomtagvalue;

	return \@result;
}

sub checkCustomSkipFilterType {
	my ($client, $filter, $track) = @_;
	my $trackID = $track->id;

	my $parameters = $filter->{'parameter'};
	my $result = 0;
	my $dbh = Slim::Schema->storage->dbh();
	if (($filter->{'id'} eq 'customtagimporter_customtag_customtag') || ($filter->{'id'} eq 'customtagimporter_customtag_notcustomtag')) {
		for my $parameter (@{$parameters}) {
			if ($parameter->{'id'} eq 'customtag') {
				my $values = $parameter->{'value'};
				my $customtag = (defined($values) && scalar(@{$values}) > 0) ? $values->[0] : undef;

				my $sth = $dbh->prepare("select track from customtagimporter_track_attributes where track = ? and type = 'customtag' and attr = ?");
				$result = 1 if $filter->{'id'} eq 'customtagimporter_customtag_notcustomtag';
				eval {
					$sth->execute($trackID, $customtag);
					if ($sth->fetch()) {
						$result = ($filter->{'id'} eq 'customtagimporter_customtag_notcustomtag') ? 0 : 1;
					}
				};
				if ($@) {
					$log->error("Error executing SQL: $@");
				}
				$sth->finish();
				last;
			}
		}
	} elsif (($filter->{'id'} eq 'customtagimporter_customtag_customtagvalue') || ($filter->{'id'} eq 'customtagimporter_customtag_notcustomtagvalue')) {
		# get filter param values
		my ($customtag, $logop, $customtagvalue);
		for my $parameter (@{$parameters}) {
			if ($parameter->{'id'} eq 'customtag') {
				my $values = $parameter->{'value'};
				$customtag = $values->[0] if (defined($values) && scalar(@{$values}) > 0);
			}
			if ($parameter->{'id'} eq 'logop') {
				my $values = $parameter->{'value'};
				$logop = $values->[0] if (defined($values) && scalar(@{$values}) > 0);
			}
			if ($parameter->{'id'} eq 'customtagvalue') {
				my $values = $parameter->{'value'};
				$customtagvalue = $values->[0] if (defined($values) && scalar(@{$values}) > 0);
			}
		}
		main::DEBUGLOG && $log->is_debug && $log->debug("customtag = ".Data::Dump::dump($customtag)."\nlogop = ".Data::Dump::dump($logop)."\ncustomtagvalue = ".Data::Dump::dump($customtagvalue));

		if ($customtag && $logop && defined($customtagvalue) && $customtagvalue ne '') {
			# values are bound as parameters, only operators and placeholders are added to the statement
			my $sql = "select track from customtagimporter_track_attributes where track = ? and type = 'customtag' and attr = ? and value ";
			my @values = ($customtagvalue);

			if ($logop eq 'lt') {
				$sql .= "< ?";
			} elsif ($logop eq 'le') {
				$sql .= "<= ?";
			} elsif ($logop eq 'ge') {
				$sql .= ">= ?";
			} elsif ($logop eq 'gt') {
				$sql .= "> ?";
			} elsif ($logop eq 'eq') {
				$sql .= "= ?";
			} elsif ($logop eq 'contains') {
				$sql .= "like ?";
				@values = ('%'.$customtagvalue.'%');
			} elsif ($logop eq 'oneof') {
				@values = map { trim_leadtail($_) } split(/;/, $customtagvalue);
				$sql .= "in (".join(',', ('?') x scalar(@values)).")";
			} else {
				return $result;
			}

			main::DEBUGLOG && $log->is_debug && $log->debug("sql = ".$sql);
			my $sth = $dbh->prepare($sql);
			$result = 1 if $filter->{'id'} eq 'customtagimporter_customtag_notcustomtagvalue';
			eval {
				$sth->execute($trackID, $customtag, @values);
				if ($sth->fetch()) {
					$result = ($filter->{'id'} eq 'customtagimporter_customtag_notcustomtagvalue') ? 0 : 1;
				}
			};
			if ($@) {
				$result = 0;
				$log->error("Error executing SQL: $@");
			}
			$sth->finish();
			main::DEBUGLOG && $log->is_debug && $log->debug('Should '.($result ? '' : 'not ').'be skipped.');
		}
	}

	return $result;
}


sub initMatrix {
	main::DEBUGLOG && $log->is_debug && $log->debug('Start initializing trackinfohandler & titleformats.');
	my $configmatrix = $prefs->get('customtagconfigmatrix');

	my $availableCustomTags = getAvailableCustomTags();
	main::DEBUGLOG && $log->is_debug && $log->debug('available custom tags = '.Data::Dump::dump($availableCustomTags));

	if (keys %{$availableCustomTags} > 0 && keys %{$configmatrix} > 0) {
		foreach my $thisCustomTag (sort keys %{$availableCustomTags}) {
			main::DEBUGLOG && $log->is_debug && $log->debug('thisCustomTag = '.$thisCustomTag);

			## register track info provider
			my $songdetailsmenuenabled = $configmatrix->{$thisCustomTag}->{'songdetailsmenuenabled'};
			my $songdetailsmenuname = $configmatrix->{$thisCustomTag}->{'songdetailsmenuname'};
			my $songdetailsmenuposition = $configmatrix->{$thisCustomTag}->{'songdetailsmenuposition'};

			# remove a menu entry registered earlier in case it got disabled in the meantime
			Slim::Menu::TrackInfo->deregisterInfoProvider('CTI_TIHregID_'.$thisCustomTag);

			if (defined $songdetailsmenuenabled && defined $songdetailsmenuname && defined $songdetailsmenuposition) {
				my %contextmenupositions = (
					0 => [after => 'artwork'],
					1 => [after => 'bottom'],
					2 => [parent => 'moreinfo', isa => 'top'],
					3 => [parent => 'moreinfo', isa => 'bottom'],
				);
				if (!exists $contextmenupositions{$songdetailsmenuposition}) {
					$log->error("Invalid songdetailsmenuposition: $songdetailsmenuposition");
					next;
				}
				Slim::Menu::TrackInfo->registerInfoProvider('CTI_TIHregID_'.$thisCustomTag => (
					@{$contextmenupositions{$songdetailsmenuposition}},
					func => sub {
						return getTrackInfo(@_, $thisCustomTag);
					}
				));
			}

			## add title format
			my $titleformatenabled = $configmatrix->{$thisCustomTag}->{'titleformatenabled'};

			if (defined $titleformatenabled) {
				my $TF_name = 'CTI_'.uc(trim_all($thisCustomTag));
				main::DEBUGLOG && $log->is_debug && $log->debug('Registering titleformat name = '.$TF_name);
				addTitleFormat($TF_name);
				Slim::Music::TitleFormatter::addFormat($TF_name, sub {
					return getTitleFormat(@_,$thisCustomTag);
				}, 1);
			}
		}
		Slim::Music::Info::clearFormatDisplayCache();
	}
	main::DEBUGLOG && $log->is_debug && $log->debug('Finished initializing trackinfohandler & titleformats.');
}

sub getTitleFormat {
	my ($track, $customtag) = @_;
	return '' if (!$track || !$customtag);
	main::DEBUGLOG && $log->is_debug && $log->debug('customtag = '.$customtag);

	my $TF_string = getCustomTagValuesForTrack($customtag, $track);

	main::INFOLOG && $log->is_info && $log->info('returned title format display string for track = '.Data::Dump::dump($TF_string));
	return $TF_string;
}

sub getTrackInfo {
	my ($client, $url, $track, $remoteMeta, $tags, $filter, $customtag) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug('customtag = '.$customtag);

	my $returnString = getCustomTagValuesForTrack($customtag, $track);

	if ($returnString) {
		my $configmatrix = $prefs->get('customtagconfigmatrix');
		my $songdetailsmenuname = $configmatrix->{$customtag}->{'songdetailsmenuname'};

		main::INFOLOG && $log->is_info && $log->info('Got track info - '.$songdetailsmenuname.': '.$returnString);
		return {
			type => 'text',
			name => $songdetailsmenuname.': '.$returnString,
			itemvalue => $returnString,
			itemid => $track->id,
		};
	}
	return;
}

sub getCustomTagValuesForTrack {
	my ($customtag, $track) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug('getting CTI values for custom tag = '.$customtag);
	my $result = '';

	if (Slim::Music::Import->stillScanning) {
		$log->warn('Not available until library scan is completed');
		return $result;
	}

	if ($track && !blessed($track)) {
		main::DEBUGLOG && $log->is_debug && $log->debug('track is not blessed');
		$track = Slim::Schema->find('Track', $track->{id});
		if (!blessed($track)) {
			main::DEBUGLOG && $log->is_debug && $log->debug('No track object found');
			return $result;
		}
	}

	my $trackID = $track->id;
	my $dbh = Slim::Schema->dbh;
	my $sth = $dbh->prepare("select value from customtagimporter_track_attributes where type = 'customtag' and attr = ? and track = ?");
	my $value;

	eval {
		$sth->execute($customtag, $trackID);
		$sth->bind_col(1, \$value);
		while ($sth->fetch()) {
			$result .= ', ' if $result;
			$value = Slim::Utils::Unicode::utf8decode($value, 'utf8');
			$result .= $value;
		}
		$sth->finish();
	};
	if ($@) {
		$log->error("Database error: $@");
	}
	main::DEBUGLOG && $log->is_debug && $log->debug("CTI values for customtag \"$customtag\" = $result");
	return $result;
}

sub getAvailableCustomTags {
	my $dbh = Slim::Schema->dbh;
	my %result = ();
	my $sth = $dbh->prepare("SELECT attr FROM customtagimporter_track_attributes WHERE type = 'customtag' GROUP BY attr ORDER BY attr");
	eval {
		$sth->execute();
		my $attr;
		$sth->bind_col(1, \$attr);
		while ($sth->fetch()) {
			$result{$attr} = 1;
		}
		$sth->finish();
	};
	if ($@) {
		$log->error("Database error: $@");
	}
	return \%result;
}

sub _setRefreshCBTimer {
	main::DEBUGLOG && $log->is_debug && $log->debug('Killing existing timers for refresh to prevent multiple calls');
	Slim::Utils::Timers::killOneTimer(undef, \&delayedRefresh);
	main::DEBUGLOG && $log->is_debug && $log->debug('Scheduling a delayed refresh');
	Slim::Utils::Timers::setTimer(undef, time() + 2, \&delayedRefresh);
}

sub delayedRefresh {
	if (Slim::Music::Import->stillScanning) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Scan in progress. Waiting for current scan to finish.');
		_setRefreshCBTimer();
	} else {
		main::DEBUGLOG && $log->is_debug && $log->debug('Starting refresh.');
		initMatrix();
	}
}

sub addTitleFormat {
	my $titleformat = shift;
	my $titleFormats = $serverPrefs->get('titleFormat');

	return if grep { $_ eq $titleformat } @{$titleFormats};
	main::DEBUGLOG && $log->is_debug && $log->debug("Adding to server title format list: $titleformat");
	push @{$titleFormats}, $titleformat;
	$serverPrefs->set('titleFormat', $titleFormats);
}

1;
