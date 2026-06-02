#
# Custom Tag Importer
#
# (c) 2021 AF
#
# Portions of code derived from the CustomScan plugin by (c) 2006 Erland Isaksson
#
# Licensed under the GPLv3 - see LICENSE file
#

package Plugins::CustomTagImporter::Settings::TagList;

use strict;
use warnings;
use utf8;

use base qw(Plugins::CustomTagImporter::Settings::BaseSettings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use Slim::Utils::Strings;
use Slim::Utils::Strings qw(string cstring);

my $prefs = preferences('plugin.customtagimporter');
my $log = logger('plugin.customtagimporter');

my $plugin;

sub new {
	my $class = shift;
	$plugin = shift;
	$class->SUPER::new($plugin);
}

sub name {
	return Slim::Web::HTTP::CSRF->protectName('PLUGIN_CUSTOMTAGIMPORTER_TAGLIST');
}

sub page {
	return Slim::Web::HTTP::CSRF->protectURI('plugins/CustomTagImporter/settings/taglist.html');
}

sub currentPage {
	return name();
}

sub pages {
	my %page = (
		'name' => name(),
		'page' => page(),
	);
	my @pages = (\%page);
	return \@pages;
}

sub prefs {
	return ($prefs);
}

sub handler {
	my ($class, $client, $paramRef) = @_;
	return $class->SUPER::handler($client, $paramRef);
}

sub beforeRender {
	my ($class, $paramRef) = @_;
	my $dbh = Slim::Schema->storage->dbh();
	my $customTagSql = "select attr,value,count(distinct id) from customtagimporter_track_attributes where type='customtag' group by value";
	my %attrValHash = ();

	eval {
		my $sth = $dbh->prepare($customTagSql);
		main::DEBUGLOG && $log->is_debug && $log->debug("Executing: $customTagSql");
		$sth->execute() or do {
			$log->error("Error executing: $customTagSql");
			$customTagSql = undef;
		};

		my $attr;
		my $value;
		my $valCount;
		$sth->bind_col(1, \$attr);
		$sth->bind_col(2, \$value);
		$sth->bind_col(3, \$valCount);
		while ($sth->fetch()) {
			$attrValHash{$attr}{$value} = $valCount;
		}
		$sth->finish();
	};
	if ($@) {
		$log->error("Running: $customTagSql got error:\n$@");
	}

	my %attrTotalCount = ();
	if (scalar keys %attrValHash > 0) {
		foreach my $thisAttr (keys %attrValHash) {
			my $count = 0;

			eval {
				my $attrCountSth = $dbh->prepare("SELECT count(distinct track) FROM customtagimporter_track_attributes WHERE type = 'customtag' AND attr = ?");
				$attrCountSth->execute($thisAttr);
				$count = $attrCountSth->fetchrow || 0;
				$attrCountSth->finish();
			};
			if ($@) {
				$log->error("Error getting track count for attr '$thisAttr': $@");
			}
			main::DEBUGLOG && $log->is_debug && $log->debug("count for $thisAttr = " . $count);
			$attrTotalCount{$thisAttr} = $count;
		}
	}

	main::DEBUGLOG && $log->is_debug && $log->debug('attrValHash = '.Data::Dump::dump(\%attrValHash));
	main::DEBUGLOG && $log->is_debug && $log->debug('attrTotalCount = '.Data::Dump::dump(\%attrTotalCount));
	main::DEBUGLOG && $log->is_debug && $log->debug('customtagcount = '.scalar keys %attrValHash);

	$paramRef->{'attrvaluelist'} = \%attrValHash;
	$paramRef->{'attrTotalCount'} = \%attrTotalCount;
	$paramRef->{'customtagcount'} = scalar keys %attrValHash;
}

1;
