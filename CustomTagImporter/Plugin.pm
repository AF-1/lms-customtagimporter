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
	refreshTitleFormats();
	Slim::Control::Request::subscribe(\&_setRefreshCBTimer, [['rescan'], ['done']]);

	if (main::WEBUI) {
		require Plugins::CustomTagImporter::Settings::Basic;
		require Plugins::CustomTagImporter::Settings::TagList;
		Plugins::CustomTagImporter::Settings::Basic->new($class);
		Plugins::CustomTagImporter::Settings::TagList->new($class);
	}
}

sub initPrefs {
	$prefs->init({
		'postscanscheduledelay' => 10,
		'ratingtagmax' => 100,
	});
	$prefs->set('scanningInProgress', 0);
	$prefs->set('scanResult', 0);
	$prefs->setValidate({'validator' => 'intlimit', 'low' => 5, 'high' => 255}, 'ratingtagmax');

	$prefs->setChange(\&Plugins::CustomTagImporter::Importer::toggleUseImporter, 'autorescan');
	$prefs->setChange(sub {
			main::DEBUGLOG && $log->is_debug && $log->debug('Change in selected title formats detected. Refreshing titleformats.');
			refreshTitleFormats();
			Slim::Music::Info::clearFormatDisplayCache();
		}, 'selectedtitleformats');
}

sub getCustomBrowseTemplates {
	my $client = shift;
	my $pluginVersion = shift;

	my $CBversion = Slim::Utils::PluginManager->isEnabled('Plugins::CustomBrowseMenus::Plugin') ? 'CustomBrowseMenus' : 'CustomBrowse';
	return Plugins::CustomTagImporter::CBTemplateReader::getTemplates($client, 'CustomTagImporter', $pluginVersion, 'PluginCache/'.$CBversion, 'CBMenuTemplates', 'xml');
}

sub getCustomBrowseTemplateData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;

	my $data = Plugins::CustomTagImporter::CBTemplateReader::readTemplateData('CustomTagImporter', 'CBMenuTemplates', $templateItem->{'id'});
	return $data;
}

sub getCustomBrowseContextTemplates {
	my $client = shift;
	my $pluginVersion = shift;
	my $CBversion = Slim::Utils::PluginManager->isEnabled('Plugins::CustomBrowseMenus::Plugin') ? 'CustomBrowseMenus' : 'CustomBrowse';
	return Plugins::CustomTagImporter::CBTemplateReader::getTemplates($client, 'CustomTagImporter', $pluginVersion, 'PluginCache/'.$CBversion, 'CBContextMenuTemplates', 'xml');
}

sub getCustomBrowseContextTemplateData {
	my $client = shift;
	my $templateItem = shift;
	my $parameterValues = shift;

	my $data = Plugins::CustomTagImporter::CBTemplateReader::readTemplateData('CustomTagImporter', 'CBContextMenuTemplates', $templateItem->{'id'});
	return $data;
}

