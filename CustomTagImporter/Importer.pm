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

package Plugins::CustomTagImporter::Importer;

use strict;
use warnings;
use utf8;

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Schema;
use Plugins::CustomTagImporter::Common ':all';

my $prefs = preferences('plugin.customtagimporter');
my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log::logger('plugin.customtagimporter');

sub initPlugin {
	main::DEBUGLOG && $log->is_debug && $log->debug('Importer module init');
	toggleUseImporter();
}

sub toggleUseImporter {
	if ($prefs->get('autorescan')) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Enabling importer');
		Slim::Music::Import->addImporter('Plugins::CustomTagImporter::Importer', {
			'type' => 'post',
			'weight' => 999,
			'use' => 1,
		});
	} else {
		main::DEBUGLOG && $log->is_debug && $log->debug('Disabling importer');
		Slim::Music::Import->useImporter('Plugins::CustomTagImporter::Importer', 0);
	}
}

sub startScan {
	main::DEBUGLOG && $log->is_debug && $log->debug('Starting importer');
	if ($prefs->get('autorescan')) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Starting CTI auto rescan');
		rescan(1);
	}
	Slim::Music::Import->endImporter(__PACKAGE__);
}

1;
