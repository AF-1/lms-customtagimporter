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

package Plugins::CustomTagImporter::Plugin;

use strict;
use warnings;
use utf8;

use base qw(Slim::Plugin::Base);

use Slim::Utils::Prefs;
use Slim::Buttons::Home;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Log;
use File::Spec::Functions qw(:ALL);
use Scalar::Util qw(blessed looks_like_number);
use HTML::Entities;

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
my $availableCTItitleFormats = ();

sub initPlugin {
	my $class = shift;
	$class->SUPER::initPlugin(@_);
	initDatabase();

	initPrefs();
	Slim::Control::Request::subscribe(\&_setRefreshCBTimer, [['rescan'], ['done']]);
	Slim::Control::Request::addDispatch(['customtagimporter', 'changedstatus','_status'],[0, 0, 0, undef]);

	if (main::WEBUI) {
		require Plugins::CustomTagImporter::Settings::Basic;
		require Plugins::CustomTagImporter::Settings::TagList;
		require Plugins::CustomTagImporter::Settings::DisplayedTagInfo;
		Plugins::CustomTagImporter::Settings::Basic->new($class);
		Plugins::CustomTagImporter::Settings::TagList->new($class);
		Plugins::CustomTagImporter::Settings::DisplayedTagInfo->new($class);
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
	my $data = Plugins::CustomTagImporter::CBTemplateReader::readTemplateData('CustomTagImporter', 'CBMenuTemplates', $templateItem->{'id'});
	return $data;
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
	my $data = Plugins::CustomTagImporter::CBTemplateReader::readTemplateData('CustomTagImporter', 'CBContextMenuTemplates', $templateItem->{'id'});
	return $data;
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

	my $currentTime = time();
	my $parameters = $filter->{'parameter'};
	my $result = 0;
	my $dbh = Slim::Schema->storage->dbh();
	if (($filter->{'id'} eq 'customtagimporter_customtag_customtag') || ($filter->{'id'} eq 'customtagimporter_customtag_notcustomtag')) {
		for my $parameter (@{$parameters}) {
			if ($parameter->{'id'} eq 'customtag') {
				my $values = $parameter->{'value'};
				my $customtag = $values->[0] if (defined($values) && scalar(@{$values}) > 0);

				my $sth = $dbh->prepare("select track from customtagimporter_track_attributes where track = $trackID and type='customtag' and attr = \"$customtag\"");
				$result = 1 if $filter->{'id'} eq 'customtagimporter_customtag_notcustomtag';
				eval {
					$sth->execute();
					if ($sth->fetch()) {
						$result = ($filter->{'id'} eq 'customtagimporter_customtag_notcustomtag') ? 0 : 1;
					}
				};
				if ($@) {
					$log->error("Error executing SQL: $@\n$DBI::errstr");
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

		if ($customtag && $logop & $customtagvalue) {
			my $dbh = Slim::Schema->storage->dbh();
			my $sql = "select track from customtagimporter_track_attributes where track=$trackID and type='customtag' and attr=\"$customtag\" and value ";

			if ($logop eq 'lt') {
				$sql .= "< ";
			} elsif ($logop eq 'le') {
				$sql .= "<= ";
			} elsif ($logop eq 'ge') {
				$sql .= ">= ";
			} elsif ($logop eq 'gt') {
				$sql .= "> ";
			} elsif ($logop eq 'eq') {
				$sql .= "= ";
				$customtagvalue = quoteValue($customtagvalue);
			} elsif ($logop eq 'contains') {
				$sql .= "like ";
				$customtagvalue = quoteValue($customtagvalue);
			} elsif ($logop eq 'oneof') {
				$sql .= "in (";
				my @paramvalues = split(/;/, $customtagvalue);
				my $quotedTextVal;

				foreach (@paramvalues) {
					my $thisParamVal = quoteValue($_);
					main::DEBUGLOG && $log->is_debug && $log->debug("thisParamVal = ".Data::Dump::dump($thisParamVal));

					if (looks_like_number($thisParamVal)) {
						$quotedTextVal .= ($quotedTextVal ? ',' : '').encode_entities(trim_leadtail($thisParamVal), "&<>\'\"");
					} else {
						$quotedTextVal .= ($quotedTextVal ? ',' : '')."'".encode_entities(trim_leadtail($thisParamVal), "&<>\'\"")."'";
					}
				}
				$customtagvalue = $quotedTextVal;
			}
			$sql .= "\"" unless $logop eq 'oneof';
			if ($logop eq 'contains') {
				$sql .= "%%";
			}
			$sql .= "$customtagvalue";
			if ($logop eq 'contains') {
				$sql .= "%%";
			}
			$sql .= "\"" unless $logop eq 'oneof';
			if ($logop eq 'oneof') {
				$sql .= ")";
			}

			main::DEBUGLOG && $log->is_debug && $log->debug("sql = ".$sql);
			my $sth = $dbh->prepare($sql);
			$result = 1 if $filter->{'id'} eq 'customtagimporter_customtag_notcustomtagvalue';
			eval {
				$sth->execute();
				if ($sth->fetch()) {
					$result = ($filter->{'id'} eq 'customtagimporter_customtag_notcustomtagvalue') ? 0 : 1;
				}
			};
			if ($@) {
				$result = 0;
				$log->error("Error executing SQL: $@\n$DBI::errstr");
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

	my $availableCustomTags = Plugins::CustomTagImporter::Plugin::getAvailableCustomTags();
	main::DEBUGLOG && $log->is_debug && $log->debug('available custom tags = '.Data::Dump::dump($availableCustomTags));

	if (keys %{$availableCustomTags} > 0 && keys %{$configmatrix} > 0) {
		foreach my $thisCustomTag (sort keys %{$availableCustomTags}) {
			main::DEBUGLOG && $log->is_debug && $log->debug('thisCustomTag = '.$thisCustomTag);

			## register track info provider

			my $songdetailsmenuenabled = $configmatrix->{$thisCustomTag}->{'songdetailsmenuenabled'};
			my $songdetailsmenuname = $configmatrix->{$thisCustomTag}->{'songdetailsmenuname'};
			my $songdetailsmenuposition = $configmatrix->{$thisCustomTag}->{'songdetailsmenuposition'};


			if (defined $songdetailsmenuenabled && defined $songdetailsmenuname && defined $songdetailsmenuposition) {
				my $regID = 'CTI_TIHregID_'.$thisCustomTag;
				main::DEBUGLOG && $log->is_debug && $log->debug('trackinfohandler ID = '.$regID);
				Slim::Menu::TrackInfo->deregisterInfoProvider($regID);

				my $possiblecontextmenupositions = [
					"after => 'artwork'", # 0
					"after => 'bottom'", # 1
					"parent => 'moreinfo', isa => 'top'", # 2
					"parent => 'moreinfo', isa => 'bottom'" # 3
				];
				my $thisPos = @{$possiblecontextmenupositions}[$songdetailsmenuposition];
				Slim::Menu::TrackInfo->registerInfoProvider($regID => (
					eval($thisPos),
					func => sub {
						return getTrackInfo(@_,$thisCustomTag);
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
	my ($customtag, $track, $infohandlerCaller) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug('getting CTI values for custom tag = '.$customtag);
	my $result = '';

	if (Slim::Music::Import->stillScanning) {
		$log->warn('Warning: not available until library scan is completed');
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
	my $sth = $dbh->prepare("select value from customtagimporter_track_attributes where type = 'customtag' and attr = \"$customtag\" and track = $trackID");
	my $value;

	eval {
		$sth->execute();
		$sth->bind_col(1, \$value);
		while ($sth->fetch()) {
			$result .= ', ' if $result;
			$value = Slim::Utils::Unicode::utf8decode($value, 'utf8');
			$result .= $value;
		}
		$sth->finish();
	};
	if ($@) {
		$log->error("Database error: $DBI::errstr");
	}
	main::DEBUGLOG && $log->is_debug && $log->debug("CTI values for customtag \"$customtag\" = $result");
	return $result;
}

sub getAvailableCustomTags {
	my $dbh = Slim::Schema->dbh;
	my %result = ();
	my $sth = $dbh->prepare("SELECT attr from customtagimporter_track_attributes where type = 'customtag' group by attr order by attr");
	my $attr;
	$sth->execute();
	$sth->bind_col(1,\$attr);
	while ($sth->fetch()) {
		$result{$attr} = 1;
	}
	$sth->finish();
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

	foreach my $format (@{$titleFormats}) {
		if ($titleformat eq $format) {
			return;
		}
	}
	main::DEBUGLOG && $log->is_debug && $log->debug("Adding to server title format list: $titleformat");
	push @{$titleFormats}, $titleformat;
	$serverPrefs->set('titleFormat', $titleFormats);
}

sub quoteValue {
	my $value = shift;
	$value =~ s/\'/\'\'/g;
	return $value;
}

sub trim_leadtail {
	my ($str) = @_;
	$str =~ s{^\s+}{};
	$str =~ s{\s+$}{};
	return $str;
}

sub trim_all {
	my ($str) = @_;
	$str =~ s/ //g;
	return $str;
}

1;
