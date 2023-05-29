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

package Plugins::CustomTagImporter::Settings::Basic;

use strict;
use warnings;
use utf8;
use base qw(Plugins::CustomTagImporter::Settings::BaseSettings);

use File::Basename;
use File::Next;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Data::Dumper;

my $prefs = preferences('plugin.customtagimporter');
my $log = logger('plugin.customtagimporter');
my $plugin;

sub new {
	my $class = shift;
	$plugin = shift;
	$class->SUPER::new($plugin,1);
}

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_CUSTOMTAGIMPORTER');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/CustomTagImporter/settings/basic.html');
}

sub currentPage {
	return Slim::Utils::Strings::string('PLUGIN_CUSTOMTAGIMPORTER_CUSTOMTAGS');
}

sub pages {
	my %page = (
		'name' => Slim::Utils::Strings::string('PLUGIN_CUSTOMTAGIMPORTER_CUSTOMTAGS'),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub prefs {
	return ($prefs, qw(customtags singlecustomtags selectedtitleformats customtagsmapping customtagrawmp3tags ratingtags ratingtagmax writeratingstodb autorescan dumptagnames));
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	my $result = undef;
	my $callHandler = 1;
	if ($paramRef->{'saveSettings'}) {
		if ($paramRef->{'pref_selectedtitleformats'} && ref($paramRef->{'pref_selectedtitleformats'}) ne 'ARRAY') {
			$paramRef->{'pref_selectedtitleformats'} = [$paramRef->{'pref_selectedtitleformats'}];
		}

		$paramRef->{'pref_customtags'} = trim_leadtail($paramRef->{'pref_customtags'}) if $paramRef->{'pref_customtags'};
		$paramRef->{'pref_ratingtags'} = trim_leadtail($paramRef->{'pref_ratingtags'}) if $paramRef->{'pref_ratingtags'};

		$result = $class->SUPER::handler($client, $paramRef);
		$callHandler = 0;
	}
	if ($paramRef->{'rescan'}) {
		if ($callHandler) {
			$paramRef->{'saveSettings'} = 1;
			$result = $class->SUPER::handler($client, $paramRef);
		}
		Plugins::CustomTagImporter::Common::rescan();
	} elsif ($paramRef->{'abortscan'}) {
		if ($callHandler) {
			$paramRef->{'saveSettings'} = 1;
			$result = $class->SUPER::handler($client, $paramRef);
		}
		Plugins::CustomTagImporter::Common::abortScan();
	} elsif ($paramRef->{'resetratingsto_ctivalues'}) {
		if ($callHandler) {
			$paramRef->{'saveSettings'} = 1;
			$result = $class->SUPER::handler($client, $paramRef);
		}
		Plugins::CustomTagImporter::Common::resetRatingsToCTIvalues();
	} elsif ($callHandler) {
		$result = $class->SUPER::handler($client, $paramRef);
	}

	return $result;
}

sub beforeRender {
	my ($class, $paramRef) = @_;
	my $host = $paramRef->{host} || (Slim::Utils::Network::serverAddr() . ':' . preferences('server')->get('httpport'));
	$paramRef->{'squeezebox_server_jsondatareq'} = 'http://' . $host . '/jsonrpc.js';

	# count tracks with rating tags and values > 0
	my $ratedCTItrackCountSQL = "select count(*) from customtagimporter_track_attributes where customtagimporter_track_attributes.type = 'rating' and ifnull(customtagimporter_track_attributes.value, 0) > 0";
	my $dbh = Slim::Schema->storage->dbh();
	my $sth = $dbh->prepare($ratedCTItrackCountSQL);
	$sth->execute();
	my $ratedCTItrackCount = $sth->fetchrow || 0;
	$sth->finish();
	$paramRef->{'ratedtrackcount'} = $ratedCTItrackCount;

	# disable manual rating if active LMS scan
	$paramRef->{'activelmsscan'} = 1 if (!Slim::Schema::hasLibrary() || Slim::Music::Import->stillScanning);
	$paramRef->{'activectiscan'} = 1 if $prefs->get('scanningInProgress');

	$paramRef->{'titleformatOptions'} = Plugins::CustomTagImporter::Plugin::getAvailableTitleFormats();
	$log->debug('titleformatOptions = '.Dumper($paramRef->{'titleformatOptions'}));
}

sub trim_leadtail {
	my ($str) = @_;
	$str =~ s{^\s+}{};
	$str =~ s{\s+$}{};
	return $str;
}

1;
