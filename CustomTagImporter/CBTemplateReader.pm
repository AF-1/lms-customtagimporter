#
# Custom Tag Importer
# (c) 2021 AF
# Licensed under the GPLv3 - see LICENSE file
#

package Plugins::CustomTagImporter::CBTemplateReader;

use strict;
use warnings;
use utf8;

use Slim::Player::Client;
use File::Spec::Functions qw(:ALL);
use Slim::Utils::Prefs;
use Slim::Utils::Misc;
use File::Slurp;
use XML::Simple;
use FindBin qw($Bin);
use Cache::Cache qw($EXPIRES_NEVER);

my $serverPrefs = preferences('server');
my $log = Slim::Utils::Log::logger('plugin.customtagimporter');

sub getTemplates {
	my ($client, $mainPlugin, $pluginVersion, $cachePrefix, $directory, $extension, $templateType, $contentType, $resultType, $raw) = @_;

	my ($cacheName, $cache);
	if ($cachePrefix) {
		$cacheName = $cachePrefix."/".$mainPlugin."/".$directory;
		my $cacheVersion = $pluginVersion;
		$cacheVersion =~ s/^.*\.([^\.]+)$/$1/;
		$cache = Slim::Utils::Cache->new($cachePrefix, $cacheVersion);
	}

	my @result = ();
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');
	if (!defined($templateType)) {
		$templateType = 'template';
	}
	if (!defined($contentType)) {
		$contentType = $templateType;
	}
	if (!defined($resultType)) {
		$resultType = $templateType;
	}

	my $cacheItems;
	if (defined($cache)) {
		$cacheItems = $cache->get($cacheName);
		if (!defined($cacheItems)) {
			my %noItems = ();
			my %empty = (
				'items' => \%noItems,
				'timestamp' => undef
			);
			$cacheItems = \%empty;
		}
	}
	for my $plugindir (@pluginDirs) {
		my $templateDir = catdir($plugindir, $mainPlugin, $directory);
		next unless -d $templateDir;
		my @dircontents = Slim::Utils::Misc::readDirectory($templateDir, $extension);
		for my $item (@dircontents) {
			next if -d catdir($templateDir, $item);
			my $templateId = $item;
			$templateId =~ s/\.$extension$//;
			my $timestamp = (stat (catdir($templateDir, $item)) )[9];
			if (defined($cacheItems)) {
				if (defined($cacheItems->{'items'}->{$item}) && $cacheItems->{'items'}->{$item}->{'timestamp'}>$timestamp) {
					main::DEBUGLOG && $log->is_debug && $log->debug("Reading $item from cache");
					push @result, $cacheItems->{'items'}->{$item}->{'data'};
					next;
				}
			}
			my $template = readTemplateConfiguration($templateId,catdir($templateDir,$item),$templateType,$raw);
			if (defined($template)) {
				my %templateItem = (
					'id' => $templateId,
					'type' => $resultType,
					'timestamp' => $timestamp,
					$contentType => $template
				);
				if (defined($cacheItems) && defined($timestamp)) {
					my %entry = (
						'data' => \%templateItem,
						'timestamp' => $timestamp,
					);
					delete $cacheItems->{'items'}->{$item};
					$cacheItems->{'items'}->{$item} = \%entry;
				}
				push @result,\%templateItem;
			}
		}
	}
	if (defined($cacheItems)) {
		$cacheItems->{'timestamp'} = time();
		$cache->set($cacheName, $cacheItems, $EXPIRES_NEVER);
	}
	return \@result;
}

sub readTemplateData {
	my ($mainPlugin, $dir, $template, $extension) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug("Loading template data for $template");

	if (!defined($extension)) {
		$extension = "template";
	}
	my @pluginDirs = Slim::Utils::OSDetect::dirsFor('Plugins');

	my $templateDir;
	for my $plugindir (@pluginDirs) {
		next unless -d catdir($plugindir, $mainPlugin, $dir);
		$templateDir = catdir($plugindir, $mainPlugin, $dir);
	}

	my $path = catfile($templateDir, $template.".".$extension);

	# read_file from File::Slurp
	my $content = eval { read_file($path) };
	return $content;
}

sub readTemplateConfiguration {
	my ($templateId, $path, $templateType, $raw) = @_;
	main::DEBUGLOG && $log->is_debug && $log->debug("Loading template configuration for $templateId");

	# read_file from File::Slurp
	my $content = eval { read_file($path) };
	my $template;
	if ($raw) {
		my $parsedTemplate = parseTemplateContent($templateId, $templateType, $content);
		if ($parsedTemplate) {
			$template = $content;
		}
	} else {
		$template = parseTemplateContent($templateId, $templateType, $content);
	}
	return $template;
}

sub parseTemplateContent {
	my ($id, $templateType, $content) = @_;

	my $template;
	if ($content) {
		$content = Slim::Utils::Unicode::utf8decode($content, 'utf8');
		my $xml = eval { XMLin($content, forcearray => ["parameter"], keyattr => []) };
		main::DEBUGLOG && $log->is_debug && $log->debug('xml = '.Data::Dump::dump($xml));
		if ($@) {
			$log->error("Failed to parse $templateType configuration for $id because:\n$@");
		} else {
			if (defined($xml->{$templateType})) {
				$xml->{$templateType}->{'id'} = $id;
				$template = $xml->{$templateType};
			}
		}

		# Release content
		undef $content;

	} else {
		$log->error("Unable to read $templateType configuration for $id" . ($@ ? ": $@" : ''));
	}
	return $template;
}

1;
