#
# Custom Tag Importer
# (c) 2021 AF
# Licensed under the GPLv3 - see LICENSE file
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
	my $class = shift;
	main::DEBUGLOG && $log->is_debug && $log->debug('Starting importer');

	# LMS passes a single folder to the scanner as its last argument if only that folder is rescanned
	if (main::SCANNER && defined $ARGV[-1] && $ARGV[-1] ne 'onlinelibrary' && -d $ARGV[-1]) {
		main::INFOLOG && $log->is_info && $log->info('LMS rescans a single folder only, skipping CTI auto rescan');
	} elsif ($prefs->get('autorescan')) {
		main::DEBUGLOG && $log->is_debug && $log->debug('Starting CTI auto rescan');
		rescan(1);
	}
	Slim::Music::Import->endImporter($class);
}

1;