sub getCustomSkipFilterTypes {
	my @result = ();

	my %customtag = (
		'id' => 'customtagimporter_customtag_customtag',
		'name' => 'Custom tag',
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
		'description' => 'Skip songs which do not have a specific custom tag',
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
	return \@result;
}

sub checkCustomSkipFilterType {
	my $client = shift;
	my $filter = shift;
	my $track = shift;

	my $currentTime = time();
	my $parameters = $filter->{'parameter'};
	my $result = 0;
	my $dbh = Slim::Schema->storage->dbh();
	if ($filter->{'id'} eq 'customtagimporter_customtag_customtag') {
		my $matching = 0;
		for my $parameter (@{$parameters}) {
			if ($parameter->{'id'} eq 'customtag') {
				my $values = $parameter->{'value'};
				my $customtag = $values->[0] if (defined($values) && scalar(@{$values}) > 0);

				my $sth = $dbh->prepare("select track from customtagimporter_track_attributes where track = ? and attr = ?");
				eval {
					$sth->bind_param(1, $track->id);
					$sth->bind_param(2, $customtag);
					$sth->execute();
					if ($sth->fetch()) {
						$result = 1;
					}
				};
				if ($@) {
					$log->error("Error executing SQL: $@\n$DBI::errstr");
				}
				$sth->finish();
				last;
			}
		}
	} elsif ($filter->{'id'} eq 'customtagimporter_customtag_notcustomtag') {
		my $matching = 0;
		for my $parameter (@{$parameters}) {
			if ($parameter->{'id'} eq 'customtag') {
				my $values = $parameter->{'value'};
				my $customtag = $values->[0] if (defined($values) && scalar(@{$values}) > 0);

				my $sth = $dbh->prepare("select track from customtagimporter_track_attributes where track = ? and attr = ?");
				$result = 1;
				eval {
					$sth->bind_param(1, $track->id);
					$sth->bind_param(2, $customtag);
					$sth->execute();
					if ($sth->fetch()) {
						$result = 0;
					}
				};
				if ($@) {
					$result = 0;
					$log->error("Error executing SQL: $@\n$DBI::errstr");
				}
				$sth->finish();
				last;
			}
		}
	}

	return $result;
}

sub addTitleFormat {
	my $titleformat = shift;
	my $titleFormats = $serverPrefs->get('titleFormat');

	foreach my $format (@{$titleFormats}) {
		if ($titleformat eq $format) {
			return;
		}
	}
	main::DEBUGLOG && $log->is_debug && $log->debug("Adding: $titleformat");
	push @{$titleFormats}, $titleformat;
	$serverPrefs->set('titleFormat', $titleFormats);
}

sub refreshTitleFormats {
	my $titleformats = $prefs->get('selectedtitleformats');
	my $availableTitleFormatOptions = getAvailableTitleFormats();
	my $newUnicodeHandling = UNIVERSAL::can("Slim::Utils::Unicode", "hasEDD") ? 1 : 0;

	for my $format (@{$titleformats}) {
		if ($format && $availableTitleFormatOptions->{$format}) {
			Slim::Music::TitleFormatter::addFormat("CTI_$format",
				sub {
					main::DEBUGLOG && $log->is_debug && $log->debug("Retreiving title format: $format");

					my $track = shift;

					# get local track if unblessed
					if ($track && !blessed($track)) {
						main::DEBUGLOG && $log->is_debug && $log->debug('Track is not blessed');
						my $trackObj = Slim::Schema->find('Track', $track->{id});
						if (blessed($trackObj)) {
							$track = $trackObj;
						} else {
							my $trackURL = $track->{'url'};
							main::DEBUGLOG && $log->is_debug && $log->debug('Slim::Schema->find found no blessed track object for id. Trying to retrieve track object with url: '.Data::Dump::dump($trackURL));
							if (defined ($trackURL)) {
								if (Slim::Music::Info::isRemoteURL($trackURL) == 1) {
									$track = Slim::Schema->_retrieveTrack($trackURL);
									main::DEBUGLOG && $log->is_debug && $log->debug('Track is remote. Retrieved trackObj = '.Data::Dump::dump($track));
								} else {
									$track = Slim::Schema->rs('Track')->single({'url' => $trackURL});
									main::DEBUGLOG && $log->is_debug && $log->debug('Track is not remote. TrackObj for url = '.Data::Dump::dump($track));
								}
							} else {
								return '';
							}
						}
					}

					my $result = '';
					if ($track) {
						eval {
							my $dbh = getCurrentDBH();
							my $sth = $dbh->prepare("SELECT value from customtagimporter_track_attributes where type = 'customtag' and attr = ? and track = ? group by value");
							$sth->bind_param(1, $format);
							$sth->bind_param(2, $track->id);
							$sth->execute();
							my $value;
							$sth->bind_col(1, \$value);
							while ($sth->fetch()) {
								$result .= ', ' if $result;
								$value = $newUnicodeHandling ? Slim::Utils::Unicode::utf8decode($value, 'utf8') : Slim::Utils::Unicode::utf8on(Slim::Utils::Unicode::utf8decode($value, 'utf8'));
								$result .= $value;
							}
							$sth->finish();
						};
						if ($@) {
							$log->error("Database error: $DBI::errstr\n$@");
						}
						main::DEBUGLOG && $log->is_debug && $log->debug("Finished retrieving title format: $format = $result");
					}
					return $result;
				});
			addTitleFormat("TRACKNUM. TITLE - CTI_$format");
		} elsif ($format) {
			Slim::Menu::TrackInfo->deregisterInfoProvider("CTI_$format");
		}
	}
}

sub getAvailableTitleFormats {
	my $dbh = getCurrentDBH();
	my %result = ();
	my %selectedTitleFormats = ();
	my $titleformats = $prefs->get('selectedtitleformats');
	main::DEBUGLOG && $log->is_debug && $log->debug('selected title formats = '.Data::Dump::dump($titleformats));
	for my $format (@{$titleformats}) {
		$selectedTitleFormats{uc($format)} = 1 if $format;
	}

	my $sth = $dbh->prepare("SELECT attr from customtagimporter_track_attributes where type = 'customtag' group by attr");
	my $attr;
	$sth->execute();
	$sth->bind_col(1,\$attr);
	while ($sth->fetch()) {
		$result{uc($attr)} = $selectedTitleFormats{uc($attr)} ? 1 : 0;
	}
	$sth->finish();
	return \%result;
}

sub _setRefreshCBTimer {
	main::DEBUGLOG && $log->is_debug && $log->debug('Killing existing timers for post-scan refresh to prevent multiple calls');
	Slim::Utils::Timers::killOneTimer(undef, \&delayedPostScanRefresh);
	main::DEBUGLOG && $log->is_debug && $log->debug('Scheduling a delayed post-scan refresh');
	Slim::Utils::Timers::setTimer(undef, time() + 2, \&delayedPostScanRefresh);
}

sub delayedPostScanRefresh {
	if (Slim::Music::Import->stillScanning) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Scan in progress. Waiting for current scan to finish.');
		_setRefreshCBTimer();
	} else {
		main::DEBUGLOG && $log->is_debug && $log->debug('Starting post-scan database table refresh.');
		refreshTitleFormats();
		Slim::Music::Info::clearFormatDisplayCache();
	}
}

1;
