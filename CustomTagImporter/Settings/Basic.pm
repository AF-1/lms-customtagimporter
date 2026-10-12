#
# Custom Tag Importer
# (c) 2021 AF
# Licensed under the GPLv3 - see LICENSE file
#

package Plugins::CustomTagImporter::Settings::Basic;

use strict;
use warnings;
use utf8;
use base qw(Plugins::CustomTagImporter::Settings::BaseSettings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Plugins::CustomTagImporter::Common ':all';

my $prefs = preferences('plugin.customtagimporter');
my $log = logger('plugin.customtagimporter');

sub new {
	my ($class, $plugin) = @_;
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
	return [{ 'name' => Slim::Utils::Strings::string('PLUGIN_CUSTOMTAGIMPORTER_CUSTOMTAGS'), 'page' => page() }];
}

sub prefs {
	return ($prefs, qw(customtags singlecustomtags selectedtitleformats customtagsmapping customtagrawmp3tags ratingtags ratingtagmax writeratingstodb autorescan dumptagnames));
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	my $result;

	if ($paramRef->{'saveSettings'}) {
		$paramRef->{'pref_customtags'} = trim_leadtail($paramRef->{'pref_customtags'}) if $paramRef->{'pref_customtags'};
		$paramRef->{'pref_ratingtags'} = trim_leadtail($paramRef->{'pref_ratingtags'}) if $paramRef->{'pref_ratingtags'};
		$result = $class->SUPER::handler($client, $paramRef);
	}

	my $action = $paramRef->{'rescan'} ? \&Plugins::CustomTagImporter::Common::rescan
		: $paramRef->{'abortscan'} ? \&Plugins::CustomTagImporter::Common::abortScan
		: $paramRef->{'resetratingsto_ctivalues'} ? \&Plugins::CustomTagImporter::Common::resetRatingsToCTIvalues
		: undef;

	# if a button was pressed without saving first, save the settings now. Otherwise just show the page.
	if (!$paramRef->{'saveSettings'}) {
		$paramRef->{'saveSettings'} = 1 if $action;
		$result = $class->SUPER::handler($client, $paramRef);
	}
	$action->() if $action;

	return $result;
}

sub beforeRender {
	my ($class, $paramRef) = @_;
	$paramRef->{'squeezebox_server_jsondatareq'} = '/jsonrpc.js';

	# count tracks with rating tags and values > 0
	$paramRef->{'ratedtrackcount'} = Slim::Schema->storage->dbh()->selectrow_array("select count(*) from customtagimporter_track_attributes where type = 'rating' and ifnull(value, 0) > 0") || 0;

	# disable manual rating if active LMS scan
	$paramRef->{'activelmsscan'} = 1 if (!Slim::Schema::hasLibrary() || Slim::Music::Import->stillScanning);
	$paramRef->{'activectiscan'} = 1 if $prefs->get('scanningInProgress');
}

1;
